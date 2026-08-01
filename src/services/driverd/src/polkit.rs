//! PolKit authorization integration for mission-driverd.
//!
//! Provides real PolKit authorization checks over D-Bus by
//! communicating with `org.freedesktop.PolicyKit1` on the
//! system bus. Implements the actual CheckAuthorization
//! D-Bus call format required by the PolKit daemon.
//!
//! ## Architecture
//!
//! Per MOS-ENG-IPC-001 §5.1, every privileged D-Bus method
//! requires PolKit authorization. This module implements the
//! real PolKit backend via D-Bus.
//!
//! ## CheckAuthorization Format
//!
//! The actual PolKit CheckAuthorization D-Bus method signature:
//! ```text
//! METHOD CheckAuthorization
//!     INPUT:
//!         subject: (sa{sv})       - Subject struct (kind + details)
//!         action_id: s             - Action identifier string
//!         details: a{ss}           - Details dictionary
//!         flags: u                 - CheckAuthorizationFlags
//!         cancellation_id: s       - Optional cancellation ID
//!     OUTPUT:
//!         authorized: b            - Whether action is authorized
//!         is_challenge: b          - Whether authentication is challenged
//!         details: a{sv}           - Response details
//! ```
//!
//! For system-bus callers, the subject is:
//! ```text
//! ("system-bus-name", {"name": <variant_containing_caller_name>})
//! ```
//!
//! ## Security
//!
//! - Fail closed: if PolKit is unavailable or returns an error,
//!   the operation is denied.
//! - MISSION_ALLOW_UNAUTHORIZED remains a development-only bypass.
//! - Authorization decisions are audited.
//! - The caller identity comes from D-Bus, not user-controlled data.

use std::collections::HashMap;

use zbus::connection;

use crate::audit::{AuditBackend, AuditEvent, EventCategory, EventSeverity};
use crate::authz::{Authorization, DriverAction};

// ── PolKit D-Bus Interface Constants ──────────────────────────────

/// PolKit authority D-Bus service name.
const POLKIT_SERVICE: &str = "org.freedesktop.PolicyKit1";

/// PolKit authority D-Bus object path.
const POLKIT_PATH: &str = "/org/freedesktop/PolicyKit1/Authority";

/// PolKit authority D-Bus interface.
const POLKIT_INTERFACE: &str = "org.freedesktop.PolicyKit1.Authority";

/// PolKit CheckAuthorization flags.
#[allow(dead_code)]
const POLKIT_FLAG_NONE: u32 = 0;
#[allow(dead_code)]
const POLKIT_FLAG_ALLOW_USER_INTERACTION: u32 = 1;

// ── PolKit Authorizer ─────────────────────────────────────────────

/// Real PolKit authorization checker.
///
/// Communicates with the PolKit daemon over D-Bus to perform
/// authorization checks. Uses the correct CheckAuthorization
/// D-Bus message format with proper subject construction.
///
/// Falls back to denial on any error (fail closed).
pub struct PolKitAuthorizer {
    /// D-Bus connection for PolKit queries.
    conn: Option<connection::Connection>,
    /// Audit backend for recording decisions.
    audit_backend: Box<dyn AuditBackend>,
    /// Whether unauthorized operations are allowed (dev mode).
    allow_unauthorized: bool,
}

impl PolKitAuthorizer {
    /// Create a new PolKit authorizer.
    ///
    /// # Arguments
    ///
    /// * `conn` - D-Bus system bus connection for PolKit queries.
    ///   If `None`, all privileged operations are denied (fail closed).
    /// * `audit_backend` - Audit backend for recording decisions.
    /// * `allow_unauthorized` - Development bypass (MUST be false in production).
    pub fn new(
        conn: Option<connection::Connection>,
        audit_backend: Box<dyn AuditBackend>,
        allow_unauthorized: bool,
    ) -> Self {
        Self {
            conn,
            audit_backend,
            allow_unauthorized,
        }
    }

    /// Check authorization for a driver action (async path).
    ///
    /// Used by the D-Bus interface handlers.
    pub async fn check_authorization(&self, action: &DriverAction, caller: &str) -> Authorization {
        if action.is_read_only() {
            self.audit_authorization(action, caller, &Authorization::Authorized);
            return Authorization::Authorized;
        }
        if self.allow_unauthorized {
            self.audit_authorization(action, caller, &Authorization::Authorized);
            return Authorization::Authorized;
        }

        let conn = match &self.conn {
            Some(c) => c.clone(),
            None => {
                self.audit_authorization(action, caller, &Authorization::Denied);
                return Authorization::Denied;
            }
        };

        match Self::call_polkit_check(&conn, action, caller).await {
            Ok(true) => {
                self.audit_authorization(action, caller, &Authorization::Authorized);
                Authorization::Authorized
            }
            Ok(false) => {
                self.audit_authorization(action, caller, &Authorization::Denied);
                Authorization::Denied
            }
            Err(e) => {
                eprintln!("[polkit] PolKit check failed: {e}");
                self.audit_authorization(action, caller, &Authorization::Denied);
                Authorization::Denied
            }
        }
    }

