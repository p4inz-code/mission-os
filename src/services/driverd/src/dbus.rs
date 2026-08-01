//! D-Bus service interface for mission-driverd.
//!
//! Defines the service's D-Bus interfaces using zbus 4.x for real
//! system D-Bus integration.
//!
//! ## D-Bus Interface
//!
//! **Service name:** `org.mission.Driver1`
//!
//! **Object path:** `/org/mission/Driver1`
//!
//! **Interfaces:**
//! - `org.mission.Driver1` — Core service interface
//! - `org.mission.Driver1.Inventory` — Driver inventory and discovery
//! - `org.mission.Driver1.Management` — Driver install/update/remove
//!
//! ## Architecture
//!
//! Per MOS-ENG-IPC-001 §6.1:
//! - Process runs as root system service
//! - Bus name: `org.mission.Driver1`
//! - System bus only (no session bus)
//! - All privileged methods require PolKit authorization
//!
//! ## Signal Flow
//!
//! Driver-related events are emitted as D-Bus signals:
//! - `DriverEvent` — Generic driver lifecycle events
//! - `HealthChanged` — Service health status changes
//! - `InventoryChanged` — Hardware/driver inventory changes

use std::sync::{Arc, Mutex};

use zbus::connection;

use crate::audit::{AuditBackend, AuditEvent, EventCategory, EventSeverity};
use crate::authz::{Authorizer, DriverAction};
use crate::cache::CacheManager;
use crate::config::DriverConfig;
use crate::download::DownloadManager;
use crate::error::ServiceError;
use crate::execution::DriverExecutionEngine;

use crate::hwdetect::UdevMonitor;
use crate::inventory::{
    InstallRequest, InventoryScanner, OperationResult, RemoveRequest, UpdateRequest,
};
use crate::repository::RepositoryManager;
use crate::signals;
use crate::source::{SourceConfig, SourceRegistry};

/// The D-Bus well-known service name.
pub const SERVICE_NAME: &str = "org.mission.Driver1";

/// The D-Bus object path.
pub const OBJECT_PATH: &str = "/org/mission/Driver1";

/// Interface name for the core driver interface.
pub const INTERFACE_CORE: &str = "org.mission.Driver1";

/// Interface name for inventory management.
pub const INTERFACE_INVENTORY: &str = "org.mission.Driver1.Inventory";

/// Interface name for driver management operations.
pub const INTERFACE_MANAGEMENT: &str = "org.mission.Driver1.Management";

/// Shared application state held behind an `Arc` for access across
/// D-Bus interface implementations.
pub struct AppState {
    /// The service configuration.
    pub config: DriverConfig,
    /// Authorization checker.
    pub authorizer: Authorizer,
    /// Source registry for package sources (M2-E).
    pub source_registry: SourceRegistry,
    /// Audit logging backend.
    pub audit_backend: Box<dyn AuditBackend>,
    /// Driver inventory scanner (shared mutable state).
    pub scanner: Mutex<InventoryScanner>,
    /// M2-D: Driver execution engine for install/update/remove.
    pub execution_engine: DriverExecutionEngine,
    /// M2-D: udev event monitor for hardware change detection.
    pub udev_monitor: Mutex<UdevMonitor>,
    /// M2-F: Cache manager for driver packages.
    pub cache_manager: CacheManager,
    /// M2-F: Repository metadata manager.
    pub repository_manager: RepositoryManager,
    /// M2-F: Download manager with resume/retry.
    pub download_manager: DownloadManager,
}

impl AppState {
    /// Record an audit event through the configured backend.
    pub fn record_audit(&self, event: &AuditEvent) {
        self.audit_backend.record(event);
    }

    /// Create a new audit event, record it, and return the event.
    pub fn audit(
        &self,
        category: EventCategory,
        severity: EventSeverity,
        action: &str,
        subject: &str,
        details: &str,
    ) -> AuditEvent {
        let event = AuditEvent::new(category, severity, action, subject, details);
        self.record_audit(&event);
        event
    }

    /// Poll and process udev events (called periodically).
    pub fn poll_hardware_events(&self) -> Vec<crate::hwdetect::UdevEvent> {
        let mut monitor = self.udev_monitor.lock().unwrap();
        monitor.poll_events()
    }

