//! Configuration file parsing (TOML-based).
//!
//! Provides a generic configuration infrastructure with:
//! - TOML parsing with serde deserialization
//! - Typed configuration structures
//! - Validation with structured errors
//! - Clear distinction between missing, malformed, and invalid config
//! - Safe atomic-write for configuration persistence
//!
//! ## Security
//!
//! - No silent corruption — all writes are validated before commit
//! - Atomic writes prevent partial file corruption
//! - No destructive writes without explicit intent
//! - No arbitrary filesystem behavior
//!
//! ## Architecture
//!
//! This module implements only the generic core configuration infrastructure.
//! Service-specific and application-specific schemas belong to their respective
//! modules and are not defined here.

use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};

use serde::de::DeserializeOwned;
use serde::Serialize;

use crate::error::{Error, ErrorCode, Result};

/// Default configuration file name used across Mission OS components.
pub const CONFIG_FILE_NAME: &str = "mission.toml";

/// Default configuration directory permissions (rwxr-xr-x).
pub const CONFIG_DIR_PERMISSIONS: u32 = 0o755;

/// Default configuration file permissions (rw-r--r--).
pub const CONFIG_FILE_PERMISSIONS: u32 = 0o644;

/// A typed configuration value backed by a TOML source file.
///
/// `T` must implement both `Serialize` and `DeserializeOwned` (via serde).
///
/// # Examples
///
/// ```ignore
/// #[derive(Deserialize, Serialize)]
/// struct AppConfig {
///     theme: String,
///     language: String,
/// }
///
/// let cfg: Config<AppConfig> = Config::load_or_default(path)?;
/// ```
#[derive(Debug)]
pub struct Config<T> {
    /// The parsed configuration value.
    inner: T,
    /// Path to the configuration file on disk.
    path: PathBuf,
}

impl<T: DeserializeOwned> Config<T> {
    /// Load configuration from a TOML file.
    ///
    /// Returns `ConfigError` if:
    /// - The file exists but cannot be read
    /// - The file content is not valid TOML
    /// - The TOML does not match the expected schema
    pub fn load(path: impl AsRef<Path>) -> Result<Self> {
        let path = path.as_ref().to_path_buf();

        let contents = match fs::read_to_string(&path) {
            Ok(s) => s,
            Err(e) if e.kind() == io::ErrorKind::NotFound => {
                return Err(Error::new(
                    ErrorCode::NotFound,
                    format!("configuration file not found: {}", path.display()),
                ));
            }
            Err(e) => {
                return Err(Error::with_source(
                    ErrorCode::IoError,
                    format!("failed to read configuration file: {}", path.display()),
                    e,
                ));
            }
        };

        if contents.trim().is_empty() {
            return Err(Error::new(
                ErrorCode::ConfigError,
                format!("configuration file is empty: {}", path.display()),
            ));
        }

        let inner: T = toml::from_str(&contents).map_err(|e| {
            Error::with_source(
                ErrorCode::ConfigError,
                format!("malformed configuration in {}", path.display()),
                e,
            )
        })?;

        Ok(Self { inner, path })
    }

    /// Load configuration from a file, or return a default if the file
    /// does not exist. Other errors (malformed, permission denied) are
    /// still propagated.
    pub fn load_or_default(path: impl AsRef<Path>) -> Result<Self>
    where
        T: Default,
    {
        let path = path.as_ref().to_path_buf();

        match Self::load(&path) {
            Ok(cfg) => Ok(cfg),
            Err(e) if e.code() == ErrorCode::NotFound => Ok(Self {
                inner: T::default(),
                path,
            }),
            Err(e) => Err(e),
        }
    }

    /// Return a reference to the parsed configuration value.
    pub fn get(&self) -> &T {
        &self.inner
    }

    /// Return a mutable reference to the parsed configuration value.
    pub fn get_mut(&mut self) -> &mut T {
        &mut self.inner
    }

    /// Consume the config and return the inner value.
    pub fn into_inner(self) -> T {
        self.inner
    }

    /// Return the path to the configuration file.
    pub fn path(&self) -> &Path {
        &self.path
    }
}

impl<T: Serialize + DeserializeOwned> Config<T> {
    /// Save the configuration to disk using an atomic write.
    ///
    /// The file is first written to a temporary path, then atomically
    /// renamed to the target path. This prevents partial writes from
    /// power loss or disk-full conditions.
    ///
    /// ## Errors
    ///
    /// Returns `IoError` if the temporary file cannot be created or
    /// written. Returns `ConfigError` if serialization fails.
    pub fn save(&self) -> Result<()> {
        self.save_to(&self.path)
    }

    /// Save the configuration to a specific path using an atomic write.
    fn save_to(&self, path: &Path) -> Result<()> {
        // Serialize to TOML string
        let toml_string = toml::to_string_pretty(&self.inner).map_err(|e| {
            Error::with_source(
                ErrorCode::ConfigError,
                "failed to serialize configuration",
                e,
            )
        })?;

        // Ensure parent directory exists
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(|e| {
                Error::with_source(
                    ErrorCode::IoError,
                    format!("failed to create config directory: {}", parent.display()),
                    e,
                )
            })?;
        }

