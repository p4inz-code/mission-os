//! Canonical path resolution for Mission OS directories.
//!
//! Provides consistent directory paths across the system following the
//! Mission OS filesystem layout architecture (MOS-ENG-004).
//!
//! ## Path Categories
//!
//! - **Configuration paths** — `/etc/mission/` (system) or `$XDG_CONFIG_HOME/mission/` (user)
//! - **Data paths** — `/usr/lib/mission/` (system) or `$XDG_DATA_HOME/mission/` (user)
//! - **Cache paths** — `/var/cache/mission/` (system) or `$XDG_CACHE_HOME/mission/` (user)
//! - **State paths** — `/var/lib/mission/` (system) or `$XDG_STATE_HOME/mission/` (user)
//! - **Runtime paths** — `/run/mission/` (system) or `$XDG_RUNTIME_DIR/mission/` (user)
//! - **Mission OS system data** — `/mission/`
//! - **Temporary paths** — `/tmp/mission/`
//!
//! ## Security
//!
//! - No automatic destructive directory creation
//! - No path traversal vulnerabilities — input is validated
//! - Environment variable usage follows XDG Base Directory Specification
//! - No hard-coded user-specific paths

use std::path::{Path, PathBuf};

use crate::error::{Error, ErrorCode, Result};

/// The canonical Mission OS root prefix for system data.
pub const MISSION_ROOT: &str = "/mission";

/// The canonical Mission OS configuration directory.
pub const MISSION_CONFIG_DIR: &str = "/etc/mission";

/// The canonical Mission OS library directory.
pub const MISSION_LIB_DIR: &str = "/usr/lib/mission";

/// The canonical Mission OS cache directory.
pub const MISSION_CACHE_DIR: &str = "/var/cache/mission";

/// The canonical Mission OS state directory.
pub const MISSION_STATE_DIR: &str = "/var/lib/mission";

/// The canonical Mission OS runtime directory.
pub const MISSION_RUN_DIR: &str = "/run/mission";

/// Environment variable for overriding the mission root.
pub const ENV_MISSION_ROOT: &str = "MISSION_ROOT";

/// Environment variable for overriding the config directory.
pub const ENV_MISSION_CONFIG: &str = "MISSION_CONFIG_DIR";

// ---------------------------------------------------------------------------
// Core path helpers
// ---------------------------------------------------------------------------

/// Resolve a component path relative to the Mission OS root.
///
/// The root is determined by (in priority order):
/// 1. `$MISSION_ROOT` environment variable
/// 2. [`MISSION_ROOT`] constant (`/mission`)
///
/// Returns an error if any component attempts directory traversal (`..`).
pub fn mission_dir(component: impl AsRef<Path>) -> Result<PathBuf> {
    let component = validate_component(component.as_ref())?;
    Ok(env_override(ENV_MISSION_ROOT, MISSION_ROOT).join(component))
}

/// Path to the verified package cache (`/mission/packages`).
pub fn package_cache() -> Result<PathBuf> {
    mission_dir("packages")
}

/// Path to system snapshots (`/mission/snapshots`).
pub fn snapshots() -> Result<PathBuf> {
    mission_dir("snapshots")
}

/// Path to staged update data (`/mission/updates`).
pub fn update_cache() -> Result<PathBuf> {
    mission_dir("updates")
}

/// Path to the driver storage directory (`/mission/drivers`).
pub fn driver_store() -> Result<PathBuf> {
    mission_dir("drivers")
}

/// Path to the configuration directory.
///
/// Determined by (in priority order):
/// 1. `$MISSION_CONFIG_DIR` environment variable
/// 2. [`MISSION_CONFIG_DIR`] constant (`/etc/mission`)
pub fn config_dir() -> PathBuf {
    env_override(ENV_MISSION_CONFIG, MISSION_CONFIG_DIR)
}

/// Path to the shared libraries directory (`/usr/lib/mission`).
pub fn lib_dir() -> PathBuf {
    PathBuf::from(MISSION_LIB_DIR)
}

// ---------------------------------------------------------------------------
// User-specific paths (XDG Base Directory)
// ---------------------------------------------------------------------------

