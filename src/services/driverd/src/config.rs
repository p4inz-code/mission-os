//! Service configuration for mission-driverd.
//!
//! Provides typed configuration structures for the driver management service.
//! Configuration is loaded from TOML files via mission-core's config system.

use serde::{Deserialize, Serialize};

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

/// Inventory scan interval configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InventoryConfig {
    /// Interval in seconds between automatic hardware inventory scans.
    #[serde(default = "default_scan_interval")]
    pub scan_interval_secs: u64,
    /// Whether to enable automatic hardware detection on service start.
    #[serde(default = "default_auto_detect")]
    pub auto_detect_on_start: bool,
}

fn default_scan_interval() -> u64 {
    300
} // 5 minutes
fn default_auto_detect() -> bool {
    true
}

impl Default for InventoryConfig {
    fn default() -> Self {
        Self {
            scan_interval_secs: default_scan_interval(),
            auto_detect_on_start: default_auto_detect(),
        }
    }
}

/// Legacy driver source configuration (simple enabled-sources list).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LegacySourceConfig {
    /// List of enabled driver source IDs.
    #[serde(default)]
    pub enabled_sources: Vec<String>,
    /// Whether to allow third-party (unsigned) drivers in development mode.
    #[serde(default)]
    pub allow_unsigned_drivers: bool,
}

impl Default for LegacySourceConfig {
    fn default() -> Self {
        Self {
            enabled_sources: vec!["mission".into()],
            allow_unsigned_drivers: false,
        }
    }
}

/// Package store configuration for M2-D.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PackageStoreConfig {
    /// Path to the package staging directory.
    #[serde(default = "default_store_path")]
    pub store_path: String,
    /// Maximum allowed package size in bytes (default: 1 GB).
    #[serde(default = "default_max_package_size")]
    pub max_package_size_bytes: u64,
}

fn default_store_path() -> String {
    "/var/cache/mission/driverd/packages".into()
}
fn default_max_package_size() -> u64 {
    1_000_000_000
}

impl Default for PackageStoreConfig {
    fn default() -> Self {
        Self {
            store_path: default_store_path(),
            max_package_size_bytes: default_max_package_size(),
        }
    }
}

/// Signature verification configuration for M2-D.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VerificationConfig {
    /// Path to the trusted key store directory.
    #[serde(default = "default_key_store_path")]
    pub key_store_path: String,
    /// Whether signature verification is required.
    #[serde(default = "default_require_signature")]
    pub require_signature: bool,
    /// Whether to allow unsigned drivers (development mode).
    #[serde(default)]
    pub allow_unsigned: bool,
}

fn default_key_store_path() -> String {
    "/etc/mission/driverd/trusted-keys".into()
}
fn default_require_signature() -> bool {
    true
}

impl Default for VerificationConfig {
    fn default() -> Self {
        Self {
            key_store_path: default_key_store_path(),
            require_signature: default_require_signature(),
            allow_unsigned: false,
        }
    }
}

/// Driver management service configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DriverConfig {
    /// The D-Bus well-known name for this service.
    #[serde(default = "default_dbus_name")]
    pub dbus_name: String,
    /// Audit logging configuration.
    #[serde(default)]
    pub audit: AuditConfig,
    /// Inventory scan configuration.
    #[serde(default)]
    pub inventory: InventoryConfig,
    /// Legacy simple source configuration.
    #[serde(default)]
    pub legacy_sources: LegacySourceConfig,
    /// Package store configuration (M2-D).
    #[serde(default)]
    pub package_store: PackageStoreConfig,
    /// Signature verification configuration (M2-D).
    #[serde(default)]
    pub verification: VerificationConfig,
}

fn default_dbus_name() -> String {
    "org.mission.Driver1".into()
}

impl Default for DriverConfig {
    fn default() -> Self {
        Self {
            dbus_name: default_dbus_name(),
            audit: AuditConfig::default(),
            inventory: InventoryConfig::default(),
            legacy_sources: LegacySourceConfig::default(),
            package_store: PackageStoreConfig::default(),
            verification: VerificationConfig::default(),
        }
    }
}

/// Load the driver service configuration from a TOML file.
///
/// Falls back to defaults if the file does not exist.
pub fn load_config(path: &std::path::Path) -> DriverConfig {
    match std::fs::read_to_string(path) {
        Ok(content) => match toml::from_str(&content) {
            Ok(cfg) => cfg,
            Err(e) => {
                eprintln!("[driverd] config parse error: {e}, using defaults");
                DriverConfig::default()
            }
        },
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            eprintln!("[driverd] config not found at {path:?}, using defaults");
            DriverConfig::default()
        }
        Err(e) => {
            eprintln!("[driverd] cannot read config {path:?}: {e}, using defaults");
            DriverConfig::default()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn config_default() {
        let cfg = DriverConfig::default();
        assert_eq!(cfg.dbus_name, "org.mission.Driver1");
        assert!(cfg.audit.enabled);
        assert!(cfg.inventory.auto_detect_on_start);
        assert_eq!(cfg.inventory.scan_interval_secs, 300);
        assert!(!cfg.legacy_sources.allow_unsigned_drivers);
        assert_eq!(cfg.legacy_sources.enabled_sources, vec!["mission"]);
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
        let cfg = DriverConfig::default();
        let toml_str = toml::to_string(&cfg).unwrap();
        let parsed: DriverConfig = toml::from_str(&toml_str).unwrap();
        assert_eq!(parsed.dbus_name, cfg.dbus_name);
    }

    #[test]
    fn config_parse_valid_toml() {
        let toml_str = r#"
dbus_name = "org.mission.Driver1"

[audit]
enabled = true
max_size_bytes = 5242880
max_files = 3
syslog_forward = false

[inventory]
scan_interval_secs = 600
auto_detect_on_start = false

[legacy_sources]
enabled_sources = ["mission", "vendor"]
allow_unsigned_drivers = false
"#;
        let cfg: DriverConfig = toml::from_str(toml_str).unwrap();
        assert_eq!(cfg.inventory.scan_interval_secs, 600);
        assert!(!cfg.inventory.auto_detect_on_start);
        assert_eq!(cfg.legacy_sources.enabled_sources.len(), 2);
        assert!(!cfg.legacy_sources.allow_unsigned_drivers);
    }

    #[test]
    fn inventory_default_values() {
        let inv = InventoryConfig::default();
        assert!(inv.auto_detect_on_start);
        assert_eq!(inv.scan_interval_secs, 300);
    }

    #[test]
    fn legacy_source_default_values() {
        let src = LegacySourceConfig::default();
        assert!(!src.allow_unsigned_drivers);
        assert!(src.enabled_sources.contains(&"mission".to_string()));
    }
}