    /// Check authorization for a driver action (sync path).
    ///
    /// Used by the sync execution engine. Uses tokio's
    /// `block_in_place` + `Handle::block_on` to perform
    /// the D-Bus call from a sync context.
    pub fn check_authorization_sync(&self, action: &DriverAction, caller: &str) -> Authorization {
        if action.is_read_only() {
            self.audit_authorization(action, caller, &Authorization::Authorized);
            return Authorization::Authorized;
        }
        if self.allow_unauthorized {
            self.audit_authorization(action, caller, &Authorization::Authorized);
            return Authorization::Authorized;
        }

        let conn = match &self.conn {
            Some(c) => c.clone(),
            None => {
                self.audit_authorization(action, caller, &Authorization::Denied);
                return Authorization::Denied;
            }
        };

        let handle = match tokio::runtime::Handle::try_current() {
            Ok(h) => h,
            Err(_) => {
                eprintln!("[polkit] no tokio runtime for sync auth, denying");
                self.audit_authorization(action, caller, &Authorization::Denied);
                return Authorization::Denied;
            }
        };

        let action_clone = *action;
        let caller_owned = caller.to_string();
        let result = tokio::task::block_in_place(|| {
            handle.block_on(Self::call_polkit_check(&conn, &action_clone, &caller_owned))
        });

        match result {
            Ok(true) => {
                self.audit_authorization(action, caller, &Authorization::Authorized);
                Authorization::Authorized
            }
            Ok(false) => {
                self.audit_authorization(action, caller, &Authorization::Denied);
                Authorization::Denied
            }
            Err(e) => {
                eprintln!("[polkit] sync PolKit check failed: {e}");
                self.audit_authorization(action, caller, &Authorization::Denied);
                Authorization::Denied
            }
        }
    }

    /// Call the PolKit CheckAuthorization D-Bus method with the
    /// correct message format.
    ///
    /// Constructs a proper subject struct for system-bus callers:
    /// ```text
    /// ("system-bus-name", {"name": <variant_with_caller_name>})
    /// ```
    async fn call_polkit_check(
        conn: &connection::Connection,
        action: &DriverAction,
        caller: &str,
    ) -> Result<bool, String> {
        let action_id = action.action_id();

        // Build the subject details dict as HashMap<String, zvariant::Value>
        // This represents a{sv} (dict of string to variant)
        let mut subject_details: HashMap<String, zvariant::Value> = HashMap::new();
        subject_details.insert("name".to_string(), zvariant::Value::new(caller.to_string()));

        // The subject is a tuple: (kind: String, details: HashMap<String, Value>)
        // This serializes as (sa{sv}) per the PolKit API
        let subject = ("system-bus-name".to_string(), subject_details);

        // Empty details dict (a{ss})
        let details: HashMap<String, String> = HashMap::new();

        // Flags: no user interaction by default (admin authentication via polkit agent)
        let flags: u32 = POLKIT_FLAG_ALLOW_USER_INTERACTION;

        // Cancellation ID (empty = no cancellation)
        let cancellation_id = "";

        let result = conn
            .call_method(
                Some(POLKIT_SERVICE),
                POLKIT_PATH,
                Some(POLKIT_INTERFACE),
                "CheckAuthorization",
                &(
                    subject,
                    action_id.to_string(),
                    details,
                    flags,
                    cancellation_id,
                ),
            )
            .await;

        match result {
            Ok(msg) => {
                // Response: (authorized: bool, is_challenge: bool, details: a{sv})
                match msg
                    .body()
                    .deserialize::<(bool, bool, HashMap<String, zvariant::Value>)>()
                {
                    Ok((authorized, _, _)) => Ok(authorized),
                    Err(e) => Err(format!("PolKit response parse error: {e}")),
                }
            }
            Err(e) => Err(format!("PolKit D-Bus call failed: {e}")),
        }
    }

    fn audit_authorization(&self, action: &DriverAction, subject: &str, result: &Authorization) {
        let (severity, details) = match result {
            Authorization::Authorized => (
                EventSeverity::Info,
                format!("PolKit authorized: {} for {subject}", action.description()),
            ),
            Authorization::Denied => (
                EventSeverity::Warning,
                format!("PolKit denied: {} for {subject}", action.description()),
            ),
            Authorization::Indeterminate => (
                EventSeverity::Error,
                format!(
                    "PolKit indeterminate: {} for {subject}",
                    action.description()
                ),
            ),
        };

        let event = AuditEvent::new(
            EventCategory::Authorization,
            severity,
            "polkit_authorization_check",
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

    fn test_authorizer(allow_unauthorized: bool) -> PolKitAuthorizer {
        PolKitAuthorizer {
            conn: None,
            audit_backend: Box::new(LogAuditBackend),
            allow_unauthorized,
        }
    }

    #[test]
    fn authorizer_new_without_connection() {
        let authorizer = test_authorizer(false);
        assert!(!authorizer.allow_unauthorized);
    }

    #[test]
    fn authorizer_dev_bypass() {
        let authorizer = test_authorizer(true);
        assert!(authorizer.allow_unauthorized);
    }

    #[test]
    fn sync_check_without_connection_denies() {
        let authorizer = test_authorizer(false);
        let result =
            authorizer.check_authorization_sync(&DriverAction::InstallDriver, "test:caller");
        assert!(!result.is_authorized());
        assert_eq!(result, Authorization::Denied);
    }

    #[test]
    fn sync_check_read_only_allowed() {
        let authorizer = test_authorizer(false);
        let result = authorizer.check_authorization_sync(&DriverAction::ViewStatus, "test:caller");
        assert!(result.is_authorized());
    }

    #[test]
    fn sync_check_dev_bypass() {
        let authorizer = test_authorizer(true);
        let result = authorizer.check_authorization_sync(&DriverAction::InstallDriver, "test:dev");
        assert!(result.is_authorized());
    }
}
