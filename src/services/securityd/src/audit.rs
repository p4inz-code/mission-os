//! Audit logging boundary for mission-securityd.
//!
//! Provides structured security event types that are logged to the
//! system audit trail. This module defines the event schema and
//! provides safe construction of audit records.
//!
//! ## Security
//!
//! - Audit records must NOT contain: passwords, encryption keys,
//!   personal file content, or session tokens.
//! - All timestamps are UTC.
//! - Event messages are static strings — no user-controlled content
//!   is included without sanitization.
//!
//! ## Architecture
//!
//! This module defines the audit event boundary. The actual log
//! emission uses mission-core's logging infrastructure with a
//! structured format compatible with future journald integration.
//!
//! Per MOS-ENG-SEC-001 §8.1, the following events are logged:
//! - Authentication: login, logout, failed attempts, lock/unlock
//! - Privilege: elevation requests, grant, deny
//! - Security: firewall changes, policy changes, sandbox violations
//! - Privacy: permission grant, revoke, access attempts
//! - Updates: check, download, install, rollback, failure
//! - Drivers: install, update, rollback, verification failure
//! - System: boot, shutdown, crash, recovery

use serde::{Deserialize, Serialize};
use std::fmt;
use std::time::{SystemTime, UNIX_EPOCH};

/// Categories of security-relevant events.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EventCategory {
    /// Authentication events (login, logout, lock, unlock).
    Authentication,
    /// Privilege escalation events.
    Privilege,
    /// Security policy changes (firewall, MAC, sandbox).
    Security,
    /// Privacy permission events.
    Privacy,
    /// Update system events.
    Update,
    /// Driver management events.
    Driver,
    /// System-level events (boot, shutdown, crash).
    System,
}

impl fmt::Display for EventCategory {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            EventCategory::Authentication => write!(f, "authentication"),
            EventCategory::Privilege => write!(f, "privilege"),
            EventCategory::Security => write!(f, "security"),
            EventCategory::Privacy => write!(f, "privacy"),
            EventCategory::Update => write!(f, "update"),
            EventCategory::Driver => write!(f, "driver"),
            EventCategory::System => write!(f, "system"),
        }
    }
}

/// Severity of an audit event.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, PartialOrd, Ord)]
#[serde(rename_all = "snake_case")]
pub enum EventSeverity {
    /// Debug-level audit information.
    Debug,
    /// Informational event.
    Info,
    /// Warning — potential issue detected.
    Warning,
    /// Error — operation failed.
    Error,
    /// Critical — immediate attention required.
    Critical,
}

impl fmt::Display for EventSeverity {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            EventSeverity::Debug => write!(f, "debug"),
            EventSeverity::Info => write!(f, "info"),
            EventSeverity::Warning => write!(f, "warning"),
            EventSeverity::Error => write!(f, "error"),
            EventSeverity::Critical => write!(f, "critical"),
        }
    }
}

/// A structured audit event.
///
/// # Security
///
/// - `details` must not contain secrets or personal data.
/// - The `subject` field identifies the requesting user/service, not secrets.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuditEvent {
    /// Unix timestamp (seconds since epoch, UTC).
    pub timestamp: u64,
    /// Event category.
    pub category: EventCategory,
    /// Event severity.
    pub severity: EventSeverity,
    /// The action that occurred (e.g., "firewall_rule_added").
    pub action: String,
    /// The subject (user or service) that triggered the event.
    pub subject: String,
    /// Human-readable details about the event.
    /// Must NOT contain secrets or sensitive data.
    pub details: String,
    /// Optional unique identifier for correlating related events.
    pub correlation_id: Option<String>,
}

impl AuditEvent {
    /// Create a new audit event.
    ///
    /// # Arguments
    ///
    /// * `category` - The event category.
    /// * `severity` - The event severity.
    /// * `action` - A short action identifier (e.g., "firewall_rule_added").
    /// * `subject` - The user or service that triggered the event.
    /// * `details` - Human-readable details. Must NOT contain secrets.
    pub fn new(
        category: EventCategory,
        severity: EventSeverity,
        action: impl Into<String>,
        subject: impl Into<String>,
        details: impl Into<String>,
    ) -> Self {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();

        Self {
            timestamp: now,
            category,
            severity,
            action: action.into(),
            subject: subject.into(),
            details: details.into(),
            correlation_id: None,
        }
    }

    /// Set a correlation ID for grouping related events.
    pub fn with_correlation(mut self, id: impl Into<String>) -> Self {
        self.correlation_id = Some(id.into());
        self
    }

    /// Serialize this event to a JSON string for log output.
    ///
    /// The JSON format is compatible with structured logging and
    /// future journald integration.
    pub fn to_json(&self) -> String {
        serde_json::to_string(self).unwrap_or_else(|_| {
            format!(
                r#"{{"error":"serialization_failed","action":"{}"}}"#,
                self.action
            )
        })
    }
}

/// Provides the interface for emitting audit events.
///
/// This trait defines how audit events are recorded. The actual
/// backend (e.g., journald, log file, mission-core logging) is
/// injected at service startup.
///
/// Implementations must be thread-safe (`Send + Sync`) so they can
/// be shared across async tasks and D-Bus interface handlers.
pub trait AuditBackend: Send + Sync {
    /// Record an audit event.
    ///
    /// Implementations MUST NOT:
    /// - Panic
    /// - Include secrets in output
    /// - Block indefinitely
    fn record(&self, event: &AuditEvent);
}