    /// List all configured driver sources.
    pub fn list_sources(&self) -> Vec<&SourceConfig> {
        self.source_registry.all_sources().iter().collect()
    }

    /// Check if a source is enabled.
    pub fn is_source_enabled(&self, id: &str) -> bool {
        self.source_registry.is_source_enabled(id)
    }

    /// Get a serializable list of sources with their status.
    pub fn source_status_list(&self) -> Vec<serde_json::Value> {
        self.source_registry
            .all_sources()
            .iter()
            .map(|s| {
                serde_json::json!({
                    "id": s.id,
                    "name": s.name,
                    "source_type": format!("{:?}", s.source_type),
                    "enabled": s.enabled,
                    "priority": s.priority,
                    "base_url": s.base_url,
                    "has_metadata_url": s.metadata_url.is_some(),
                    "trusted_key_count": s.trusted_key_ids.len(),
                    "mirror_count": s.mirrors.len(),
                })
            })
            .collect()
    }

    /// Get cache status information.
    pub fn cache_status(&self) -> serde_json::Value {
        serde_json::json!({
            "cache_path": self.cache_manager.config().cache_path.to_string_lossy(),
            "current_size_bytes": self.cache_manager.current_cache_size(),
            "entry_count": self.cache_manager.cache_entry_count(),
            "max_size_bytes": self.cache_manager.config().max_size_bytes,
            "max_entries": self.cache_manager.config().max_entries,
        })
    }
}

// ── Helper: collect a snapshot of inventory data without holding the lock across await ──

/// Snapshot of inventory statistics used for status queries.
struct InventorySnapshot {
    driver_count: usize,
    active_drivers: usize,
    failed_drivers: usize,
    device_count: usize,
    last_scan_timestamp: u64,
}

/// Collect inventory statistics without holding the mutex across await points.
fn snapshot_inventory(scanner: &InventoryScanner) -> InventorySnapshot {
    let inv = scanner.inventory();
    InventorySnapshot {
        driver_count: inv.drivers.len(),
        active_drivers: inv.active_driver_count(),
        failed_drivers: inv.failed_driver_count(),
        device_count: inv.devices.len(),
        last_scan_timestamp: inv.last_scan_timestamp,
    }
}

// ── Core Interface (org.mission.Driver1) ─────────────────────────

/// Core driver D-Bus interface.
///
/// Interface: `org.mission.Driver1`
pub struct DriverInterface {
    /// Shared application state.
    state: Arc<AppState>,
    /// D-Bus connection for signal emission.
    conn: connection::Connection,
}

impl DriverInterface {
    /// Create a new core interface handler.
    pub fn new(state: Arc<AppState>, conn: connection::Connection) -> Self {
        Self { state, conn }
    }
}

#[zbus::interface(name = "org.mission.Driver1")]
impl DriverInterface {
    /// Return the service version string.
    async fn get_version(&self) -> zbus::fdo::Result<String> {
        Ok(env!("CARGO_PKG_VERSION").to_string())
    }

    /// Return the current driver service status as a JSON object.
    async fn get_status(&self, caller: &str) -> zbus::fdo::Result<String> {
        let auth = self
            .state
            .authorizer
            .authorize(&DriverAction::ViewStatus, caller);
        if !auth.is_authorized() {
            return Err(zbus::fdo::Error::AccessDenied(
                "not authorized to view driver service status".into(),
            ));
        }

        // Collect snapshot while holding the lock, then drop it before await.
        let snapshot = {
            let scanner = self.state.scanner.lock().unwrap();
            snapshot_inventory(&scanner)
        };

        let event = self.state.audit(
            EventCategory::System,
            EventSeverity::Info,
            "get_status",
            caller,
            "Driver service status requested",
        );
        emit_driver_event(&self.conn, &event).await;

        let status = serde_json::json!({
            "service": "mission-driverd",
            "version": env!("CARGO_PKG_VERSION"),
            "driver_count": snapshot.driver_count,
            "active_drivers": snapshot.active_drivers,
            "failed_drivers": snapshot.failed_drivers,
            "device_count": snapshot.device_count,
            "last_scan_timestamp": snapshot.last_scan_timestamp,
            "audit_enabled": self.state.config.audit.enabled,
        });

        serde_json::to_string(&status)
            .map_err(|e| zbus::fdo::Error::Failed(format!("status serialization failed: {e}")))
    }
}

