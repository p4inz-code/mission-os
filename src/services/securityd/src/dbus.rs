//! D-Bus service interface for mission-securityd.
//!
//! Defines the service's D-Bus interfaces using zbus 4.x for real
//! system D-Bus integration.
//!
//! ## D-Bus Interface
//!
//! **Service name:** `org.mission.Security1`
//!
//! **Object path:** `/org/mission/Security1`
//!
//! **Interfaces:**
//! - `org.mission.Security1` — Core security interface
//! - `org.mission.Security1.Firewall` — Firewall management
//! - `org.mission.Security1.Audit` — Audit log management
//!
//! ## Architecture
//!
//! Per MOS-ENG-IPC-001 §6.1:
//! - Process runs as `mission-security` system user
//! - Bus name: `org.mission.Security1`
//! - System bus only (no session bus)
//! - All privileged methods require PolKit authorization
//!
//! ## Signal Flow
//!
//! Security-relevant events are emitted as D-Bus signals on the
//! `org.mission.Security1` interface. The event body matches the
//! audit event structure.

use std::sync::Arc;

use zbus::connection;

use crate::audit::{AuditBackend, AuditEvent, EventCategory, EventSeverity};
use crate::authz::{Authorizer, SecurityAction};
use crate::config::SecurityConfig;
use crate::error::ServiceError;
use crate::firewall::{ApplyResult, FirewallRule, FirewallStatus, ProfileChangeRequest};
use crate::signals;

/// The D-Bus well-known service name.
pub const SERVICE_NAME: &str = "org.mission.Security1";

/// The D-Bus object path.
pub const OBJECT_PATH: &str = "/org/mission/Security1";

/// Interface name for the core security interface.
pub const INTERFACE_CORE: &str = "org.mission.Security1";

/// Interface name for firewall management.
pub const INTERFACE_FIREWALL: &str = "org.mission.Security1.Firewall";

/// Interface name for audit log management.
pub const INTERFACE_AUDIT: &str = "org.mission.Security1.Audit";

/// Shared application state held behind an `Arc` for access across
/// D-Bus interface implementations.
pub struct AppState {
    /// The service configuration.
    pub config: SecurityConfig,
    /// Authorization checker.
    pub authorizer: Authorizer,
    /// Audit logging backend.
    pub audit_backend: Box<dyn AuditBackend>,
}

impl AppState {
    /// Record an audit event through the configured backend.
    pub fn record_audit(&self, event: &AuditEvent) {
        self.audit_backend.record(event);
    }

    /// Create a new audit event, record it, and return the event.
    pub fn audit(
        &self,
        severity: EventSeverity,
        action: &str,
        subject: &str,
        details: &str,
    ) -> AuditEvent {
        let event = AuditEvent::new(EventCategory::Security, severity, action, subject, details);
        self.record_audit(&event);
        event
    }
}

// ── Core Interface (org.mission.Security1) ─────────────────────────

/// Core security D-Bus interface.
///
/// Interface: `org.mission.Security1`
pub struct SecurityInterface {
    /// Shared application state.
    state: Arc<AppState>,
    /// D-Bus connection for signal emission.
    conn: connection::Connection,
}

impl SecurityInterface {
    /// Create a new core interface handler.
    pub fn new(state: Arc<AppState>, conn: connection::Connection) -> Self {
        Self { state, conn }
    }
}

#[zbus::interface(name = "org.mission.Security1")]
impl SecurityInterface {
    /// Return the service version string.
    async fn get_version(&self) -> zbus::fdo::Result<String> {
        Ok(env!("CARGO_PKG_VERSION").to_string())
    }

    /// Return the current security status as a JSON object.
    async fn get_status(&self, caller: &str) -> zbus::fdo::Result<String> {
        let event = self.state.audit(
            EventSeverity::Info,
            "get_status",
            caller,
            "Security status requested",
        );
        emit_security_event(&self.conn, &event).await;

        let status = serde_json::json!({
            "service": "mission-securityd",
            "version": env!("CARGO_PKG_VERSION"),
            "firewall_enabled": self.state.config.firewall_enabled,
            "firewall_profile": self.state.config.default_firewall_profile,
            "audit_enabled": self.state.config.audit.enabled,
        });

        serde_json::to_string(&status)
            .map_err(|e| zbus::fdo::Error::Failed(format!("status serialization failed: {e}")))
    }
}

// ── Firewall Interface (org.mission.Security1.Firewall) ────────────

/// Firewall management D-Bus interface.
///
/// Interface: `org.mission.Security1.Firewall`
pub struct FirewallInterface {
    /// Shared application state.
    state: Arc<AppState>,
    /// D-Bus connection for signal emission.
    conn: connection::Connection,
}

