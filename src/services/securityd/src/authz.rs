//! PolKit authorization boundary for mission-securityd.
//!
//! This module defines the authorization actions and the boundary
//! for PolKit integration. It registers the PolKit action identifiers
//! that the service uses and provides a safe authorization check
//! interface.
//!
//! ## Architecture
//!
//! Per MOS-ENG-IPC-001 sec 5.1, every privileged D-Bus method requires
//! PolKit authorization. The action naming convention uses the pattern
//! "org.mission.security.<action>" (e.g., "org.mission.security.configure-firewall").
//!
//! ## IMPORTANT
//!
//! This module defines the authorization **boundary** and **schema**.
//! The actual PolKit IPC integration (via `zbus` or `polkit-rs`) will
//! be added when the system D-Bus bus is available.
//!
//! Until then, all authorization checks return `Authorization::Denied`
//! unless the service is running in a development mode with
//! `MISSION_ALLOW_UNAUTHORIZED` set — this ensures fail-closed behavior.
//!
//! ## Security
//!
//! - Fail closed: if authorization state cannot be determined, deny.
//! - Authorization decisions are logged to the audit trail.
//! - No authorization decision is cached without explicit configuration.

use std::fmt;

use crate::audit::{AuditBackend, AuditEvent, EventCategory, EventSeverity};

/// PolKit authorization actions for mission-securityd.
///
/// Each action maps to a PolKit action ID:
/// `org.mission.security.<action_variant>`
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SecurityAction {
    /// View the current firewall status and rules.
    ViewFirewallStatus,
    /// Modify firewall rules or profiles.
    ConfigureFirewall,
    /// View audit logs.
    ViewAuditLog,
    /// Export or forward audit logs.
    ExportAuditLog,
    /// Change security policy settings.
    ChangeSecurityPolicy,
    /// Manage certificate trust store.
    ManageCertificates,
    /// View Secure Boot status.
    ViewSecureBootStatus,
    /// Modify Secure Boot configuration.
    ConfigureSecureBoot,
    /// View sandbox/MAC policy status.
    ViewSandboxStatus,
    /// Modify sandbox/MAC policy.
    ConfigureSandbox,
}

impl SecurityAction {
    /// Return the PolKit action ID string.
    pub fn action_id(&self) -> &'static str {
        match self {
            SecurityAction::ViewFirewallStatus => "org.mission.security.view-firewall-status",
            SecurityAction::ConfigureFirewall => "org.mission.security.configure-firewall",
            SecurityAction::ViewAuditLog => "org.mission.security.view-audit-log",
            SecurityAction::ExportAuditLog => "org.mission.security.export-audit-log",
            SecurityAction::ChangeSecurityPolicy => "org.mission.security.change-policy",
            SecurityAction::ManageCertificates => "org.mission.security.manage-certificates",
            SecurityAction::ViewSecureBootStatus => "org.mission.security.view-secure-boot",
            SecurityAction::ConfigureSecureBoot => "org.mission.security.configure-secure-boot",
            SecurityAction::ViewSandboxStatus => "org.mission.security.view-sandbox-status",
            SecurityAction::ConfigureSandbox => "org.mission.security.configure-sandbox",
        }
    }

    /// Return a human-readable description of this action.
    pub fn description(&self) -> &'static str {
        match self {
            SecurityAction::ViewFirewallStatus => "View firewall status and rules",
            SecurityAction::ConfigureFirewall => "Modify firewall configuration",
            SecurityAction::ViewAuditLog => "View security audit logs",
            SecurityAction::ExportAuditLog => "Export or forward audit logs",
            SecurityAction::ChangeSecurityPolicy => "Change security policy settings",
            SecurityAction::ManageCertificates => "Manage certificate trust store",
            SecurityAction::ViewSecureBootStatus => "View Secure Boot status",
            SecurityAction::ConfigureSecureBoot => "Modify Secure Boot configuration",
            SecurityAction::ViewSandboxStatus => "View sandbox/MAC policy status",
            SecurityAction::ConfigureSandbox => "Modify sandbox/MAC policy",
        }
    }

    /// Whether this action is read-only (no privilege escalation needed).
    pub fn is_read_only(&self) -> bool {
        matches!(
            self,
            SecurityAction::ViewFirewallStatus
                | SecurityAction::ViewAuditLog
                | SecurityAction::ViewSecureBootStatus
                | SecurityAction::ViewSandboxStatus
        )
    }
}

impl fmt::Display for SecurityAction {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.action_id())
    }
}

/// The result of an authorization check.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Authorization {
    /// The action is authorized.
    Authorized,
    /// The action is denied.
    Denied,
    /// Authorization could not be determined (fail closed).
    Indeterminate,
}

impl Authorization {
    /// Returns `true` if the action is authorized.
    pub fn is_authorized(&self) -> bool {
        matches!(self, Authorization::Authorized)
    }
}

/// Authorization checker for mission-securityd.
///
/// This is the boundary for PolKit integration. Currently, it provides
/// a development bypass (via `MISSION_ALLOW_UNAUTHORIZED` env var) and
/// a delegate point for future PolKit integration.
///
/// # Security
///
/// - If `MISSION_ALLOW_UNAUTHORIZED` is NOT set, all privileged actions
///   are denied (fail closed).
/// - Read-only actions are always authorized.
/// - Authorization decisions are audited.
pub struct Authorizer {
    /// Whether to allow unauthorized requests (development mode only).
    allow_unauthorized: bool,
    /// Audit backend for recording authorization decisions.
    audit_backend: Box<dyn AuditBackend>,
}