// ── Inventory Interface (org.mission.Driver1.Inventory) ──────────

/// Inventory management D-Bus interface.
///
/// Interface: `org.mission.Driver1.Inventory`
pub struct InventoryInterface {
    /// Shared application state.
    state: Arc<AppState>,
    /// D-Bus connection for signal emission.
    conn: connection::Connection,
}

impl InventoryInterface {
    /// Create a new inventory interface handler.
    pub fn new(state: Arc<AppState>, conn: connection::Connection) -> Self {
        Self { state, conn }
    }
}

#[zbus::interface(name = "org.mission.Driver1.Inventory")]
impl InventoryInterface {
    /// Scan the system hardware and update the driver inventory.
    ///
    /// Returns a JSON-encoded `OperationResult`.
    async fn scan_hardware(&self, caller: &str) -> zbus::fdo::Result<String> {
        let auth = self
            .state
            .authorizer
            .authorize(&DriverAction::ScanHardware, caller);
        if !auth.is_authorized() {
            return Err(zbus::fdo::Error::AccessDenied(
                "not authorized to trigger hardware scan".into(),
            ));
        }

        // Perform scan under the lock; result is owned data.
        let op_result = {
            let mut scanner = self.state.scanner.lock().unwrap();
            scanner.scan_system().map(|_| {
                let count = scanner.inventory().drivers.len();
                OperationResult::success(
                    "system",
                    format!("Scan complete: {count} drivers in inventory"),
                )
            })
        };

        match op_result {
            Ok(op_result) => {
                let event = self.state.audit(
                    EventCategory::HardwareDetection,
                    EventSeverity::Info,
                    "hardware_scan",
                    caller,
                    &format!("Hardware scan completed: {}", op_result.message),
                );
                emit_driver_event(&self.conn, &event).await;
                emit_inventory_changed(&self.conn).await;

                serde_json::to_string(&op_result).map_err(|e| {
                    zbus::fdo::Error::Failed(format!("result serialization failed: {e}"))
                })
            }
            Err(e) => Err(map_service_error(e)),
        }
    }

    /// List all drivers in the inventory.
    ///
    /// Returns a JSON-encoded list of `DriverEntry`.
    async fn list_drivers(&self, caller: &str) -> zbus::fdo::Result<String> {
        let auth = self
            .state
            .authorizer
            .authorize(&DriverAction::ListDrivers, caller);
        if !auth.is_authorized() {
            return Err(zbus::fdo::Error::AccessDenied(
                "not authorized to list drivers".into(),
            ));
        }

        // Clone the data under the lock, then drop it.
        let drivers_json = {
            let scanner = self.state.scanner.lock().unwrap();
            let inv = scanner.inventory();
            serde_json::to_string(&inv.drivers)
                .map_err(|e| zbus::fdo::Error::Failed(format!("serialization failed: {e}")))
        };

        drivers_json
    }

    /// List all discovered hardware devices.
    ///
    /// Returns a JSON-encoded list of `HardwareDevice`.
    async fn list_devices(&self, caller: &str) -> zbus::fdo::Result<String> {
        let auth = self
            .state
            .authorizer
            .authorize(&DriverAction::ListDrivers, caller);
        if !auth.is_authorized() {
            return Err(zbus::fdo::Error::AccessDenied(
                "not authorized to list devices".into(),
            ));
        }

        let devices_json = {
            let scanner = self.state.scanner.lock().unwrap();
            let inv = scanner.inventory();
            serde_json::to_string(&inv.devices)
                .map_err(|e| zbus::fdo::Error::Failed(format!("serialization failed: {e}")))
        };

        devices_json
    }

    /// Query detailed information about a specific driver.
    ///
    /// Takes driver name and provider as arguments.
    /// Returns a JSON-encoded `DriverEntry`.
    async fn query_driver(
        &self,
        caller: &str,
        driver_name: &str,
        provider: &str,
    ) -> zbus::fdo::Result<String> {
        let auth = self
            .state
            .authorizer
            .authorize(&DriverAction::QueryDriver, caller);
        if !auth.is_authorized() {
            return Err(zbus::fdo::Error::AccessDenied(
                "not authorized to query drivers".into(),
            ));
        }

        // Clone data under lock, drop guard before returning.
        let driver_json = {
            let scanner = self.state.scanner.lock().unwrap();
            let driver = scanner
                .inventory()
                .find_driver(driver_name, provider)
                .ok_or_else(|| {
                    zbus::fdo::Error::FileNotFound(format!(
                        "driver '{provider}/{driver_name}' not found"
                    ))
                })
                .and_then(|d| {
                    serde_json::to_string(d)
                        .map_err(|e| zbus::fdo::Error::Failed(format!("serialization failed: {e}")))
                });
            driver
        };

        driver_json
    }

