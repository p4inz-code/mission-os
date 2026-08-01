//! Audit logging boundary for mission-driverd.
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
//! Per MOS-ENG-SEC-001 §8.1, the following driver events are logged:
//! - Drivers: install, update, rollback, verification failure
//!
//! This module is self-contained within mission-driverd and does not
//! depend on mission-securityd's audit module.

use serde::{Deserialize, Serialize};
use std::fmt;
use std::time::{SystemTime, UNIX_EPOCH};

/// Categories of audit-relevant events for driver management.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EventCategory {
    /// Driver installation events.
    DriverInstall,
    /// Driver update events.
    DriverUpdate,
    /// Driver removal events.
    DriverRemove,
    /// Driver verification events (signature, compatibility).
    DriverVerification,
    /// Hardware detection events.
    HardwareDetection,
    /// Authorization and privilege events.
    Authorization,
    /// Configuration changes.
    Configuration,
    /// System lifecycle events (start, stop, scan).
    System,
    /// Source query and resolution events.
    Source,
    /// Package download events.
    Download,
    /// Package integrity verification events.
    Integrity,
}

impl fmt::Display for EventCategory {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            EventCategory::DriverInstall => write!(f, "driver_install"),
            EventCategory::DriverUpdate => write!(f, "driver_update"),
            EventCategory::DriverRemove => write!(f, "driver_remove"),
            EventCategory::DriverVerification => write!(f, "driver_verification"),
            EventCategory::HardwareDetection => write!(f, "hardware_detection"),
            EventCategory::Authorization => write!(f, "authorization"),
            EventCategory::Configuration => write!(f, "configuration"),
            EventCategory::System => write!(f, "system"),
            EventCategory::Source => write!(f, "source"),
            EventCategory::Download => write!(f, "download"),
            EventCategory::Integrity => write!(f, "integrity"),
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

/// A structured audit event for driver management.
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
    /// The action that occurred (e.g., "driver_install_requested").
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
    /// * `action` - A short action identifier (e.g., "driver_install_requested").
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
#[derive(Debug, Clone)]
pub struct LogAuditBackend;

impl AuditBackend for LogAuditBackend {
    fn record(&self, event: &AuditEvent) {
        let json = event.to_json();
        eprintln!("[AUDIT] {json}");
    }
}

/// Audit backend that integrates with mission-core logging.
#[derive(Debug, Clone)]
pub struct LoggingAuditBackend;

impl AuditBackend for LoggingAuditBackend {
    fn record(&self, event: &AuditEvent) {
        let json = event.to_json();
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
            EventCategory::DriverInstall,
            EventSeverity::Info,
            "driver_install_requested",
            "user:admin",
            "Driver 'nvidia' installation requested from source 'vendor'",
        );
        assert_eq!(event.category, EventCategory::DriverInstall);
        assert_eq!(event.severity, EventSeverity::Info);
        assert_eq!(event.action, "driver_install_requested");
        assert!(event.timestamp > 0);
        assert!(event.correlation_id.is_none());
    }

    #[test]
    fn audit_event_with_correlation() {
        let event = AuditEvent::new(
            EventCategory::DriverVerification,
            EventSeverity::Warning,
            "signature_verification_failed",
            "system",
            "Driver signature verification failed for 'nvidia'",
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
            "mission-driverd",
            "Driver service started successfully",
        );
        let json = event.to_json();
        assert!(json.contains(r#""action":"service_started""#));
        assert!(json.contains(r#""category":"system""#));
        assert!(json.contains(r#""severity":"info""#));
    }

    #[test]
    fn audit_event_json_no_secrets() {
        let event = AuditEvent::new(
            EventCategory::DriverInstall,
            EventSeverity::Info,
            "install_completed",
            "user:bob",
            "Driver installed successfully",
        );
        let json = event.to_json();
        assert!(!json.contains("password"));
        assert!(!json.contains("secret"));
    }

    #[test]
    fn category_display() {
        assert_eq!(EventCategory::DriverInstall.to_string(), "driver_install");
        assert_eq!(EventCategory::DriverRemove.to_string(), "driver_remove");
        assert_eq!(EventCategory::System.to_string(), "system");
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
            "Test event",
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
            "Test event for coverage",
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
        assert!(event.timestamp > 1_000_000_000);
        assert!(event.timestamp < 9_999_999_999);
    }
}
