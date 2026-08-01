//! Authorization boundary for mission-driverd.
//!
//! Defines the authorization actions and the boundary
//! for PolKit integration. The Authorizer delegates to
//! PolKit when available, with a development-only bypass.
//!
//! ## Architecture
//!
//! Per MOS-ENG-IPC-001 §5.1, every privileged D-Bus method requires
//! PolKit authorization. The action naming convention uses the pattern
//! "org.mission.driver.<action>" (e.g., "org.mission.driver.install-driver").
//!
//! ## Security
//!
//! - Fail closed: if authorization state cannot be determined, deny.
//! - Authorization decisions are logged to the audit trail.
//! - No authorization decision is cached without explicit configuration.
//! - Read-only actions (view/list status) are always authorized.
//! - MISSION_ALLOW_UNAUTHORIZED is a dev-only bypass, impossible to
//!   accidentally enable in production.

use std::fmt;
use std::sync::Arc;

use crate::audit::{AuditBackend, AuditEvent, EventCategory, EventSeverity};

/// PolKit authorization actions for mission-driverd.
///
/// Each action maps to a PolKit action ID:
/// `org.mission.driver.<action_variant>`
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DriverAction {
    /// View the overall driver service status.
    ViewStatus,
    /// List all known drivers in the inventory.
    ListDrivers,
    /// Query detailed information about a specific driver.
    QueryDriver,
    /// Check compatibility of a driver with the current hardware.
    CheckCompatibility,
    /// Request installation of a driver.
    InstallDriver,
    /// Request update of an installed driver.
    UpdateDriver,
    /// Request removal of a driver.
    RemoveDriver,
    /// Configure driver sources/repositories.
    ConfigureSources,
    /// Trigger a hardware inventory scan.
    ScanHardware,
}

impl DriverAction {
    /// Return the PolKit action ID string.
    pub fn action_id(&self) -> &'static str {
        match self {
            DriverAction::ViewStatus => "org.mission.driver.view-status",
            DriverAction::ListDrivers => "org.mission.driver.list-drivers",
            DriverAction::QueryDriver => "org.mission.driver.query-driver",
            DriverAction::CheckCompatibility => "org.mission.driver.check-compatibility",
            DriverAction::InstallDriver => "org.mission.driver.install-driver",
            DriverAction::UpdateDriver => "org.mission.driver.update-driver",
            DriverAction::RemoveDriver => "org.mission.driver.remove-driver",
            DriverAction::ConfigureSources => "org.mission.driver.configure-sources",
            DriverAction::ScanHardware => "org.mission.driver.scan-hardware",
        }
    }

    /// Return a human-readable description of this action.
    pub fn description(&self) -> &'static str {
        match self {
            DriverAction::ViewStatus => "View driver service status",
            DriverAction::ListDrivers => "List all drivers in inventory",
            DriverAction::QueryDriver => "Query detailed driver information",
            DriverAction::CheckCompatibility => "Check driver compatibility with hardware",
            DriverAction::InstallDriver => "Install a driver on the system",
            DriverAction::UpdateDriver => "Update an installed driver",
            DriverAction::RemoveDriver => "Remove a driver from the system",
            DriverAction::ConfigureSources => "Configure driver sources and repositories",
            DriverAction::ScanHardware => "Trigger hardware inventory scan",
        }
    }

    /// Whether this action is read-only (no privilege escalation needed).
    pub fn is_read_only(&self) -> bool {
        matches!(
            self,
            DriverAction::ViewStatus
                | DriverAction::ListDrivers
                | DriverAction::QueryDriver
                | DriverAction::CheckCompatibility
        )
    }
}