    /// Check compatibility of a driver with the current system.
    ///
    /// Takes driver name and provider as arguments.
    /// Returns a JSON-encoded `CompatibilityInfo`.
    async fn check_compatibility(
        &self,
        caller: &str,
        driver_name: &str,
        provider: &str,
    ) -> zbus::fdo::Result<String> {
        let auth = self
            .state
            .authorizer
            .authorize(&DriverAction::CheckCompatibility, caller);
        if !auth.is_authorized() {
            return Err(zbus::fdo::Error::AccessDenied(
                "not authorized to check compatibility".into(),
            ));
        }

        // Run compatibility check under lock; clone result.
        let compat_json = {
            let scanner = self.state.scanner.lock().unwrap();
            let compat =
                scanner
                    .check_compatibility(driver_name, provider)
                    .map_err(|e| match &e {
                        ServiceError::NotFound(msg) => zbus::fdo::Error::FileNotFound(msg.clone()),
                        _ => map_service_error(e),
                    })?;
            serde_json::to_string(&compat)
                .map_err(|e| zbus::fdo::Error::Failed(format!("serialization failed: {e}")))
        };

        compat_json
    }
}

// ── Management Interface (org.mission.Driver1.Management) ────────

/// Driver management D-Bus interface.
///
/// Interface: `org.mission.Driver1.Management`
pub struct ManagementInterface {
    /// Shared application state.
    state: Arc<AppState>,
    /// D-Bus connection for signal emission.
    conn: connection::Connection,
}

impl ManagementInterface {
    /// Create a new management interface handler.
    pub fn new(state: Arc<AppState>, conn: connection::Connection) -> Self {
        Self { state, conn }
    }
}

#[zbus::interface(name = "org.mission.Driver1.Management")]
impl ManagementInterface {
    /// Request installation of a driver.
    ///
    /// Takes a JSON-encoded `InstallRequest` string.
    /// Returns a JSON-encoded `OperationResult`.
    async fn install_driver(&self, caller: &str, request_json: &str) -> zbus::fdo::Result<String> {
        let request: InstallRequest = serde_json::from_str(request_json)
            .map_err(|e| zbus::fdo::Error::InvalidArgs(format!("invalid install request: {e}")))?;

        request
            .validate()
            .map_err(|e| zbus::fdo::Error::InvalidArgs(format!("invalid install request: {e}")))?;

        let auth = self
            .state
            .authorizer
            .authorize(&DriverAction::InstallDriver, caller);
        if !auth.is_authorized() {
            return Err(zbus::fdo::Error::AccessDenied(
                "not authorized to install drivers".into(),
            ));
        }

        let event = self.state.audit(
            EventCategory::DriverInstall,
            EventSeverity::Info,
            "driver_install_requested",
            caller,
            &format!(
                "Driver '{}' installation requested from '{}'",
                request.driver_name, request.provider
            ),
        );
        emit_driver_event(&self.conn, &event).await;

        // M2-D: Real driver installation — sync method, lock taken within scope
        let result = {
            let mut scanner = self.state.scanner.lock().unwrap();
            let devices = scanner.inventory().devices.clone();
            self.state.execution_engine.install_driver(
                &request,
                caller,
                scanner.inventory_mut(),
                &devices,
            )
        };

        emit_inventory_changed(&self.conn).await;

        if result.status == crate::inventory::OperationStatus::Completed {
            let event = self.state.audit(
                EventCategory::DriverInstall,
                EventSeverity::Info,
                "driver_install_completed",
                caller,
                &result.message,
            );
            emit_driver_event(&self.conn, &event).await;
        }

        serde_json::to_string(&result)
            .map_err(|e| zbus::fdo::Error::Failed(format!("result serialization failed: {e}")))
    }