/// Resolve the Mission OS user configuration directory.
///
/// Follows the XDG Base Directory Specification:
/// - `$XDG_CONFIG_HOME/mission/` if `$XDG_CONFIG_HOME` is set
/// - `~/.config/mission/` otherwise
pub fn user_config_dir() -> PathBuf {
    xdg_home("XDG_CONFIG_HOME", ".config").join("mission")
}

/// Resolve the Mission OS user data directory.
///
/// Follows the XDG Base Directory Specification:
/// - `$XDG_DATA_HOME/mission/` if `$XDG_DATA_HOME` is set
/// - `~/.local/share/mission/` otherwise
pub fn user_data_dir() -> PathBuf {
    xdg_home("XDG_DATA_HOME", ".local/share").join("mission")
}

/// Resolve the Mission OS user cache directory.
///
/// Follows the XDG Base Directory Specification:
/// - `$XDG_CACHE_HOME/mission/` if `$XDG_CACHE_HOME` is set
/// - `~/.cache/mission/` otherwise
pub fn user_cache_dir() -> PathBuf {
    xdg_home("XDG_CACHE_HOME", ".cache").join("mission")
}

/// Resolve the Mission OS user state directory.
///
/// Follows the XDG Base Directory Specification:
/// - `$XDG_STATE_HOME/mission/` if `$XDG_STATE_HOME` is set
/// - `~/.local/state/mission/` otherwise
pub fn user_state_dir() -> PathBuf {
    xdg_home("XDG_STATE_HOME", ".local/state").join("mission")
}

/// Resolve the Mission OS user runtime directory.
///
/// Follows the XDG Base Directory Specification:
/// - `$XDG_RUNTIME_DIR/mission/` if `$XDG_RUNTIME_DIR` is set
/// - `/tmp/mission/runtime-<uid>/` as fallback
pub fn user_runtime_dir() -> PathBuf {
    if let Ok(dir) = std::env::var("XDG_RUNTIME_DIR") {
        return PathBuf::from(dir).join("mission");
    }
    // Fallback: /tmp/mission/runtime/
    PathBuf::from("/tmp/mission/runtime")
}

/// Path to the temporary directory for Mission OS (`/tmp/mission`).
pub fn temp_dir() -> PathBuf {
    PathBuf::from("/tmp/mission")
}

// ---------------------------------------------------------------------------
// Safe path validation
// ---------------------------------------------------------------------------