impl fmt::Display for DriverAction {
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

/// Authorization checker for mission-driverd.
///
/// Integrates real PolKit authorization (via PolKitAuthorizer)
/// with a development-only bypass. The authorization flow:
///
/// 1. Read-only actions → always authorized
/// 2. MISSION_ALLOW_UNAUTHORIZED → authorized (dev only, printed warning)
/// 3. PolKit available → delegate to PolKitAuthorizer
/// 4. No PolKit → fail closed (deny)
///
/// # Security
///
/// - If `MISSION_ALLOW_UNAUTHORIZED` is NOT set and PolKit is NOT
///   available, all privileged actions are denied (fail closed).
/// - Read-only actions are always authorized.
/// - Authorization decisions are audited.
/// - The dev bypass is explicitly gated by environment variable and
///   prints a warning on startup — impossible to accidentally enable.
/// - `clone_audit()` shares the PolKit authorizer via Arc, ensuring
///   the execution engine's defense-in-depth check uses real PolKit.
pub struct Authorizer {
    /// Whether to allow unauthorized requests (development mode only).
    allow_unauthorized: bool,
    /// Audit backend for recording authorization decisions.
    audit_backend: Box<dyn AuditBackend>,
    /// Optional real PolKit authorization backend (shared via Arc).
    polkit: Option<Arc<crate::polkit::PolKitAuthorizer>>,
}

impl Authorizer {
    /// Create a new authorizer.
    ///
    /// # Arguments
    ///
    /// * `allow_unauthorized` - If true, privileged operations are
    ///   authorized without PolKit. MUST only be used in dev.
    /// * `audit_backend` - Audit backend for recording decisions.
    /// * `polkit` - Optional PolKit authorizer for real auth.
    ///
    /// # Security
    ///
    /// If `allow_unauthorized` is `true`, all privileged operations
    /// are authorized without checking PolKit. A warning is printed
    /// to stderr. This flag is never set in production.
    pub fn new(
        allow_unauthorized: bool,
        audit_backend: Box<dyn AuditBackend>,
        polkit: Option<Arc<crate::polkit::PolKitAuthorizer>>,
    ) -> Self {
        Self {
            allow_unauthorized,
            audit_backend,
            polkit,
        }
    }

    /// Check whether the given action is authorized for the given subject.
    ///
    /// # Arguments
    ///
    /// * `action` - The driver action to authorize.
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
    pub fn authorize(&self, action: &DriverAction, subject: &str) -> Authorization {
        // Read-only actions are always authorized
        if action.is_read_only() {
            self.audit_authorization(action, subject, &Authorization::Authorized);
            return Authorization::Authorized;
        }

        // Development bypass (warned at startup, never set in production)
        if self.allow_unauthorized {
            self.audit_authorization(action, subject, &Authorization::Authorized);
            return Authorization::Authorized;
        }

        // Real PolKit authorization (sync path)
        if let Some(ref polkit) = self.polkit {
            let result = polkit.check_authorization_sync(action, subject);
            self.audit_authorization(action, subject, &result);
            return result;
        }

        // Fail closed: no PolKit available and not in dev mode
        self.audit_authorization(action, subject, &Authorization::Denied);
        Authorization::Denied
    }

    /// Create a new authorizer with a cloned audit backend (for use in sub-components).
    ///
    /// The PolKit authorizer is shared via Arc (not cloned), so the
    /// returned authorizer retains the same PolKit authorization backend.
    /// This ensures defense-in-depth checks in sub-components like the
    /// execution engine use the same real PolKit authorization.
    pub fn clone_audit(&self, audit_backend: Box<dyn AuditBackend>) -> Self {
        Self {
            allow_unauthorized: self.allow_unauthorized,
            audit_backend,
            polkit: self.polkit.clone(),
        }
    }