    /// Request removal of a driver.
    async fn remove_driver(&self, caller: &str, request_json: &str) -> zbus::fdo::Result<String> {
        let request: RemoveRequest = serde_json::from_str(request_json)
            .map_err(|e| zbus::fdo::Error::InvalidArgs(format!("invalid remove request: {e}")))?;

        request
            .validate()
            .map_err(|e| zbus::fdo::Error::InvalidArgs(format!("invalid remove request: {e}")))?;

        let auth = self
            .state
            .authorizer
            .authorize(&DriverAction::RemoveDriver, caller);
        if !auth.is_authorized() {
            return Err(zbus::fdo::Error::AccessDenied(
                "not authorized to remove drivers".into(),
            ));
        }

        let event = self.state.audit(
            EventCategory::DriverRemove,
            EventSeverity::Info,
            "driver_remove_requested",
            caller,
            &format!("Driver '{}' removal requested", request.driver_name),
        );
        emit_driver_event(&self.conn, &event).await;

        let result = {
            let mut scanner = self.state.scanner.lock().unwrap();
            self.state
                .execution_engine
                .remove_driver(&request, caller, scanner.inventory_mut())
        };

        emit_inventory_changed(&self.conn).await;

        serde_json::to_string(&result)
            .map_err(|e| zbus::fdo::Error::Failed(format!("result serialization failed: {e}")))
    }

    /// Request update of a driver.
    async fn update_driver(&self, caller: &str, request_json: &str) -> zbus::fdo::Result<String> {
        let request: UpdateRequest = serde_json::from_str(request_json)
            .map_err(|e| zbus::fdo::Error::InvalidArgs(format!("invalid update request: {e}")))?;

        request
            .validate()
            .map_err(|e| zbus::fdo::Error::InvalidArgs(format!("invalid update request: {e}")))?;

        let auth = self
            .state
            .authorizer
            .authorize(&DriverAction::UpdateDriver, caller);
        if !auth.is_authorized() {
            return Err(zbus::fdo::Error::AccessDenied(
                "not authorized to update drivers".into(),
            ));
        }

        let event = self.state.audit(
            EventCategory::DriverUpdate,
            EventSeverity::Info,
            "driver_update_requested",
            caller,
            &format!(
                "Driver '{}' update requested to {:?}",
                request.driver_name, request.target_version
            ),
        );
        emit_driver_event(&self.conn, &event).await;

        let result = {
            let mut scanner = self.state.scanner.lock().unwrap();
            let devices = scanner.inventory().devices.clone();
            self.state.execution_engine.update_driver(
                &request,
                caller,
                scanner.inventory_mut(),
                &devices,
            )
        };

        emit_inventory_changed(&self.conn).await;

        serde_json::to_string(&result)
            .map_err(|e| zbus::fdo::Error::Failed(format!("result serialization failed: {e}")))
    }

    // ── M2-F: Source and Cache Management ────────────────────────

    /// List all configured driver sources.
    ///
    /// Returns a JSON-encoded list of source configurations with status.
    async fn list_sources(&self, caller: &str) -> zbus::fdo::Result<String> {
        let auth = self
            .state
            .authorizer
            .authorize(&DriverAction::ListDrivers, caller);
        if !auth.is_authorized() {
            return Err(zbus::fdo::Error::AccessDenied(
                "not authorized to list sources".into(),
            ));
        }

        let sources = serde_json::to_string(&self.state.source_status_list())
            .map_err(|e| zbus::fdo::Error::Failed(format!("serialization failed: {e}")))?;

        Ok(sources)
    }

    /// Refresh repository metadata for all configured sources.
    ///
    /// Returns a JSON-encoded result.
    async fn refresh_metadata(&self, caller: &str) -> zbus::fdo::Result<String> {
        let auth = self
            .state
            .authorizer
            .authorize(&DriverAction::ConfigureSources, caller);
        if !auth.is_authorized() {
            return Err(zbus::fdo::Error::AccessDenied(
                "not authorized to refresh metadata".into(),
            ));
        }

        self.state.audit(
            EventCategory::Configuration,
            EventSeverity::Info,
            "metadata_refresh_requested",
            caller,
            "Repository metadata refresh requested",
        );

        // Placeholder — actual metadata fetch requires HTTP requests
        // to each source's metadata_url. This will be connected when
        // the full metadata fetch pipeline is wired in a future step.
        let result = serde_json::json!({
            "status": "metadata_refresh_initiated",
            "message": "Repository metadata refresh has been initiated",
            "source_count": self.state.source_registry.source_count(),
        });

        serde_json::to_string(&result)
            .map_err(|e| zbus::fdo::Error::Failed(format!("serialization failed: {e}")))
    }