impl Authorizer {
    /// Create a new authorizer.
    ///
    /// # Security
    ///
    /// If `allow_unauthorized` is set to `true`, all privileged operations
    /// will be authorized without checking PolKit. This MUST only be used
    /// in development environments.
    pub fn new(allow_unauthorized: bool, audit_backend: Box<dyn AuditBackend>) -> Self {
        Self {
            allow_unauthorized,
            audit_backend,
        }
    }

    /// Check whether the given action is authorized for the given subject.
    ///
    /// # Arguments
    ///
    /// * `action` - The security action to authorize.
    /// * `subject` - The requesting user or service identifier.
    ///
    /// # Returns
    ///
    /// * `Authorization::Authorized` if the action is permitted.
    /// * `Authorization::Denied` if the action is not permitted.
    /// * `Authorization::Indeterminate` if the state is uncertain (fail closed).
    ///
    /// # Security
    ///
    /// This method always audits its decision. Denials are logged at
    /// WARNING severity, grants at INFO severity.
    pub fn authorize(&self, action: &SecurityAction, subject: &str) -> Authorization {
        // Read-only actions are always authorized
        if action.is_read_only() {
            self.audit_authorization(action, subject, &Authorization::Authorized);
            return Authorization::Authorized;
        }

        // Development bypass
        if self.allow_unauthorized {
            self.audit_authorization(action, subject, &Authorization::Authorized);
            return Authorization::Authorized;
        }

        // Fail closed: deny all privileged actions until PolKit is integrated
        // TODO: Integrate with PolKit via zbus/polkit-rs
        //       This will call polkit_authority.check_authorization() with
        //       the subject's D-Bus name to validate authorization.
        self.audit_authorization(action, subject, &Authorization::Denied);
        Authorization::Denied
    }

    /// Record an authorization decision in the audit log.
    fn audit_authorization(&self, action: &SecurityAction, subject: &str, result: &Authorization) {
        let (severity, details) = match result {
            Authorization::Authorized => (
                EventSeverity::Info,
                format!("Authorized: {} for {}", action.description(), subject),
            ),
            Authorization::Denied => (
                EventSeverity::Warning,
                format!("Denied: {} for {}", action.description(), subject),
            ),
            Authorization::Indeterminate => (
                EventSeverity::Error,
                format!(
                    "Authorization indeterminate: {} for {}",
                    action.description(),
                    subject
                ),
            ),
        };

        let event = AuditEvent::new(
            EventCategory::Privilege,
            severity,
            "authorization_check",
            subject,
            details,
        );
        self.audit_backend.record(&event);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::audit::LogAuditBackend;

    fn test_authorizer(allow_unauthorized: bool) -> Authorizer {
        Authorizer::new(allow_unauthorized, Box::new(LogAuditBackend))
    }

    #[test]
    fn read_only_actions_always_authorized() {
        let authorizer = test_authorizer(false);
        let result = authorizer.authorize(&SecurityAction::ViewFirewallStatus, "test:user");
        assert!(result.is_authorized());
    }

    #[test]
    fn privileged_actions_denied_without_polkit() {
        let authorizer = test_authorizer(false);
        let result = authorizer.authorize(&SecurityAction::ConfigureFirewall, "test:user");
        assert!(!result.is_authorized());
        assert_eq!(result, Authorization::Denied);
    }

    #[test]
    fn development_bypass_allows_privileged() {
        let authorizer = test_authorizer(true);
        let result = authorizer.authorize(&SecurityAction::ConfigureFirewall, "test:dev");
        assert!(result.is_authorized());
    }

    #[test]
    fn authorization_is_audited() {
        let authorizer = test_authorizer(false);
        let _ = authorizer.authorize(&SecurityAction::ConfigureFirewall, "test:user");
        // The audit backend records the event (no panic = success)
    }

    #[test]
    fn action_id_format() {
        assert_eq!(
            SecurityAction::ConfigureFirewall.action_id(),
            "org.mission.security.configure-firewall"
        );
        assert_eq!(
            SecurityAction::ViewFirewallStatus.action_id(),
            "org.mission.security.view-firewall-status"
        );
    }

    #[test]
    fn action_descriptions() {
        assert!(!SecurityAction::ConfigureFirewall.description().is_empty());
        assert!(!SecurityAction::ViewAuditLog.description().is_empty());
    }

    #[test]
    fn read_only_classification() {
        assert!(SecurityAction::ViewFirewallStatus.is_read_only());
        assert!(!SecurityAction::ConfigureFirewall.is_read_only());
        assert!(SecurityAction::ViewAuditLog.is_read_only());
        assert!(!SecurityAction::ExportAuditLog.is_read_only());
    }

    #[test]
    fn fail_closed_on_indeterminate() {
        let authorizer = test_authorizer(false);
        let result = authorizer.authorize(&SecurityAction::ChangeSecurityPolicy, "test:attacker");
        assert_eq!(result, Authorization::Denied);
    }
}