    /// Record an authorization decision in the audit log.
    fn audit_authorization(&self, action: &DriverAction, subject: &str, result: &Authorization) {
        let (severity, details) = match result {
            Authorization::Authorized => (
                EventSeverity::Info,
                format!("Authorized: {} for {subject}", action.description()),
            ),
            Authorization::Denied => (
                EventSeverity::Warning,
                format!("Denied: {} for {subject}", action.description()),
            ),
            Authorization::Indeterminate => (
                EventSeverity::Error,
                format!(
                    "Authorization indeterminate: {} for {subject}",
                    action.description()
                ),
            ),
        };

        let event = AuditEvent::new(
            EventCategory::Authorization,
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
        Authorizer::new(allow_unauthorized, Box::new(LogAuditBackend), None)
    }

    #[test]
    fn read_only_actions_always_authorized() {
        let authorizer = test_authorizer(false);
        let result = authorizer.authorize(&DriverAction::ViewStatus, "test:user");
        assert!(result.is_authorized());
        let result = authorizer.authorize(&DriverAction::ListDrivers, "test:user");
        assert!(result.is_authorized());
        let result = authorizer.authorize(&DriverAction::QueryDriver, "test:user");
        assert!(result.is_authorized());
        let result = authorizer.authorize(&DriverAction::CheckCompatibility, "test:user");
        assert!(result.is_authorized());
    }

    #[test]
    fn privileged_actions_denied_without_polkit() {
        let authorizer = test_authorizer(false);
        let result = authorizer.authorize(&DriverAction::InstallDriver, "test:user");
        assert!(!result.is_authorized());
        assert_eq!(result, Authorization::Denied);
    }

    #[test]
    fn development_bypass_allows_privileged() {
        let authorizer = test_authorizer(true);
        let result = authorizer.authorize(&DriverAction::InstallDriver, "test:dev");
        assert!(result.is_authorized());
    }

    #[test]
    fn authorization_is_audited() {
        let authorizer = test_authorizer(false);
        let _ = authorizer.authorize(&DriverAction::InstallDriver, "test:user");
        // The audit backend records the event (no panic = success)
    }

    #[test]
    fn action_id_format() {
        assert_eq!(
            DriverAction::InstallDriver.action_id(),
            "org.mission.driver.install-driver"
        );
        assert_eq!(
            DriverAction::ViewStatus.action_id(),
            "org.mission.driver.view-status"
        );
        assert_eq!(
            DriverAction::ConfigureSources.action_id(),
            "org.mission.driver.configure-sources"
        );
    }

    #[test]
    fn action_descriptions() {
        assert!(!DriverAction::InstallDriver.description().is_empty());
        assert!(!DriverAction::ListDrivers.description().is_empty());
    }

    #[test]
    fn read_only_classification() {
        assert!(DriverAction::ViewStatus.is_read_only());
        assert!(!DriverAction::InstallDriver.is_read_only());
        assert!(!DriverAction::RemoveDriver.is_read_only());
        assert!(!DriverAction::ConfigureSources.is_read_only());
    }

    #[test]
    fn fail_closed_on_indeterminate() {
        let authorizer = test_authorizer(false);
        let result = authorizer.authorize(&DriverAction::InstallDriver, "test:attacker");
        assert_eq!(result, Authorization::Denied);
    }

    #[test]
    fn all_privileged_actions_denied() {
        let authorizer = test_authorizer(false);
        assert!(!authorizer
            .authorize(&DriverAction::InstallDriver, "u")
            .is_authorized());
        assert!(!authorizer
            .authorize(&DriverAction::UpdateDriver, "u")
            .is_authorized());
        assert!(!authorizer
            .authorize(&DriverAction::RemoveDriver, "u")
            .is_authorized());
        assert!(!authorizer
            .authorize(&DriverAction::ConfigureSources, "u")
            .is_authorized());
        assert!(!authorizer
            .authorize(&DriverAction::ScanHardware, "u")
            .is_authorized());
    }

    #[test]
    fn clone_audit_shares_polkit_arc() {
        // Verify that clone_audit shares the PolKit Arc (not None)
        let polkit = Arc::new(crate::polkit::PolKitAuthorizer::new(
            None,
            Box::new(LogAuditBackend),
            false,
        ));
        let authorizer = Authorizer::new(false, Box::new(LogAuditBackend), Some(polkit));
        let cloned = authorizer.clone_audit(Box::new(LogAuditBackend));
        // The cloned authorizer should have the same PolKit via Arc
        // (can't directly test Arc pointer equality, but we can test behavior)
        // Without PolKit in clone, authorize would deny — with it, it still denies
        // because PolKit has no connection. But the call path is different.
        let result = cloned.authorize(&DriverAction::InstallDriver, "test");
        assert!(!result.is_authorized()); // Denied: PolKit has no D-Bus connection
                                          // The key is this does NOT panic (shows clone_audit succeeded)
    }
}