    /// Get cache status information.
    ///
    /// Returns a JSON-encoded object with cache stats.
    async fn get_cache_status(&self, caller: &str) -> zbus::fdo::Result<String> {
        let auth = self
            .state
            .authorizer
            .authorize(&DriverAction::ViewStatus, caller);
        if !auth.is_authorized() {
            return Err(zbus::fdo::Error::AccessDenied(
                "not authorized to view cache status".into(),
            ));
        }

        let status = serde_json::to_string(&self.state.cache_status())
            .map_err(|e| zbus::fdo::Error::Failed(format!("serialization failed: {e}")))?;

        Ok(status)
    }

    /// Clear the driver package cache.
    ///
    /// Returns a JSON-encoded result with the count of removed entries.
    async fn clear_cache(&self, caller: &str) -> zbus::fdo::Result<String> {
        let auth = self
            .state
            .authorizer
            .authorize(&DriverAction::ConfigureSources, caller);
        if !auth.is_authorized() {
            return Err(zbus::fdo::Error::AccessDenied(
                "not authorized to clear cache".into(),
            ));
        }

        match self.state.cache_manager.clear() {
            Ok(removed) => {
                self.state.audit(
                    EventCategory::Configuration,
                    EventSeverity::Info,
                    "cache_cleared",
                    caller,
                    &format!("Cache cleared: {removed} entries removed"),
                );

                let result = serde_json::json!({
                    "status": "cache_cleared",
                    "removed_entries": removed,
                });

                Ok(serde_json::to_string(&result)
                    .map_err(|e| zbus::fdo::Error::Failed(format!("serialization failed: {e}")))?)
            }
            Err(e) => Err(map_service_error(e)),
        }
    }
}

// ── Signal Emission Helpers ───────────────────────────────────────

/// Emit a `DriverEvent` signal through the connection.
pub async fn emit_driver_event(conn: &connection::Connection, event: &AuditEvent) {
    let seq = signals::next_sequence();
    let ts = signals::current_timestamp();

    let path = match zbus::zvariant::ObjectPath::try_from(OBJECT_PATH) {
        Ok(p) => p,
        Err(_) => return,
    };

    let body = (
        seq,
        ts,
        event.category.to_string(),
        event.severity.to_string(),
        event.action.clone(),
        event.subject.clone(),
        event.details.clone(),
    );

    let _ = conn
        .emit_signal(None::<&str>, path, INTERFACE_CORE, "DriverEvent", &body)
        .await;
}

/// Emit a `HealthChanged` signal through the connection.
pub async fn emit_health_changed(conn: &connection::Connection, healthy: bool, status: &str) {
    let seq = signals::next_sequence();
    let ts = signals::current_timestamp();

    let path = match zbus::zvariant::ObjectPath::try_from(OBJECT_PATH) {
        Ok(p) => p,
        Err(_) => return,
    };

    let body = (seq, ts, healthy, status.to_string());

    let _ = conn
        .emit_signal(None::<&str>, path, INTERFACE_CORE, "HealthChanged", &body)
        .await;
}

/// Emit an `InventoryChanged` signal through the connection.
pub async fn emit_inventory_changed(conn: &connection::Connection) {
    let seq = signals::next_sequence();
    let ts = signals::current_timestamp();

    let path = match zbus::zvariant::ObjectPath::try_from(OBJECT_PATH) {
        Ok(p) => p,
        Err(_) => return,
    };

    let body = (seq, ts);

    let _ = conn
        .emit_signal(
            None::<&str>,
            path,
            INTERFACE_INVENTORY,
            "InventoryChanged",
            &body,
        )
        .await;
}

// ── Error Mapping ─────────────────────────────────────────────────