        // Atomic write: write to .tmp file, then rename
        let tmp_path = path.with_extension("toml.tmp");

        let mut tmp_file = fs::File::create(&tmp_path).map_err(|e| {
            Error::with_source(
                ErrorCode::IoError,
                format!(
                    "failed to create temporary config file: {}",
                    tmp_path.display()
                ),
                e,
            )
        })?;

        tmp_file.write_all(toml_string.as_bytes()).map_err(|e| {
            Error::with_source(ErrorCode::IoError, "failed to write configuration data", e)
        })?;

        tmp_file.sync_all().map_err(|e| {
            Error::with_source(ErrorCode::IoError, "failed to sync configuration file", e)
        })?;

        drop(tmp_file);

        fs::rename(&tmp_path, path).map_err(|e| {
            Error::with_source(
                ErrorCode::IoError,
                format!(
                    "failed to atomically rename config file: {} -> {}",
                    tmp_path.display(),
                    path.display()
                ),
                e,
            )
        })?;

        // Sync the containing directory to ensure the rename is durable
        if let Some(parent) = path.parent() {
            if let Ok(dir) = fs::File::open(parent) {
                let _ = dir.sync_all();
            }
        }

        Ok(())
    }
}

/// Parse a TOML string directly into a typed value.
///
/// Useful for testing and for config embedded in other formats.
pub fn from_str<T: DeserializeOwned>(toml_str: &str) -> Result<T> {
    toml::from_str(toml_str).map_err(|e| {
        Error::with_source(
            ErrorCode::ConfigError,
            "failed to parse TOML configuration",
            e,
        )
    })
}

/// Serialize a typed value to a TOML string.
pub fn to_string<T: Serialize>(value: &T) -> Result<String> {
    toml::to_string_pretty(value).map_err(|e| {
        Error::with_source(
            ErrorCode::ConfigError,
            "failed to serialize configuration",
            e,
        )
    })
}

// ---------------------------------------------------------------------------
// Default configuration structure for mission-core itself
// ---------------------------------------------------------------------------

/// Core configuration for mission-core behaviour.
///
/// This is the generic top-level config structure. Service-specific
/// and application-specific schemas extend from this.
#[derive(Debug, Clone, Default, Serialize, serde::Deserialize)]
pub struct CoreConfig {
    /// Logging configuration.
    #[serde(default)]
    pub logging: LoggingConfig,
    /// Paths configuration overrides.
    #[serde(default)]
    pub paths: PathsConfig,
}

/// Logging configuration.
#[derive(Debug, Clone, Serialize, serde::Deserialize)]
pub struct LoggingConfig {
    /// Minimum log level to emit.
    #[serde(default = "default_log_level")]
    pub level: String,
    /// Whether to include file/line information in log records.
    #[serde(default = "default_true")]
    pub include_location: bool,
}

impl Default for LoggingConfig {
    fn default() -> Self {
        Self {
            level: default_log_level(),
            include_location: default_true(),
        }
    }
}

fn default_log_level() -> String {
    "info".to_string()
}

fn default_true() -> bool {
    true
}

/// Paths configuration overrides.
#[derive(Debug, Clone, Default, Serialize, serde::Deserialize)]
pub struct PathsConfig {
    /// Override for the Mission OS root prefix.
    #[serde(default)]
    pub mission_root: Option<String>,
    /// Override for the configuration directory.
    #[serde(default)]
    pub config_dir: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde::Deserialize;

    #[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
    struct TestConfig {
        name: String,
        version: u32,
        enabled: bool,
    }

    impl Default for TestConfig {
        fn default() -> Self {
            Self {
                name: "default".into(),
                version: 1,
                enabled: false,
            }
        }
    }

    // -------------------------------------------------------------------
    // Valid TOML parsing
    // -------------------------------------------------------------------

    #[test]
    fn parse_valid_toml() {
        let toml_str = r#"
name = "test-app"
version = 42
enabled = true
"#;
        let cfg: TestConfig = from_str(toml_str).unwrap();
        assert_eq!(cfg.name, "test-app");
        assert_eq!(cfg.version, 42);
        assert!(cfg.enabled);
    }
    #[test]
    fn parse_toml_missing_required_field_fails() {
        let toml_str = r#"
name = "minimal"
version = 1
"#;
        let result: Result<TestConfig> = from_str(toml_str);
        assert!(result.is_err());
        assert_eq!(result.unwrap_err().code(), ErrorCode::ConfigError);
    }

    #[test]
    fn parse_toml_with_defaults_proper() {
        #[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
        struct OptConfig {
            name: String,
            #[serde(default)]
            flag: bool,
        }

        let toml_str = r#"name = "test""#;
        let cfg: OptConfig = from_str(toml_str).unwrap();
        assert_eq!(cfg.name, "test");
        assert!(!cfg.flag); // default for bool
    }

