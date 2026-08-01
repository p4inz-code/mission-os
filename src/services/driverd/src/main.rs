//! mission-driverd — Mission OS Driver Management Service
//!
//! Systemd service binary for the hardware driver management daemon.
//!
//! ## Startup Flow
//!
//! 1. Load configuration from `/etc/mission/driverd.toml`
//! 2. Initialize mission-core logging
//! 3. Initialize audit backend
//! 4. Connect to D-Bus system bus
//! 5. Initialize PolKit authorizer (requires D-Bus connection)
//! 6. Initialize authorization checker (with PolKit backend)
//! 7. Initialize driver inventory (scan hardware via sysfs)
//! 8. Initialize package store and trusted key store
//! 9. Initialize signature verifier
//! 10. Initialize execution engine
//! 11. Register D-Bus interfaces at `/org/mission/Driver1`
//! 12. Request well-known name `org.mission.Driver1`
//! 13. Emit initial `HealthChanged` signal
//! 14. Enter async event loop with periodic hardware polling
//!
//! ## Security
//!
//! - Configuration loading uses safe defaults if the config file is missing.
//! - The service does NOT start if D-Bus connection fails.
//! - No secrets are loaded from configuration.
//! - All privileged D-Bus methods require PolKit authorization.
//! - The service fails closed: if authorization state is unknown, deny.
//! - M2-D: All driver operations are verified, authorized, conflict-checked.
//! - PolKit is initialized after D-Bus connect and wired into the Authorizer.

use std::path::Path;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use mission_driverd::audit::LogAuditBackend;
use mission_driverd::authz::Authorizer;
use mission_driverd::config::load_config;
use mission_driverd::dbus::{
    self, AppState, DriverInterface, InventoryInterface, ManagementInterface,
};
use mission_driverd::execution::DriverExecutionEngine;
use mission_driverd::hwdetect::UdevMonitor;
use mission_driverd::inventory::InventoryScanner;
use mission_driverd::package::PackageStore;
use mission_driverd::polkit::PolKitAuthorizer;
use mission_driverd::verification::{SignatureVerifier, TrustedKeyStore};

/// Default configuration path.
const CONFIG_PATH: &str = "/etc/mission/driverd.toml";

/// Health check interval in seconds.
const HEALTH_CHECK_INTERVAL_SECS: u64 = 60;

/// Hardware event polling interval in seconds.
const HARDWARE_POLL_INTERVAL_SECS: u64 = 10;