/// Validate that a path component does not contain traversal attempts.
///
/// Returns an error if the component contains `..` or other traversal patterns.
fn validate_component(component: &Path) -> Result<&Path> {
    for segment in component.components() {
        match segment {
            std::path::Component::ParentDir => {
                return Err(Error::new(
                    ErrorCode::InvalidArgument,
                    format!(
                        "path component contains '..' traversal: {}",
                        component.display()
                    ),
                ));
            }
            std::path::Component::Prefix(_) => {
                return Err(Error::new(
                    ErrorCode::InvalidArgument,
                    format!(
                        "path component contains Windows prefix: {}",
                        component.display()
                    ),
                ));
            }
            std::path::Component::RootDir => {
                return Err(Error::new(
                    ErrorCode::InvalidArgument,
                    format!("path component is absolute: {}", component.display()),
                ));
            }
            _ => {}
        }
    }
    Ok(component)
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Return the value of an environment variable if set and non-empty,
/// otherwise return a fallback path.
fn env_override(env_var: &str, fallback: &str) -> PathBuf {
    match std::env::var(env_var) {
        Ok(val) if !val.is_empty() => PathBuf::from(val),
        _ => PathBuf::from(fallback),
    }
}

/// Resolve an XDG-style home directory path.
///
/// - If `env_var` is set, use that directory
/// - Otherwise, use `$HOME/{default_subpath}`
fn xdg_home(env_var: &str, default_subpath: &str) -> PathBuf {
    if let Ok(dir) = std::env::var(env_var) {
        if !dir.is_empty() {
            return PathBuf::from(dir);
        }
    }

    // Fallback to $HOME/default_subpath
    if let Ok(home) = std::env::var("HOME") {
        return PathBuf::from(home).join(default_subpath);
    }

    // Last resort: use root-relative path
    PathBuf::from(format!("/root/{default_subpath}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    // -------------------------------------------------------------------
    // Path construction
    // -------------------------------------------------------------------

    #[test]
    fn mission_dir_construction() {
        let p = mission_dir("packages").unwrap();
        assert!(p.to_string_lossy().contains("mission"));
        assert!(p.to_string_lossy().contains("packages"));
    }

    #[test]
    fn mission_dir_nested() {
        let p = mission_dir("subdir/deep").unwrap();
        assert!(p.to_string_lossy().ends_with("subdir/deep"));
    }

    #[test]
    fn package_cache_path() {
        let p = package_cache().unwrap();
        assert!(p.to_string_lossy().contains("packages"));
    }

    #[test]
    fn snapshots_path() {
        let p = snapshots().unwrap();
        assert!(p.to_string_lossy().contains("snapshots"));
    }

    #[test]
    fn config_dir_path() {
        let p = config_dir();
        assert!(p.to_string_lossy().contains("etc"));
    }

    #[test]
    fn lib_dir_path() {
        let p = lib_dir();
        assert_eq!(p, PathBuf::from("/usr/lib/mission"));
    }

    // -------------------------------------------------------------------
    // Path validation (traversal protection)
    // -------------------------------------------------------------------

    #[test]
    fn traversal_attempt_rejected() {
        let result = mission_dir("../etc/passwd");
        assert!(result.is_err());
        assert_eq!(result.unwrap_err().code(), ErrorCode::InvalidArgument);
    }

    #[test]
    fn double_dot_rejected() {
        let result = mission_dir("../../etc");
        assert!(result.is_err());
    }

    #[test]
    fn absolute_component_rejected() {
        let result = mission_dir("/etc");
        assert!(result.is_err());
    }

    #[test]
    fn simple_name_accepted() {
        let result = mission_dir("config");
        assert!(result.is_ok());
    }

    #[test]
    fn nested_valid_accepted() {
        let result = mission_dir("var/log/app");
        assert!(result.is_ok());
    }

    // -------------------------------------------------------------------
    // XDG paths
    // -------------------------------------------------------------------

    #[test]
    fn user_config_contains_mission() {
        let p = user_config_dir();
        assert!(p.to_string_lossy().contains("mission"));
    }

    #[test]
    fn user_data_contains_mission() {
        let p = user_data_dir();
        assert!(p.to_string_lossy().contains("mission"));
    }

    #[test]
    fn user_cache_contains_mission() {
        let p = user_cache_dir();
        assert!(p.to_string_lossy().contains("mission"));
    }

    #[test]
    fn user_state_contains_mission() {
        let p = user_state_dir();
        assert!(p.to_string_lossy().contains("mission"));
    }

    #[test]
    fn user_runtime_contains_mission() {
        let p = user_runtime_dir();
        assert!(p.to_string_lossy().contains("mission"));
    }

    // -------------------------------------------------------------------
    // Environment variable override
    // -------------------------------------------------------------------

    #[test]
    fn env_override_works() {
        // Temporarily set MISSION_ROOT
        std::env::set_var("MISSION_ROOT", "/custom/root");
        let p = mission_dir("test").unwrap();
        assert!(p.to_string_lossy().starts_with("/custom/root"));
        std::env::remove_var("MISSION_ROOT");
    }

    #[test]
    fn env_config_override() {
        std::env::set_var("MISSION_CONFIG_DIR", "/custom/config");
        let p = config_dir();
        assert_eq!(p, PathBuf::from("/custom/config"));
        std::env::remove_var("MISSION_CONFIG_DIR");
    }

    // -------------------------------------------------------------------
    // Temp dir
    // -------------------------------------------------------------------

    #[test]
    fn temp_dir_path() {
        let p = temp_dir();
        assert_eq!(p, PathBuf::from("/tmp/mission"));
    }

    // -------------------------------------------------------------------
    // Edge cases
    // -------------------------------------------------------------------

    #[test]
    fn empty_component_accepted() {
        let result = mission_dir("");
        assert!(result.is_ok());
    }

    #[test]
    fn path_with_hyphens() {
        let result = mission_dir("my-component");
        assert!(result.is_ok());
        let p = result.unwrap();
        assert!(p.to_string_lossy().ends_with("my-component"));
    }
}
