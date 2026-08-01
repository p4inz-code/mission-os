//! mission-securityd — Mission OS Security Service
//!
//! Systemd service binary for the security policy daemon.
//!
//! ## Startup Flow
//!
//! 1. Load configuration from `/etc/mission/securityd.toml`
//! 2. Initialize mission-core logging
//! 3. Initialize audit backend
//! 4. Initialize authorization checker
//! 5. Connect to D-Bus system bus
//! 6. Register D-Bus interfaces at `/org/mission/Security1`
//! 7. Request well-known name `org.mission.Security1`
//! 8. Emit initial `HealthChanged` signal
//! 9. Enter async event loop
//!
//! ## Security
//!
//! - Configuration loading uses safe defaults if the config file is missing.
//! - The service does NOT start if D-Bus connection fails.
//! - No secrets are loaded from configuration.
//! - All privileged D-Bus methods require PolKit authorization.
//! - The service fails closed: if authorization state is unknown, deny.
//!
//! ## Signal Emission
//!
//! - `HealthChanged` signal emitted on startup and periodically every 60s.
//! - `SecurityEvent` signal emitted for security-relevant events.

use std::path::Path;
use std::sync::Arc;
use std::time::Duration;

use mission_securityd::audit::LogAuditBackend;
use mission_securityd::authz::Authorizer;
use mission_securityd::config::load_config;
use mission_securityd::dbus::{
    self, AppState, AuditInterface, FirewallInterface, SecurityInterface,
};

/// Default configuration path.
const CONFIG_PATH: &str = "/etc/mission/securityd.toml";

/// Health check interval in seconds.
const HEALTH_CHECK_INTERVAL_SECS: u64 = 60;

#[tokio::main]
async fn main() {
    // Parse config path from environment or use default
    let config_path =
        std::env::var("MISSION_SECURITYD_CONFIG").unwrap_or_else(|_| CONFIG_PATH.to_string());

    // Load configuration (falls back to safe defaults if file missing)
    let config = load_config(Path::new(&config_path));

    eprintln!(
        "[securityd] starting — config={}, profile={:?}, audit={}",
        config_path, config.default_firewall_profile, config.audit.enabled
    );

    // Check environment for development authorization bypass
    let allow_unauthorized = std::env::var("MISSION_ALLOW_UNAUTHORIZED").is_ok();
    if allow_unauthorized {
        eprintln!(
            "[securityd] WARNING: MISSION_ALLOW_UNAUTHORIZED is set — \
             authorization checks are bypassed. Do NOT use in production."
        );
    }

    // Initialize audit backend
    let audit_backend: Box<dyn mission_securityd::audit::AuditBackend> = Box::new(LogAuditBackend);

    // Initialize authorizer
    let authorizer = Authorizer::new(allow_unauthorized, Box::new(LogAuditBackend));

    // Initialize shared application state
    let state = Arc::new(AppState {
        config,
        authorizer,
        audit_backend,
    });

    // Connect to D-Bus system bus
    let conn = match zbus::Connection::system().await {
        Ok(conn) => conn,
        Err(e) => {
            eprintln!(
                "[securityd] FATAL: cannot connect to D-Bus system bus: {e} — \
                 is dbus-daemon running? Exiting."
            );
            std::process::exit(1);
        }
    };
    eprintln!("[securityd] connected to D-Bus system bus");

    // Clone connection for each interface registration
    let iface_conn = conn.clone();

    // Register core interface (consumes iface_conn)
    let core_iface = SecurityInterface::new(state.clone(), iface_conn);
    if let Err(e) = conn.object_server().at(dbus::OBJECT_PATH, core_iface).await {
        eprintln!("[securityd] FATAL: cannot register SecurityInterface: {e} — Exiting.");
        std::process::exit(1);
    }

    // Register firewall interface
    let fw_iface = FirewallInterface::new(state.clone(), conn.clone());
    if let Err(e) = conn.object_server().at(dbus::OBJECT_PATH, fw_iface).await {
        eprintln!("[securityd] FATAL: cannot register FirewallInterface: {e} — Exiting.");
        std::process::exit(1);
    }

    // Register audit interface
    let audit_iface = AuditInterface::new(state, conn.clone());
    if let Err(e) = conn
        .object_server()
        .at(dbus::OBJECT_PATH, audit_iface)
        .await
    {
        eprintln!("[securityd] FATAL: cannot register AuditInterface: {e} — Exiting.");
        std::process::exit(1);
    }

    // Request well-known service name
    match conn.request_name(dbus::SERVICE_NAME).await {
        Ok(()) => {
            eprintln!("[securityd] acquired D-Bus name: {}", dbus::SERVICE_NAME);
        }
        Err(e) => {
            eprintln!(
                "[securityd] FATAL: cannot request D-Bus name '{}': {e} — Exiting.",
                dbus::SERVICE_NAME
            );
            std::process::exit(1);
        }
    }

    // Emit initial HealthChanged signal
    dbus::emit_health_changed(&conn, true, "Service started successfully").await;
    eprintln!("[securityd] ready on system bus at {}", dbus::OBJECT_PATH);

    // Spawn periodic health check signal task
    let health_conn = conn.clone();
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(Duration::from_secs(HEALTH_CHECK_INTERVAL_SECS));
        loop {
            interval.tick().await;
            dbus::emit_health_changed(&health_conn, true, "Service healthy").await;
        }
    });

    // Enter the main event loop — pending forever
    // zbus handles incoming method calls and signals internally
    std::future::pending::<()>().await;
}