#[tokio::main]
async fn main() {
    // Parse config path from environment or use default
    let config_path =
        std::env::var("MISSION_DRIVERD_CONFIG").unwrap_or_else(|_| CONFIG_PATH.to_string());

    // Load configuration (falls back to safe defaults if file missing)
    let config = load_config(Path::new(&config_path));

    eprintln!(
        "[driverd] starting — config={}, audit={}, scan_interval={}s, \
         package_store={}, verification_required={}",
        config_path,
        config.audit.enabled,
        config.inventory.scan_interval_secs,
        config.package_store.store_path,
        config.verification.require_signature,
    );

    // Check environment for development authorization bypass
    let allow_unauthorized = std::env::var("MISSION_ALLOW_UNAUTHORIZED").is_ok();
    if allow_unauthorized {
        eprintln!(
            "[driverd] WARNING: MISSION_ALLOW_UNAUTHORIZED is set — \
             authorization checks are bypassed. Do NOT use in production."
        );
    }

    // Initialize audit backend
    let audit_backend: Box<dyn mission_driverd::audit::AuditBackend> = Box::new(LogAuditBackend);

    // ── Connect to D-Bus system bus (required before PolKit init) ──
    let conn = match zbus::Connection::system().await {
        Ok(conn) => conn,
        Err(e) => {
            eprintln!(
                "[driverd] FATAL: cannot connect to D-Bus system bus: {e} — \
                 is dbus-daemon running? Exiting."
            );
            std::process::exit(1);
        }
    };
    eprintln!("[driverd] connected to D-Bus system bus");

    // ── Initialize PolKit authorizer with the system bus connection ──
    let polkit = std::sync::Arc::new(PolKitAuthorizer::new(
        Some(conn.clone()),
        Box::new(LogAuditBackend),
        allow_unauthorized,
    ));
    eprintln!("[driverd] PolKit authorizer initialized");

    // ── Initialize authorizer with real PolKit backend ──
    let authorizer = Authorizer::new(allow_unauthorized, Box::new(LogAuditBackend), Some(polkit));

    // ── Initialize driver inventory scanner with real hardware detection (M2-D) ──
    let mut scanner = InventoryScanner::new();
    if config.inventory.auto_detect_on_start {
        match scanner.scan_system() {
            Ok(()) => {
                eprintln!(
                    "[driverd] inventory initialized — {} drivers, {} hardware devices",
                    scanner.inventory().drivers.len(),
                    scanner.inventory().devices.len(),
                );
                // Match drivers to discovered hardware
                scanner.match_drivers_to_hardware();
            }
            Err(e) => {
                eprintln!("[driverd] initial inventory scan failed: {e}");
            }
        }
    }

    // ── Initialize package store (M2-D) ──
    let package_store = PackageStore::new(&config.package_store);
    eprintln!(
        "[driverd] package store initialized at {}",
        config.package_store.store_path
    );

    // ── Initialize trusted key store (M2-D) ──
    let key_store_path = Path::new(&config.verification.key_store_path);
    let key_store = TrustedKeyStore::new(key_store_path.to_path_buf());
    eprintln!(
        "[driverd] trusted key store — {} keys loaded from {}",
        key_store.key_count(),
        config.verification.key_store_path
    );

    // ── Initialize signature verifier (M2-D) ──
    let signature_verifier = SignatureVerifier::new(key_store, config.verification.allow_unsigned);

    // ── Initialize execution engine (M2-D) ──
    // clone_audit shares the PolKit authorizer via Arc, so the execution engine's
    // defense-in-depth authorization check uses the same real PolKit backend
    // as the D-Bus handler level.
    let execution_engine = DriverExecutionEngine::new(
        authorizer.clone_audit(Box::new(LogAuditBackend)),
        Box::new(LogAuditBackend),
        package_store,
        signature_verifier,
        allow_unauthorized,
    );
    eprintln!("[driverd] execution engine initialized");

    // ── Initialize udev event monitor (M2-D) ──
    let udev_monitor = UdevMonitor::new();

    // ── Initialize source registry from configuration (M2-E) ──
    let source_registry = mission_driverd::source::SourceRegistry::from_configs(
        mission_driverd::source::default_sources(),
    )
    .unwrap_or_else(|_| mission_driverd::source::SourceRegistry::empty());
    eprintln!(
        "[driverd] source registry initialized — {} sources",
        source_registry.source_count()
    );

    // ── Initialize shared application state ──
    // ── Initialize cache manager (M2-F) ──
    let cache_manager =
        mission_driverd::cache::CacheManager::new(mission_driverd::cache::CacheConfig::new(
            std::path::PathBuf::from("/var/cache/mission/drivers"),
        ));
    eprintln!("[driverd] cache manager initialized at /var/cache/mission/drivers");

    // ── Initialize repository manager (M2-F) ──
    let repository_manager = mission_driverd::repository::RepositoryManager::new(
        mission_driverd::repository::FreshnessPolicy::default(),
        Box::new(LogAuditBackend),
    );
    eprintln!("[driverd] repository metadata manager initialized");

    // ── Initialize download manager (M2-F) ──
    let download_fetcher = mission_driverd::fetch::PackageFetcher::new(
        mission_driverd::fetch::DownloadConfig::default(),
    );
    let download_manager = mission_driverd::download::DownloadManager::new(
        download_fetcher,
        mission_driverd::download::RetryPolicy::default(),
        mission_driverd::download::ResumeManager::new(std::path::PathBuf::from(
            "/var/cache/mission/drivers/partials",
        )),
        Box::new(LogAuditBackend),
    );
    eprintln!("[driverd] download manager initialized");

    // ── Initialize shared application state ──
    let state = Arc::new(AppState {
        config,
        authorizer,
        source_registry,
        audit_backend,
        scanner: Mutex::new(scanner),
        execution_engine,
        udev_monitor: Mutex::new(udev_monitor),
        cache_manager,
        repository_manager,
        download_manager,
    });

    // ── Register core interface ──
    let core_iface = DriverInterface::new(state.clone(), conn.clone());
    if let Err(e) = conn.object_server().at(dbus::OBJECT_PATH, core_iface).await {
        eprintln!("[driverd] FATAL: cannot register DriverInterface: {e} — Exiting.");
        std::process::exit(1);
    }

    // ── Register inventory interface ──
    let inv_iface = InventoryInterface::new(state.clone(), conn.clone());
    if let Err(e) = conn.object_server().at(dbus::OBJECT_PATH, inv_iface).await {
        eprintln!("[driverd] FATAL: cannot register InventoryInterface: {e} — Exiting.");
        std::process::exit(1);
    }

    // ── Register management interface ──
    let mgmt_iface = ManagementInterface::new(state.clone(), conn.clone());
    if let Err(e) = conn.object_server().at(dbus::OBJECT_PATH, mgmt_iface).await {
        eprintln!("[driverd] FATAL: cannot register ManagementInterface: {e} — Exiting.");
        std::process::exit(1);
    }

    // ── Request well-known service name ──
    match conn.request_name(dbus::SERVICE_NAME).await {
        Ok(()) => {
            eprintln!("[driverd] acquired D-Bus name: {}", dbus::SERVICE_NAME);
        }
        Err(e) => {
            eprintln!(
                "[driverd] FATAL: cannot request D-Bus name '{}': {e} — Exiting.",
                dbus::SERVICE_NAME
            );
            std::process::exit(1);
        }
    }

    // ── Emit initial HealthChanged signal ──
    dbus::emit_health_changed(&conn, true, "Service started successfully").await;
    eprintln!("[driverd] ready on system bus at {}", dbus::OBJECT_PATH);

    // ── Spawn periodic health check signal task ──
    let health_conn = conn.clone();
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(Duration::from_secs(HEALTH_CHECK_INTERVAL_SECS));
        loop {
            interval.tick().await;
            dbus::emit_health_changed(&health_conn, true, "Service healthy").await;
        }
    });

    // ── Spawn periodic hardware event polling (M2-D) ──
    let poll_state = state.clone();
    let poll_conn = conn.clone();
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(Duration::from_secs(HARDWARE_POLL_INTERVAL_SECS));
        loop {
            interval.tick().await;
            let events = poll_state.poll_hardware_events();
            if !events.is_empty() {
                eprintln!(
                    "[driverd] detected {} hardware events, re-scanning",
                    events.len()
                );
                if let Ok(mut scanner) = poll_state.scanner.lock() {
                    let _ = scanner.scan_system();
                    scanner.match_drivers_to_hardware();
                }
                dbus::emit_inventory_changed(&poll_conn).await;
            }
        }
    });

    // ── Enter the main event loop — pending forever ──
    // zbus handles incoming method calls and signals internally
    std::future::pending::<()>().await;
}