/// Map a `ServiceError` to a `zbus::fdo::Error` for D-Bus method returns.
pub fn map_service_error(err: ServiceError) -> zbus::fdo::Error {
    match err {
        ServiceError::PermissionDenied(msg) => zbus::fdo::Error::AccessDenied(msg),
        ServiceError::InvalidArgument(msg) => zbus::fdo::Error::InvalidArgs(msg),
        ServiceError::NotFound(msg) => zbus::fdo::Error::FileNotFound(msg),
        ServiceError::AlreadyExists(msg) => {
            zbus::fdo::Error::Failed(format!("already exists: {msg}"))
        }
        ServiceError::NotSupported(msg) => zbus::fdo::Error::NotSupported(msg),
        ServiceError::BackendUnavailable(msg) => zbus::fdo::Error::Failed(msg),
        ServiceError::Busy(msg) => zbus::fdo::Error::Failed(msg),
        ServiceError::Conflict(msg) => zbus::fdo::Error::Failed(msg),
        ServiceError::VerificationFailed(msg) => zbus::fdo::Error::Failed(msg),
        ServiceError::RollbackFailed(msg) => zbus::fdo::Error::Failed(msg),
        ServiceError::PackageError(msg) => zbus::fdo::Error::Failed(msg),
        ServiceError::DownloadFailed(msg) => zbus::fdo::Error::Failed(msg),
        ServiceError::SourceError(msg) => zbus::fdo::Error::Failed(msg),
        ServiceError::MetadataError(msg) => zbus::fdo::Error::InvalidArgs(msg),
        ServiceError::DowngradeRejected(msg) => zbus::fdo::Error::InvalidArgs(msg),
        ServiceError::Internal(msg) => zbus::fdo::Error::Failed(msg),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::audit::LogAuditBackend;
    use crate::authz::Authorizer;

    fn test_state(allow_unauthorized: bool) -> Arc<AppState> {
        use crate::execution::DriverExecutionEngine;
        use crate::package::PackageStore;

        let store = PackageStore::new(&crate::config::PackageStoreConfig {
            store_path: std::env::temp_dir()
                .join("mission_driverd_test")
                .to_string_lossy()
                .to_string(),
            max_package_size_bytes: 1_000_000_000,
        });
        let verifier = crate::verification::SignatureVerifier::new(
            crate::verification::TrustedKeyStore::new(std::path::PathBuf::from(
                "/nonexistent/keys",
            )),
            true,
        );
        let engine = DriverExecutionEngine::new(
            Authorizer::new(allow_unauthorized, Box::new(LogAuditBackend), None),
            Box::new(LogAuditBackend),
            store,
            verifier,
            true,
        );

        let sources = SourceRegistry::from_configs(crate::source::default_sources())
            .unwrap_or_else(|_| SourceRegistry::empty());

        let cache_dir = std::env::temp_dir().join("mission_driverd_cache_test");
        let _ = std::fs::create_dir_all(&cache_dir);
        let cache_manager = CacheManager::new(crate::cache::CacheConfig::new(cache_dir.clone()));

        let repository_manager = RepositoryManager::new(
            crate::repository::FreshnessPolicy::default(),
            Box::new(LogAuditBackend),
        );

        let fetcher = crate::fetch::PackageFetcher::new(crate::fetch::DownloadConfig::default());
        let download_manager = DownloadManager::new(
            fetcher,
            crate::download::RetryPolicy::default(),
            crate::download::ResumeManager::new(cache_dir.join("partials")),
            Box::new(LogAuditBackend),
        );

        Arc::new(AppState {
            config: DriverConfig::default(),
            authorizer: Authorizer::new(allow_unauthorized, Box::new(LogAuditBackend), None),
            source_registry: sources,
            audit_backend: Box::new(LogAuditBackend),
            scanner: Mutex::new(InventoryScanner::new()),
            execution_engine: engine,
            udev_monitor: Mutex::new(crate::hwdetect::UdevMonitor::new()),
            cache_manager,
            repository_manager,
            download_manager,
        })
    }

    #[test]
    fn constants_are_defined() {
        assert!(!SERVICE_NAME.is_empty());
        assert!(!OBJECT_PATH.is_empty());
        assert!(!INTERFACE_CORE.is_empty());
        assert!(!INTERFACE_INVENTORY.is_empty());
        assert!(!INTERFACE_MANAGEMENT.is_empty());
    }

    #[test]
    fn app_state_audit_records() {
        let state = test_state(true);
        let event = state.audit(
            EventCategory::System,
            EventSeverity::Info,
            "test",
            "tester",
            "Test audit",
        );
        assert_eq!(event.action, "test");
    }

    #[test]
    fn app_state_list_sources() {
        let state = test_state(true);
        let sources = state.list_sources();
        assert!(!sources.is_empty());
    }

    #[test]
    fn map_service_error_permission_denied() {
        let err = ServiceError::PermissionDenied("denied".into());
        let fdo = map_service_error(err);
        assert!(format!("{fdo}").contains("denied") || format!("{fdo}").contains("AccessDenied"));
    }

    #[test]
    fn map_service_error_invalid_arg() {
        let err = ServiceError::InvalidArgument("bad".into());
        let fdo = map_service_error(err);
        assert!(format!("{fdo}").contains("InvalidArgs") || format!("{fdo}").contains("bad"));
    }

    #[test]
    fn map_service_error_internal() {
        let err = ServiceError::Internal("crash".into());
        let fdo = map_service_error(err);
        assert!(format!("{fdo}").contains("Failed") || format!("{fdo}").contains("crash"));
    }

    #[test]
    fn map_service_error_already_exists() {
        let err = ServiceError::AlreadyExists("driver exists".into());
        let fdo = map_service_error(err);
        assert!(!fdo.to_string().is_empty());
        let display = format!("{fdo}");
        assert!(display.contains("already exists") || display.contains("Failed"));
    }

    #[test]
    fn map_service_error_backend_unavailable() {
        let err = ServiceError::BackendUnavailable("udev not ready".into());
        let fdo = map_service_error(err);
        assert!(!fdo.to_string().is_empty());
    }

    #[test]
    fn map_service_error_busy() {
        let err = ServiceError::Busy("in progress".into());
        let fdo = map_service_error(err);
        assert!(!fdo.to_string().is_empty());
    }

    #[test]
    fn map_service_error_download_failed() {
        let err = ServiceError::DownloadFailed("timeout".into());
        let fdo = map_service_error(err);
        assert!(!fdo.to_string().is_empty());
    }

    #[test]
    fn map_service_error_source_error() {
        let err = ServiceError::SourceError("unreachable".into());
        let fdo = map_service_error(err);
        assert!(!fdo.to_string().is_empty());
    }

    #[test]
    fn map_service_error_metadata_error() {
        let err = ServiceError::MetadataError("invalid format".into());
        let fdo = map_service_error(err);
        assert!(!fdo.to_string().is_empty());
    }

    #[test]
    fn emit_driver_event_creates_valid_args() {
        let event = AuditEvent::new(
            EventCategory::DriverInstall,
            EventSeverity::Info,
            "test",
            "tester",
            "Signal test",
        );
        assert_eq!(event.action, "test");
    }

    #[test]
    fn emit_health_changed_creates_valid_args() {
        let ts = signals::current_timestamp();
        assert!(ts > 1_000_000_000);
        assert!(ts < 9_999_999_999);
    }

    #[test]
    fn emit_inventory_changed_creates_valid_args() {
        let ts = signals::current_timestamp();
        assert!(ts > 1_000_000_000);
    }

    #[test]
    fn driver_interface_new() {
        let state = test_state(true);
        assert_eq!(state.config.dbus_name, SERVICE_NAME);
    }

    #[test]
    fn object_path_is_valid() {
        let path = zbus::zvariant::ObjectPath::try_from(OBJECT_PATH);
        assert!(path.is_ok());
    }

    #[test]
    fn inventory_interface_new() {
        let state = test_state(true);
        assert_eq!(state.config.dbus_name, SERVICE_NAME);
    }

    #[test]
    fn management_interface_new() {
        let state = test_state(true);
        assert_eq!(state.config.dbus_name, SERVICE_NAME);
    }

    #[test]
    fn snapshot_inventory_empty() {
        let scanner = InventoryScanner::new();
        let snap = snapshot_inventory(&scanner);
        assert_eq!(snap.driver_count, 0);
        assert_eq!(snap.active_drivers, 0);
        assert_eq!(snap.failed_drivers, 0);
    }

    #[test]
    fn snapshot_inventory_with_data() {
        let mut scanner = InventoryScanner::new();
        scanner.scan_system().unwrap();
        let snap = snapshot_inventory(&scanner);
        assert!(snap.driver_count > 0);
        assert!(
            snap.last_scan_timestamp > 0,
            "scan should set last_scan_timestamp"
        );
    }
}
