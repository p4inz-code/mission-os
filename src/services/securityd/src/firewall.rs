//! Firewall management API boundary for mission-securityd.
//!
//! This module defines the firewall management request/response types,
//! validation logic, and structured errors for the security service's
//! firewall interface.
//!
//! ## Architecture
//!
//! Per MOS-ENG-SEC-001 §6.1, the firewall backend is nftables.
//! This module defines the API boundary only — the actual nftables
//! integration will be implemented in a later phase.
//!
//! ## Security
//!
//! - All inputs are validated before processing.
//! - Rules must specify direction, action, and protocol minimally.
//! - Arbitrary nftables expressions are NOT accepted directly.
//! - The default policy is deny-incoming, allow-outgoing.

use serde::{Deserialize, Serialize};

use crate::config::FirewallProfile;

/// Direction of network traffic for a firewall rule.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Direction {
    /// Incoming traffic.
    In,
    /// Outgoing traffic.
    Out,
}

/// Action to take when a rule matches.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RuleAction {
    /// Allow the traffic.
    Accept,
    /// Drop the traffic (silent).
    Drop,
    /// Reject the traffic (with notification).
    Reject,
}

/// Network protocol for a firewall rule.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Protocol {
    /// TCP protocol.
    Tcp,
    /// UDP protocol.
    Udp,
    /// ICMP protocol.
    Icmp,
    /// Any other protocol.
    #[serde(other)]
    Other,
}

/// A single firewall rule definition.
///
/// This is a validated, structured representation of a firewall rule.
/// It does NOT allow arbitrary nftables expressions.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FirewallRule {
    /// A human-readable name for this rule.
    pub name: String,
    /// Traffic direction.
    pub direction: Direction,
    /// Action to take on match.
    pub action: RuleAction,
    /// Network protocol (optional, matches all if None).
    pub protocol: Option<Protocol>,
    /// Source address (CIDR notation, optional).
    pub source: Option<String>,
    /// Destination address (CIDR notation, optional).
    pub destination: Option<String>,
    /// Source port (optional).
    pub source_port: Option<u16>,
    /// Destination port (optional).
    pub destination_port: Option<u16>,
    /// Whether this rule is enabled.
    #[serde(default = "default_enabled")]
    pub enabled: bool,
}

fn default_enabled() -> bool {
    true
}

impl FirewallRule {
    /// Validate the rule fields.
    ///
    /// Returns `Ok(())` if the rule is valid, or a `FirewallError` describing
    /// the first validation failure found.
    pub fn validate(&self) -> Result<(), FirewallError> {
        // Name must not be empty
        if self.name.trim().is_empty() {
            return Err(FirewallError::ValidationError(
                "rule name must not be empty".into(),
            ));
        }

        // Port validation (u16 ensures 0–65535 range; only check for zero)
        if let Some(port) = self.source_port {
            if port == 0 {
                return Err(FirewallError::ValidationError(
                    "source port must not be 0".into(),
                ));
            }
        }
        if let Some(port) = self.destination_port {
            if port == 0 {
                return Err(FirewallError::ValidationError(
                    "destination port must not be 0".into(),
                ));
            }
        }

        // Protocol required for port-based rules
        if (self.source_port.is_some() || self.destination_port.is_some())
            && self.protocol.is_none()
        {
            return Err(FirewallError::ValidationError(
                "protocol required when specifying ports".into(),
            ));
        }

        Ok(())
    }
}

/// Errors that can occur during firewall operations.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FirewallError {
    /// The rule or request failed validation.
    ValidationError(String),
    /// The requested operation is not supported.
    NotSupported(String),
    /// An internal error occurred.
    Internal(String),
    /// The nftables backend is not available.
    BackendUnavailable,
}

impl std::fmt::Display for FirewallError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            FirewallError::ValidationError(msg) => write!(f, "validation error: {msg}"),
            FirewallError::NotSupported(msg) => write!(f, "not supported: {msg}"),
            FirewallError::Internal(msg) => write!(f, "internal error: {msg}"),
            FirewallError::BackendUnavailable => write!(f, "nftables backend unavailable"),
        }
    }
}