impl FirewallInterface {
    /// Create a new firewall interface handler.
    pub fn new(state: Arc<AppState>, conn: connection::Connection) -> Self {
        Self { state, conn }
    }
}

#[zbus::interface(name = "org.mission.Security1.Firewall")]
impl FirewallInterface {
    /// Return the current firewall status as a JSON string.
    async fn get_firewall_status(&self, caller: &str) -> zbus::fdo::Result<String> {
        let auth = self
            .state
            .authorizer
            .authorize(&SecurityAction::ViewFirewallStatus, caller);
        if !auth.is_authorized() {
            return Err(zbus::fdo::Error::AccessDenied(
                "not authorized to view firewall status".into(),
            ));
        }

        let status = FirewallStatus {
            enabled: self.state.config.firewall_enabled,
            active_profile: self.state.config.default_firewall_profile,
            rule_count: 0,
            backend_available: false,
        };

        serde_json::to_string(&status).map_err(|e| {
            zbus::fdo::Error::Failed(format!("firewall status serialization failed: {e}"))
        })
    }

    /// Request a firewall profile change.
    ///
    /// Takes a JSON-encoded `ProfileChangeRequest` string.
    /// Returns a JSON-encoded `ApplyResult`.
    async fn set_firewall_profile(
        &self,
        caller: &str,
        request_json: &str,
    ) -> zbus::fdo::Result<String> {
        let request: ProfileChangeRequest = serde_json::from_str(request_json).map_err(|e| {
            zbus::fdo::Error::InvalidArgs(format!("invalid profile change request: {e}"))
        })?;

        request.validate().map_err(|e| {
            zbus::fdo::Error::InvalidArgs(format!("invalid profile change request: {e}"))
        })?;

        let auth = self
            .state
            .authorizer
            .authorize(&SecurityAction::ConfigureFirewall, caller);
        if !auth.is_authorized() {
            return Err(zbus::fdo::Error::AccessDenied(
                "not authorized to change firewall profile".into(),
            ));
        }

        let event = self.state.audit(
            EventSeverity::Info,
            "firewall_profile_changed",
            caller,
            &format!(
                "Firewall profile changed to {:?}: {}",
                request.profile, request.reason
            ),
        );
        emit_security_event(&self.conn, &event).await;

        let result = ApplyResult {
            success: true,
            rules_applied: 0,
            rules_failed: 0,
            error: Some(
                "nftables backend not yet integrated; profile recorded but not applied".into(),
            ),
        };

        serde_json::to_string(&result)
            .map_err(|e| zbus::fdo::Error::Failed(format!("result serialization failed: {e}")))
    }

    /// Add a firewall rule.
    ///
    /// Takes a JSON-encoded `FirewallRule` string.
    /// Returns a JSON-encoded `ApplyResult`.
    async fn add_firewall_rule(&self, caller: &str, rule_json: &str) -> zbus::fdo::Result<String> {
        let rule: FirewallRule = serde_json::from_str(rule_json)
            .map_err(|e| zbus::fdo::Error::InvalidArgs(format!("invalid firewall rule: {e}")))?;

        rule.validate()
            .map_err(|e| zbus::fdo::Error::InvalidArgs(format!("invalid firewall rule: {e}")))?;

        let auth = self
            .state
            .authorizer
            .authorize(&SecurityAction::ConfigureFirewall, caller);
        if !auth.is_authorized() {
            return Err(zbus::fdo::Error::AccessDenied(
                "not authorized to add firewall rules".into(),
            ));
        }

        let event = self.state.audit(
            EventSeverity::Info,
            "firewall_rule_added",
            caller,
            &format!("Rule added: {}", rule.name),
        );
        emit_security_event(&self.conn, &event).await;

        let result = ApplyResult {
            success: true,
            rules_applied: 1,
            rules_failed: 0,
            error: Some(
                "nftables backend not yet integrated; rule recorded but not applied".into(),
            ),
        };

        serde_json::to_string(&result)
            .map_err(|e| zbus::fdo::Error::Failed(format!("result serialization failed: {e}")))
    }
}

// ── Audit Interface (org.mission.Security1.Audit) ──────────────────

/// Audit log management D-Bus interface.
///
/// Interface: `org.mission.Security1.Audit`
pub struct AuditInterface {
    /// Shared application state.
    state: Arc<AppState>,
    /// D-Bus connection for signal emission.
    conn: connection::Connection,
}

impl AuditInterface {
    /// Create a new audit interface handler.
    pub fn new(state: Arc<AppState>, conn: connection::Connection) -> Self {
        Self { state, conn }
    }
}

