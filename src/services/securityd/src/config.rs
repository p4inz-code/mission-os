//! Service configuration for mission-securityd.
//!
//! Provides typed configuration structures for the security service.
//! Configuration is loaded from TOML files via mission-core's config system.

use serde::{Deserialize, Serialize};

/// Default firewall profile to apply on service start.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FirewallProfile {
    /// Block incoming, allow outgoing (stateful).
    #[default]
    Public,
    /// Allow LAN, block WAN incoming.
    Private,
    /// Development mode with selected open ports.
    Development,
    /// User-defined custom rules.
    Custom,
}

/// Audit log configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuditConfig {
    /// Whether audit logging is enabled.
    #[serde(default = "default_audit_enabled")]
    pub enabled: bool,
    /// Maximum log file size before rotation (bytes).
    #[serde(default = "default_audit_max_size")]
    pub max_size_bytes: u64,
    /// Maximum number of rotated log files to keep.
    #[serde(default = "default_audit_max_files")]
    pub max_files: u32,
    /// Whether to forward audit events to syslog.
    #[serde(default)]
    pub syslog_forward: bool,
}

fn default_audit_enabled() -> bool {
    true
}
fn default_audit_max_size() -> u64 {
    10 * 1024 * 1024
} // 10 MB
fn default_audit_max_files() -> u32 {
    5
}

impl Default for AuditConfig {
    fn default() -> Self {
        Self {
            enabled: default_audit_enabled(),
            max_size_bytes: default_audit_max_size(),
            max_files: default_audit_max_files(),
            syslog_forward: false,
        }
    }
}

/// Security service configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SecurityConfig {
    /// The D-Bus well-known name for this service.
    #[serde(default = "default_dbus_name")]
    pub dbus_name: String,
    /// The default firewall profile.
    #[serde(default)]
    pub default_firewall_profile: FirewallProfile,
    /// Audit logging configuration.
    #[serde(default)]
    pub audit: AuditConfig,
    /// Whether to enable firewall on service start.
    #[serde(default = "default_firewall_enabled")]
    pub firewall_enabled: bool,
}

fn default_dbus_name() -> String {
    "org.mission.Security1".into()
}
fn default_firewall_enabled() -> bool {
    true
}

impl Default for SecurityConfig {
    fn default() -> Self {
        Self {
            dbus_name: default_dbus_name(),
            default_firewall_profile: FirewallProfile::default(),
            audit: AuditConfig::default(),
            firewall_enabled: default_firewall_enabled(),
        }
    }
}

/// Load the security service configuration from a TOML file.
///
/// Falls back to defaults if the file does not exist.
pub fn load_config(path: &std::path::Path) -> SecurityConfig {
    match std::fs::read_to_string(path) {
        Ok(content) => match toml::from_str(&content) {
            Ok(cfg) => cfg,
            Err(e) => {
                eprintln!("[securityd] config parse error: {e}, using defaults");
                SecurityConfig::default()
            }
        },
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            eprintln!("[securityd] config not found at {path:?}, using defaults");
            SecurityConfig::default()
        }
        Err(e) => {
            eprintln!("[securityd] cannot read config {path:?}: {e}, using defaults");
            SecurityConfig::default()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn config_default() {
        let cfg = SecurityConfig::default();
        assert_eq!(cfg.dbus_name, "org.mission.Security1");
        assert_eq!(cfg.default_firewall_profile, FirewallProfile::Public);
        assert!(cfg.audit.enabled);
        assert!(cfg.firewall_enabled);
    }

    #[test]
    fn audit_default() {
        let audit = AuditConfig::default();
        assert!(audit.enabled);
        assert_eq!(audit.max_size_bytes, 10 * 1024 * 1024);
        assert_eq!(audit.max_files, 5);
    }

    #[test]
    fn config_serialization_roundtrip() {
        let cfg = SecurityConfig::default();
        let toml_str = toml::to_string(&cfg).unwrap();
        let parsed: SecurityConfig = toml::from_str(&toml_str).unwrap();
        assert_eq!(parsed.dbus_name, cfg.dbus_name);
        assert_eq!(
            parsed.default_firewall_profile,
            cfg.default_firewall_profile
        );
    }

    #[test]
    fn config_parse_valid_toml() {
        let toml_str = r#"
dbus_name = "org.mission.Security1"
default_firewall_profile = "private"
firewall_enabled = true

[audit]
enabled = true
max_size_bytes = 5242880
max_files = 3
syslog_forward = false
"#;
        let cfg: SecurityConfig = toml::from_str(toml_str).unwrap();
        assert_eq!(cfg.default_firewall_profile, FirewallProfile::Private);
        assert_eq!(cfg.audit.max_size_bytes, 5_242_880);
        assert_eq!(cfg.audit.max_files, 3);
    }

    #[test]
    fn profile_deser_public() {
        // TOML requires key-value format, use serde_json for standalone enum test
        let profile: FirewallProfile = serde_json::from_str("\"public\"").unwrap();
        assert_eq!(profile, FirewallProfile::Public);
    }
}