    // -------------------------------------------------------------------
    // Malformed TOML
    // -------------------------------------------------------------------

    #[test]
    fn parse_invalid_toml_fails() {
        let result: Result<TestConfig> = from_str("this is not toml ====");
        assert!(result.is_err());
        assert_eq!(result.unwrap_err().code(), ErrorCode::ConfigError);
    }

    #[test]
    fn parse_empty_toml_fails() {
        let result: Result<TestConfig> = from_str("");
        assert!(result.is_err());
    }

    #[test]
    fn parse_empty_string_with_whitespace() {
        let result: Result<TestConfig> = from_str("  \n  ");
        assert!(result.is_err());
    }

    // -------------------------------------------------------------------
    // Missing fields
    // -------------------------------------------------------------------

    #[test]
    fn parse_missing_required_field_fails() {
        let toml_str = r#"name = "only-name""#;
        let result: Result<TestConfig> = from_str(toml_str);
        assert!(result.is_err());
        assert_eq!(result.unwrap_err().code(), ErrorCode::ConfigError);
    }

    // -------------------------------------------------------------------
    // Invalid values
    // -------------------------------------------------------------------

    #[test]
    fn parse_invalid_type_fails() {
        let toml_str = r#"
name = "test"
version = "not-a-number"
enabled = true
"#;
        let result: Result<TestConfig> = from_str(toml_str);
        assert!(result.is_err());
    }

    // -------------------------------------------------------------------
    // CoreConfig defaults
    // -------------------------------------------------------------------

    #[test]
    fn core_config_default() {
        let cfg = CoreConfig::default();
        assert_eq!(cfg.logging.level, "info");
        assert!(cfg.logging.include_location);
        assert!(cfg.paths.mission_root.is_none());
    }

    #[test]
    fn core_config_from_toml() {
        let toml_str = r#"
[logging]
level = "debug"
include_location = false

[paths]
mission_root = "/custom/mission"
"#;
        let cfg: CoreConfig = from_str(toml_str).unwrap();
        assert_eq!(cfg.logging.level, "debug");
        assert!(!cfg.logging.include_location);
        assert_eq!(cfg.paths.mission_root.as_deref(), Some("/custom/mission"));
    }

    // -------------------------------------------------------------------
    // Round-trip
    // -------------------------------------------------------------------

    #[test]
    fn roundtrip_toml() {
        let cfg = TestConfig {
            name: "roundtrip".into(),
            version: 99,
            enabled: true,
        };

        let toml_str = to_string(&cfg).unwrap();
        let parsed: TestConfig = from_str(&toml_str).unwrap();
        assert_eq!(cfg, parsed);
    }

    #[test]
    fn roundtrip_core_config() {
        let cfg = CoreConfig::default();
        let toml_str = to_string(&cfg).unwrap();
        let parsed: CoreConfig = from_str(&toml_str).unwrap();
        assert_eq!(cfg.logging.level, parsed.logging.level);
    }

    // -------------------------------------------------------------------
    // File-based operations
    // -------------------------------------------------------------------

    #[test]
    fn load_nonexistent_file_fails() {
        let path = Path::new("/tmp/__mission_test_nonexistent_config.toml");
        // Clean up if it exists from a previous run
        let _ = fs::remove_file(path);
        let result: Result<Config<TestConfig>> = Config::load(path);
        assert!(result.is_err());
        assert_eq!(result.unwrap_err().code(), ErrorCode::NotFound);
    }

    #[test]
    fn load_or_default_nonexistent() {
        let path = Path::new("/tmp/__mission_test_nonexistent_default.toml");
        let _ = fs::remove_file(path);
        let cfg: Config<TestConfig> = Config::load_or_default(path).unwrap();
        assert_eq!(cfg.get().name, "default");
    }

    #[test]
    fn atomic_write_and_read() {
        let dir = std::env::temp_dir().join("__mission_config_test");
        let _ = fs::remove_dir_all(&dir);
        let path = dir.join("test_config.toml");

        let cfg = TestConfig {
            name: "atomic-test".into(),
            version: 7,
            enabled: true,
        };

        let config: Config<TestConfig> = Config {
            inner: cfg,
            path: path.clone(),
        };

        // Save
        config.save().unwrap();

        // Read back
        let loaded: Config<TestConfig> = Config::load(&path).unwrap();
        assert_eq!(loaded.get().name, "atomic-test");
        assert_eq!(loaded.get().version, 7);
        assert!(loaded.get().enabled);

        // Cleanup
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn load_malformed_file() {
        let dir = std::env::temp_dir().join("__mission_config_malformed");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("bad.toml");
        fs::write(&path, "[[[ invalid toml").unwrap();

        let result: Result<Config<TestConfig>> = Config::load(&path);
        assert!(result.is_err());
        assert_eq!(result.unwrap_err().code(), ErrorCode::ConfigError);

        let _ = fs::remove_dir_all(&dir);
    }
}