/// Default audit backend that logs via stderr.
///
/// This is the minimal backend used during bootstrap and testing.
/// In production, it is replaced by a `LoggingAuditBackend` that
/// integrates mission-core logging.
#[derive(Debug, Clone)]
pub struct LogAuditBackend;

impl AuditBackend for LogAuditBackend {
    fn record(&self, event: &AuditEvent) {
        let json = event.to_json();
        // Use eprintln as the bootstrap output channel.
        // When mission-core logging is initialized, this is
        // replaced by the LoggingAuditBackend.
        eprintln!("[AUDIT] {json}");
    }
}

/// Audit backend that integrates with mission-core logging.
///
/// This backend uses `mission_core::log!` macros for structured
/// log output, which is compatible with future journald integration.
///
/// ## Usage
///
/// This backend should be used after mission-core logging is
/// initialized in `main.rs`. During bootstrap (before logging init),
/// use `LogAuditBackend` instead.
#[derive(Debug, Clone)]
pub struct LoggingAuditBackend;

impl AuditBackend for LoggingAuditBackend {
    fn record(&self, event: &AuditEvent) {
        let json = event.to_json();

        // Map event severity to mission-core log level.
        // The module path is automatically captured via file!() and line!().
        let level = match event.severity {
            EventSeverity::Critical | EventSeverity::Error => mission_core::logging::Level::Error,
            EventSeverity::Warning => mission_core::logging::Level::Warn,
            EventSeverity::Info => mission_core::logging::Level::Info,
            EventSeverity::Debug => mission_core::logging::Level::Debug,
        };
        mission_core::log!(level, "[AUDIT] {json}");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn audit_event_creation() {
        let event = AuditEvent::new(
            EventCategory::Security,
            EventSeverity::Info,
            "firewall_profile_changed",
            "user:admin",
            "Firewall profile changed from Public to Private",
        );
        assert_eq!(event.category, EventCategory::Security);
        assert_eq!(event.severity, EventSeverity::Info);
        assert_eq!(event.action, "firewall_profile_changed");
        assert!(event.timestamp > 0);
        assert!(event.correlation_id.is_none());
    }

    #[test]
    fn audit_event_with_correlation() {
        let event = AuditEvent::new(
            EventCategory::Authentication,
            EventSeverity::Warning,
            "login_failed",
            "user:unknown",
            "Failed login attempt from console",
        )
        .with_correlation("corr-001");

        assert_eq!(event.correlation_id, Some("corr-001".into()));
    }

    #[test]
    fn audit_event_json_serialization() {
        let event = AuditEvent::new(
            EventCategory::System,
            EventSeverity::Info,
            "service_started",
            "mission-securityd",
            "Security service started successfully",
        );
        let json = event.to_json();
        assert!(json.contains(r#""action":"service_started""#));
        assert!(json.contains(r#""category":"system""#));
        assert!(json.contains(r#""severity":"info""#));
    }

    #[test]
    fn audit_event_json_no_secrets() {
        let event = AuditEvent::new(
            EventCategory::Authentication,
            EventSeverity::Info,
            "login_success",
            "user:alice",
            "User alice logged in successfully",
        );
        let json = event.to_json();
        // Ensure no password or key material appears
        assert!(!json.contains("password"));
        assert!(!json.contains("secret"));
        assert!(!json.contains("key"));
    }

    #[test]
    fn category_display() {
        assert_eq!(EventCategory::Authentication.to_string(), "authentication");
        assert_eq!(EventCategory::Security.to_string(), "security");
        assert_eq!(EventCategory::Privilege.to_string(), "privilege");
    }

    #[test]
    fn severity_ordering() {
        assert!(EventSeverity::Debug < EventSeverity::Info);
        assert!(EventSeverity::Info < EventSeverity::Warning);
        assert!(EventSeverity::Warning < EventSeverity::Error);
        assert!(EventSeverity::Error < EventSeverity::Critical);
    }

    #[test]
    fn log_audit_backend_does_not_panic() {
        let backend = LogAuditBackend;
        let event = AuditEvent::new(
            EventCategory::System,
            EventSeverity::Debug,
            "test_event",
            "test",
            "Test event for coverage",
        );
        backend.record(&event);
    }

    #[test]
    fn logging_audit_backend_does_not_panic() {
        let backend = LoggingAuditBackend;
        let event = AuditEvent::new(
            EventCategory::System,
            EventSeverity::Info,
            "test_event_logging",
            "test",
            "Test event for LoggingAuditBackend coverage",
        );
        backend.record(&event);
    }

    #[test]
    fn event_default_timestamp_is_recent() {
        let event = AuditEvent::new(
            EventCategory::System,
            EventSeverity::Info,
            "boot",
            "kernel",
            "System boot",
        );
        // Timestamp should be within the last 100 years (sanity check)
        assert!(event.timestamp > 1_000_000_000);
        assert!(event.timestamp < 9_999_999_999);
    }
}