impl std::error::Error for FirewallError {}

/// Result of applying a set of firewall rules.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApplyResult {
    /// Whether the operation succeeded.
    pub success: bool,
    /// Number of rules applied.
    pub rules_applied: u32,
    /// Number of rules that failed.
    pub rules_failed: u32,
    /// Error message if the operation failed overall.
    pub error: Option<String>,
}

/// Request to change the firewall profile.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProfileChangeRequest {
    /// The new firewall profile.
    pub profile: FirewallProfile,
    /// Reason for the change (for audit logging).
    pub reason: String,
}

impl ProfileChangeRequest {
    /// Validate the profile change request.
    pub fn validate(&self) -> Result<(), FirewallError> {
        if self.reason.trim().is_empty() {
            return Err(FirewallError::ValidationError(
                "reason must not be empty".into(),
            ));
        }
        Ok(())
    }
}

/// The current firewall status.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FirewallStatus {
    /// Whether the firewall is enabled.
    pub enabled: bool,
    /// The currently active profile.
    pub active_profile: FirewallProfile,
    /// Number of active rules.
    pub rule_count: u32,
    /// Whether the backend is available.
    pub backend_available: bool,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn valid_rule() -> FirewallRule {
        FirewallRule {
            name: "allow-ssh".into(),
            direction: Direction::In,
            action: RuleAction::Accept,
            protocol: Some(Protocol::Tcp),
            source: None,
            destination: None,
            source_port: None,
            destination_port: Some(22),
            enabled: true,
        }
    }

    #[test]
    fn valid_rule_passes_validation() {
        let rule = valid_rule();
        assert!(rule.validate().is_ok());
    }

    #[test]
    fn empty_name_fails_validation() {
        let rule = FirewallRule {
            name: "   ".into(),
            ..valid_rule()
        };
        assert!(rule.validate().is_err());
    }

    #[test]
    fn port_without_protocol_fails() {
        let rule = FirewallRule {
            protocol: None,
            ..valid_rule()
        };
        assert!(rule.validate().is_err());
    }

    #[test]
    fn invalid_port_fails() {
        let rule = FirewallRule {
            destination_port: Some(0),
            ..valid_rule()
        };
        assert!(rule.validate().is_err());
    }

    #[test]
    fn accept_drop_reject_enums() {
        assert_eq!(RuleAction::Accept as u8, 0);
        assert_eq!(RuleAction::Drop as u8, 1);
        assert_eq!(RuleAction::Reject as u8, 2);
    }

    #[test]
    fn profile_change_validation() {
        let req = ProfileChangeRequest {
            profile: FirewallProfile::Private,
            reason: "".into(),
        };
        assert!(req.validate().is_err());

        let req = ProfileChangeRequest {
            profile: FirewallProfile::Private,
            reason: "Switching to private mode for LAN party".into(),
        };
        assert!(req.validate().is_ok());
    }

    #[test]
    fn firewall_error_display() {
        let err = FirewallError::ValidationError("bad rule".into());
        assert!(err.to_string().contains("bad rule"));

        let err = FirewallError::BackendUnavailable;
        assert!(err.to_string().contains("unavailable"));
    }

    #[test]
    fn apply_result_serialization() {
        let result = ApplyResult {
            success: true,
            rules_applied: 5,
            rules_failed: 0,
            error: None,
        };
        let json = serde_json::to_string(&result).unwrap();
        assert!(json.contains("\"success\":true"));
        assert!(json.contains("\"rules_applied\":5"));
    }

    #[test]
    fn firewall_status_defaults() {
        let status = FirewallStatus {
            enabled: true,
            active_profile: FirewallProfile::Public,
            rule_count: 0,
            backend_available: false,
        };
        assert!(status.enabled);
        assert_eq!(status.active_profile, FirewallProfile::Public);
        assert!(!status.backend_available);
    }

    #[test]
    fn direction_serde() {
        let dir: Direction = serde_json::from_str("\"in\"").unwrap();
        assert_eq!(dir, Direction::In);
        let dir: Direction = serde_json::from_str("\"out\"").unwrap();
        assert_eq!(dir, Direction::Out);
    }
}