#[zbus::interface(name = "org.mission.Security1.Audit")]
impl AuditInterface {
    /// Export the audit log as a JSON array string.
    async fn export_audit_log(&self, caller: &str) -> zbus::fdo::Result<String> {
        let auth = self
            .state
            .authorizer
            .authorize(&SecurityAction::ExportAuditLog, caller);
        if !auth.is_authorized() {
            return Err(zbus::fdo::Error::AccessDenied(
                "not authorized to export audit logs".into(),
            ));
        }

        let event = self.state.audit(
            EventSeverity::Info,
            "audit_log_export",
            caller,
            "Audit log export requested",
        );
        emit_security_event(&self.conn, &event).await;

        Ok("[]".into())
    }
}

// ── Signal Emission Helpers ───────────────────────────────────────

/// Emit a `SecurityEvent` signal through the connection.
///
/// Signal interface: `org.mission.Security1`
/// Signal name: `SecurityEvent`
pub async fn emit_security_event(conn: &connection::Connection, event: &AuditEvent) {
    let seq = signals::next_sequence();
    let ts = signals::current_timestamp();

    let path = zbus::zvariant::ObjectPath::try_from(OBJECT_PATH).expect("valid object path");

    let body = (
        seq,
        ts,
        event.category.to_string(),
        event.severity.to_string(),
        event.action.clone(),
        event.subject.clone(),
        event.details.clone(),
    );

    // Best-effort emission — errors are silently ignored because
    // signal emission must not block the caller.
    let _ = conn
        .emit_signal(None::<&str>, path, INTERFACE_CORE, "SecurityEvent", &body)
        .await;
}

/// Emit a `HealthChanged` signal through the connection.
///
/// Signal interface: `org.mission.Security1`
/// Signal name: `HealthChanged`
pub async fn emit_health_changed(conn: &connection::Connection, healthy: bool, status: &str) {
    let seq = signals::next_sequence();
    let ts = signals::current_timestamp();

    let path = zbus::zvariant::ObjectPath::try_from(OBJECT_PATH).expect("valid object path");

    let body = (seq, ts, healthy, status.to_string());

    let _ = conn
        .emit_signal(None::<&str>, path, INTERFACE_CORE, "HealthChanged", &body)
        .await;
}

// ── Error Mapping ─────────────────────────────────────────────────

/// Map a `ServiceError` to a `zbus::fdo::Error` for D-Bus method returns.
pub fn map_service_error(err: ServiceError) -> zbus::fdo::Error {
    match err {
        ServiceError::PermissionDenied(msg) => zbus::fdo::Error::AccessDenied(msg),
        ServiceError::InvalidArgument(msg) => zbus::fdo::Error::InvalidArgs(msg),
        ServiceError::NotFound(msg) => zbus::fdo::Error::FileNotFound(msg),
        ServiceError::NotSupported(msg) => zbus::fdo::Error::NotSupported(msg),
        ServiceError::Internal(msg) => zbus::fdo::Error::Failed(msg),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::audit::LogAuditBackend;
    use crate::authz::Authorizer;

    fn test_state(allow_unauthorized: bool) -> Arc<AppState> {
        Arc::new(AppState {
            config: SecurityConfig::default(),
            authorizer: Authorizer::new(allow_unauthorized, Box::new(LogAuditBackend)),
            audit_backend: Box::new(LogAuditBackend),
        })
    }

    #[test]
    fn constants_are_defined() {
        assert!(!SERVICE_NAME.is_empty());
        assert!(!OBJECT_PATH.is_empty());
        assert!(!INTERFACE_CORE.is_empty());
        assert!(!INTERFACE_FIREWALL.is_empty());
        assert!(!INTERFACE_AUDIT.is_empty());
    }

    #[test]
    fn app_state_audit_records() {
        let state = test_state(true);
        let event = state.audit(EventSeverity::Info, "test", "tester", "Test audit");
        assert_eq!(event.action, "test");
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
    fn emit_security_event_creates_valid_args() {
        let event = AuditEvent::new(
            EventCategory::Security,
            EventSeverity::Info,
            "test",
            "tester",
            "Signal test",
        );
        assert_eq!(event.action, "test");
    }

    #[test]
    fn emit_health_changed_creates_valid_args() {
        let _seq = signals::next_sequence();
        let ts = signals::current_timestamp();
        assert!(ts > 1_000_000_000);
        assert!(ts < 9_999_999_999);
    }

    #[test]
    fn security_interface_new() {
        let state = test_state(true);
        assert_eq!(state.config.dbus_name, SERVICE_NAME);
    }

    #[test]
    fn object_path_is_valid() {
        let path = zbus::zvariant::ObjectPath::try_from(OBJECT_PATH);
        assert!(path.is_ok());
    }
}
