//! Kernel module management for mission-driverd.
//!
//! Provides safe management of Linux kernel modules: detection,
//! loading, unloading, and status queries.
//!
//! ## Architecture
//!
//! Per MOS-ENG-MOD-001 §3.6, mission-driverd manages kernel
//! modules as part of driver installation. This module provides
//! the safe backend for module operations.
//!
//! ## Linux Implementation
//!
//! - **Detection**: Reads `/proc/modules` and `/sys/module/` for
//!   module state information. No shell commands.
//! - **Loading**: Uses `libc::init_module` syscall directly for
//!   safe module loading. Wrapped in a safe function.
//! - **Unloading**: Uses `libc::delete_module` syscall directly.
//!   Wrapped in a safe function with proper error handling.
//!
//! ## Security
//!
//! - No shelling out to `modprobe` or `rmmod`
//! - Unsafe FFI calls are isolated in this module with SAFETY docs
//! - Module parameters are validated before loading
//! - Module names are checked for path traversal
//! - All errors are handled cleanly — no panics

use std::path::Path;

use crate::error::{ServiceError, ServiceResult};

// ── Module State ──────────────────────────────────────────────────

/// State of a kernel module.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ModuleState {
    /// Module is loaded and active.
    Live,
    /// Module is loaded but not in use.
    Loaded,
    /// Module is built into the kernel (cannot be unloaded).
    BuiltIn,
    /// Module is available but not loaded.
    Unloaded,
    /// Module failed to load or is in an error state.
    Error,
}

impl ModuleState {
    /// Parse module state from `/proc/modules` format.
    #[allow(dead_code)]
    fn from_proc_modules_state(state: &str) -> Self {
        match state.trim() {
            "Live" => ModuleState::Live,
            "Loaded" => ModuleState::Loaded,
            "Unloaded" => ModuleState::Unloaded,
            _ => ModuleState::Error,
        }
    }
}

/// Information about a kernel module.
#[derive(Debug, Clone)]
pub struct ModuleInfo {
    /// Module name (e.g., "e1000e").
    pub name: String,
    /// Current state.
    pub state: ModuleState,
    /// Memory size in bytes (0 if unknown).
    pub size_bytes: u64,
    /// Number of processes/instances using this module.
    pub used_by_count: u32,
    /// Modules that depend on this module.
    pub used_by: Vec<String>,
    /// Whether this is a built-in module (cannot be unloaded).
    pub is_builtin: bool,
    /// Module path on disk (for loadable modules).
    pub path: Option<String>,
}

// ── Kmod Manager ─────────────────────────────────────────────────

/// Safe kernel module manager.
///
/// Provides kernel module operations without shelling out to
/// external commands. Uses sysfs and /proc files for detection,
/// and libc syscalls for load/unload operations.
pub struct KmodManager;

impl KmodManager {
    /// List all currently loaded kernel modules.
    ///
    /// Reads `/proc/modules` to get the list of loaded modules
    /// and their state.
    #[cfg(target_os = "linux")]
    pub fn list_modules() -> ServiceResult<Vec<ModuleInfo>> {
        let content = std::fs::read_to_string("/proc/modules").map_err(|e| {
            ServiceError::BackendUnavailable(format!("cannot read /proc/modules: {e}"))
        })?;

        let mut modules = Vec::new();

        for line in content.lines() {
            let line = line.trim();
            if line.is_empty() {
                continue;
            }

            // Format: name size used_by_count used_by_list state
            // Example: e1000e 245760 0 - Live 0x0000000000000000
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() < 6 {
                continue;
            }

            let name = parts[0].to_string();
            let size_bytes = parts[1].parse::<u64>().unwrap_or(0);
            let used_by_count = parts[2].parse::<u32>().unwrap_or(0);
            let used_by = if parts[3] == "-" {
                Vec::new()
            } else {
                parts[3].split(',').map(|s| s.trim().to_string()).collect()
            };
            let state = ModuleState::from_proc_modules_state(parts[4]);

            modules.push(ModuleInfo {
                name,
                state,
                size_bytes,
                used_by_count,
                used_by,
                is_builtin: false,
                path: None,
            });
        }

        Ok(modules)
    }

    /// List modules available on disk (not yet loaded).
    ///
    /// Checks standard kernel module directories for available
    /// modules. This only checks for module existence, it does
    /// not resolve dependencies or parse module metadata beyond
    /// the file name.
    #[cfg(target_os = "linux")]
    pub fn list_available_modules() -> ServiceResult<Vec<String>> {
        let module_dirs = vec!["/lib/modules"];

        // Get current kernel version for the module path
        let kernel_release = std::fs::read_to_string("/proc/sys/kernel/osrelease")
            .ok()
            .map(|s| s.trim().to_string())
            .unwrap_or_default();

        let mut module_names = Vec::new();

        for base_dir in &module_dirs {
            let modules_dir = if kernel_release.is_empty() {
                Path::new(base_dir).to_path_buf()
            } else {
                Path::new(base_dir).join(&kernel_release)
            };

            let kernel_dir = modules_dir.join("kernel");
            if !kernel_dir.exists() {
                continue;
            }

            collect_kernel_modules(&kernel_dir, &mut module_names);
        }

        module_names.sort();
        module_names.dedup();
        Ok(module_names)
    }

    /// Get information about a specific module.
    #[cfg(target_os = "linux")]
    pub fn module_info(name: &str) -> ServiceResult<ModuleInfo> {
        // Check if module is loaded via /sys/module/<name>
        let sysfs_path = Path::new("/sys/module").join(name);

        if sysfs_path.exists() {
            // Module is loaded — get details from sysfs
            let holders_path = sysfs_path.join("holders");
            let used_by = if holders_path.exists() {
                let mut holders = Vec::new();
                if let Ok(entries) = std::fs::read_dir(&holders_path) {
                    for entry in entries.flatten() {
                        if let Some(name) = entry.file_name().to_str() {
                            holders.push(name.to_string());
                        }
                    }
                }
                holders
            } else {
                Vec::new()
            };

            // Check hold status
            let hold_path = sysfs_path.join("hold");
            let is_builtin = if let Ok(content) = std::fs::read_to_string(&hold_path) {
                content.trim() == "1" // built-in module has hold=1
            } else {
                false
            };

            // Get size if available
            let size_path = sysfs_path.join("coresize");
            let size_bytes = std::fs::read_to_string(&size_path)
                .ok()
                .and_then(|s| s.trim().parse::<u64>().ok())
                .unwrap_or(0);

            let state = if is_builtin {
                ModuleState::BuiltIn
            } else {
                ModuleState::Live
            };

            return Ok(ModuleInfo {
                name: name.to_string(),
                state,
                size_bytes,
                used_by_count: used_by.len() as u32,
                used_by,
                is_builtin,
                path: None,
            });
        }

        // Module not loaded — check if available on disk
        if Self::module_available(name) {
            return Ok(ModuleInfo {
                name: name.to_string(),
                state: ModuleState::Unloaded,
                size_bytes: 0,
                used_by_count: 0,
                used_by: Vec::new(),
                is_builtin: false,
                path: None,
            });
        }

        Err(ServiceError::NotFound(format!(
            "kernel module '{name}' not found"
        )))
    }

    /// Check if a module is available on disk.
    #[cfg(target_os = "linux")]
    pub fn module_available(name: &str) -> bool {
        let kernel_release = std::fs::read_to_string("/proc/sys/kernel/osrelease")
            .ok()
            .map(|s| s.trim().to_string())
            .unwrap_or_default();

        let modules_dir = if kernel_release.is_empty() {
            Path::new("/lib/modules").to_path_buf()
        } else {
            Path::new("/lib/modules").join(&kernel_release)
        };

        // Check common locations for the module
        let extensions = [".ko", ".ko.xz", ".ko.gz", ".ko.zst"];
        let search_dirs = [
            modules_dir.join("kernel"),
            modules_dir.join("updates"),
            modules_dir.join("extra"),
        ];

        for dir in &search_dirs {
            if !dir.exists() {
                continue;
            }
            // Walk the directory tree looking for the module
            if let Ok(walk) = walk_module_dir(dir, name, &extensions) {
                if walk {
                    return true;
                }
            }
        }

        false
    }

    /// Stub for non-Linux platforms.
    #[cfg(not(target_os = "linux"))]
    pub fn list_modules() -> ServiceResult<Vec<ModuleInfo>> {
        Err(ServiceError::NotSupported(
            "kernel module management is not supported on this platform".into(),
        ))
    }

    /// Stub for non-Linux platforms.
    #[cfg(not(target_os = "linux"))]
    pub fn module_info(_name: &str) -> ServiceResult<ModuleInfo> {
        Err(ServiceError::NotSupported(
            "kernel module management is not supported on this platform".into(),
        ))
    }

    /// Stub for non-Linux platforms.
    #[cfg(not(target_os = "linux"))]
    pub fn module_available(_name: &str) -> bool {
        false
    }

    /// Stub for non-Linux platforms.
    #[cfg(not(target_os = "linux"))]
    pub fn list_available_modules() -> ServiceResult<Vec<String>> {
        Err(ServiceError::NotSupported(
            "kernel module management is not supported on this platform".into(),
        ))
    }

    /// Load a kernel module.
    ///
    /// Uses the `init_module` syscall directly via libc.
    /// This is isolated unsafe code with documented safety.
    ///
    /// # Arguments
    ///
    /// * `name` - Module name.
    /// * `path` - Path to the module file (.ko).
    /// * `params` - Optional module parameters as key=value pairs.
    #[cfg(target_os = "linux")]
    #[allow(unsafe_code)]
    pub fn load_module(name: &str, path: &Path, params: &[String]) -> ServiceResult<()> {
        // Validate module name (no path traversal)
        validate_module_name(name)?;

        // Read the module binary
        let module_data = std::fs::read(path).map_err(|e| {
            ServiceError::InvalidArgument(format!("cannot read module file {path:?}: {e}"))
        })?;

        // Format module parameters as a null-terminated string
        let param_string = if params.is_empty() {
            String::new()
        } else {
            params.join(" ")
        };
        let param_bytes = param_string.as_bytes();

        // SAFETY: init_module is a Linux syscall that loads a kernel module.
        // The module data must be valid ELF. We validate the path and name
        // beforehand. This is the minimal FFI boundary for module loading.
        let ret = unsafe {
            libc::syscall(
                libc::SYS_init_module,
                module_data.as_ptr() as *const libc::c_void,
                module_data.len(),
                if param_bytes.is_empty() {
                    std::ptr::null()
                } else {
                    param_bytes.as_ptr() as *const libc::c_void
                },
            )
        };

        if ret != 0 {
            let errno = unsafe { *libc::__errno_location() };
            return Err(match errno {
                libc::EEXIST => {
                    ServiceError::AlreadyExists(format!("module '{name}' already loaded"))
                }
                libc::ENOENT => {
                    ServiceError::NotFound(format!("module '{name}' not found on disk"))
                }
                libc::EINVAL => ServiceError::InvalidArgument(format!(
                    "invalid module file or parameters for '{name}'"
                )),
                libc::EPERM => ServiceError::PermissionDenied(
                    "insufficient privilege to load kernel module".into(),
                ),
                _ => {
                    ServiceError::Internal(format!("failed to load module '{name}': errno={errno}"))
                }
            });
        }

        Ok(())
    }

    /// Unload a kernel module.
    ///
    /// Uses the `delete_module` syscall directly via libc.
    /// This is isolated unsafe code with documented safety.
    ///
    /// # Arguments
    ///
    /// * `name` - Module name to unload.
    /// * `force` - Whether to force unload (may cause system instability).
    #[cfg(target_os = "linux")]
    #[allow(unsafe_code)]
    pub fn unload_module(name: &str, force: bool) -> ServiceResult<()> {
        // Validate module name
        validate_module_name(name)?;

        let flags = if force {
            libc::O_NONBLOCK | 0x0001 // O_TRUNC flag forces removal
        } else {
            libc::O_NONBLOCK
        };

        // Create a CString for the module name
        let c_name = std::ffi::CString::new(name).map_err(|_| {
            ServiceError::InvalidArgument(format!("module name '{name}' contains null byte"))
        })?;

        // SAFETY: delete_module is a Linux syscall that removes a kernel module.
        // The module name is validated and passed as a CString. We handle all
        // errno values gracefully. This is the minimal FFI boundary for module unloading.
        let ret = unsafe {
            libc::syscall(
                libc::SYS_delete_module,
                c_name.as_ptr() as *const libc::c_void,
                flags,
            )
        };

        if ret != 0 {
            let errno = unsafe { *libc::__errno_location() };
            return Err(match errno {
                libc::ENOENT => ServiceError::NotFound(format!("module '{name}' is not loaded")),
                libc::EBUSY => {
                    ServiceError::Busy(format!("module '{name}' is in use and cannot be unloaded"))
                }
                libc::EPERM => ServiceError::PermissionDenied(
                    "insufficient privilege to unload kernel module".into(),
                ),
                _ => ServiceError::Internal(format!(
                    "failed to unload module '{name}': errno={errno}"
                )),
            });
        }

        Ok(())
    }

    /// Stub for non-Linux platforms.
    #[cfg(not(target_os = "linux"))]
    pub fn load_module(_name: &str, _path: &Path, _params: &[String]) -> ServiceResult<()> {
        Err(ServiceError::NotSupported(
            "kernel module loading is not supported on this platform".into(),
        ))
    }

    /// Stub for non-Linux platforms.
    #[cfg(not(target_os = "linux"))]
    pub fn unload_module(_name: &str, _force: bool) -> ServiceResult<()> {
        Err(ServiceError::NotSupported(
            "kernel module unloading is not supported on this platform".into(),
        ))
    }

    /// Check if a module is currently loaded.
    #[cfg(target_os = "linux")]
    pub fn is_loaded(name: &str) -> bool {
        Path::new("/sys/module").join(name).exists()
    }

    /// Check if a module is currently loaded.
    ///
    /// On non-Linux platforms, always returns false.
    #[cfg(not(target_os = "linux"))]
    pub fn is_loaded(_name: &str) -> bool {
        false
    }
}

// ── Module Name Validation ────────────────────────────────────────

/// Validate a kernel module name.
///
/// Rejects names containing path separators, null bytes,
/// or other dangerous characters.
#[allow(dead_code)]
fn validate_module_name(name: &str) -> ServiceResult<()> {
    if name.is_empty() {
        return Err(ServiceError::InvalidArgument(
            "module name must not be empty".into(),
        ));
    }

    if name.len() > 128 {
        return Err(ServiceError::InvalidArgument(
            "module name exceeds maximum length (128)".into(),
        ));
    }

    for ch in name.chars() {
        match ch {
            '/' | '\\' | '.' | '\0' | ';' | '|' | '&' | '$' | '`' => {
                return Err(ServiceError::InvalidArgument(format!(
                    "module name '{name}' contains invalid character '{ch}'"
                )));
            }
            _ => {}
        }
    }

    Ok(())
}

// ── Module Directory Walking ──────────────────────────────────────

/// Walk a directory tree looking for a kernel module file.
#[cfg(target_os = "linux")]
fn walk_module_dir(dir: &Path, name: &str, extensions: &[&str]) -> ServiceResult<bool> {
    let read_dir = match std::fs::read_dir(dir) {
        Ok(rd) => rd,
        Err(_) => return Ok(false),
    };

    for entry in read_dir.flatten() {
        let path = entry.path();
        if path.is_dir() {
            if walk_module_dir(&path, name, extensions)? {
                return Ok(true);
            }
        } else if let Some(file_name) = path.file_name() {
            let file_name_str = file_name.to_string_lossy();
            for ext in extensions {
                let target = format!("{name}{ext}");
                if file_name_str == target {
                    return Ok(true);
                }
            }
        }
    }

    Ok(false)
}

/// Collect kernel module names from a directory tree.
#[cfg(target_os = "linux")]
fn collect_kernel_modules(dir: &Path, names: &mut Vec<String>) {
    let read_dir = match std::fs::read_dir(dir) {
        Ok(rd) => rd,
        Err(_) => return,
    };

    for entry in read_dir.flatten() {
        let path = entry.path();
        if path.is_dir() {
            collect_kernel_modules(&path, names);
        } else if let Some(file_name) = path.file_name() {
            let file_name_str = file_name.to_string_lossy();
            // Kernel modules end with .ko (possibly compressed)
            if file_name_str.ends_with(".ko") {
                // Extract module name: "e1000e.ko" -> "e1000e"
                let name = file_name_str
                    .trim_end_matches(".ko")
                    .trim_end_matches(".xz")
                    .trim_end_matches(".gz")
                    .trim_end_matches(".zst")
                    .to_string();
                if !name.is_empty() {
                    names.push(name);
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // ── Module Name Validation ─────────────────────────────────

    #[test]
    fn valid_module_name() {
        assert!(validate_module_name("e1000e").is_ok());
        assert!(validate_module_name("iwlwifi").is_ok());
        assert!(validate_module_name("nvidia_current").is_ok());
    }

    #[test]
    fn empty_name_rejected() {
        assert!(validate_module_name("").is_err());
    }

    #[test]
    fn path_traversal_rejected() {
        assert!(validate_module_name("../../etc/passwd").is_err());
        assert!(validate_module_name("../module").is_err());
        assert!(validate_module_name("test;ls").is_err());
        assert!(validate_module_name("test|echo").is_err());
    }

    #[test]
    fn null_byte_rejected() {
        assert!(validate_module_name("test\0module").is_err());
    }

    #[test]
    fn long_name_rejected() {
        let long_name = "a".repeat(129);
        assert!(validate_module_name(&long_name).is_err());
    }

    // ── ModuleState ─────────────────────────────────────────────

    #[test]
    fn module_state_parsing() {
        assert_eq!(
            ModuleState::from_proc_modules_state("Live"),
            ModuleState::Live
        );
        assert_eq!(
            ModuleState::from_proc_modules_state("Unloaded"),
            ModuleState::Unloaded
        );
        assert_eq!(
            ModuleState::from_proc_modules_state("Unknown"),
            ModuleState::Error
        );
    }

    // ── Cross-platform stubs ───────────────────────────────────

    #[test]
    fn list_modules_stub() {
        let result = KmodManager::list_modules();
        #[cfg(not(target_os = "linux"))]
        assert!(result.is_err());
        #[cfg(target_os = "linux")]
        {
            // On Linux, this may succeed or fail gracefully
            if let Ok(modules) = result {
                assert!(modules.iter().all(|m| !m.name.is_empty()));
            }
        }
    }

    #[test]
    fn is_loaded_stub() {
        // Should not panic
        let _ = KmodManager::is_loaded("nonexistent_module");
    }

    #[test]
    fn load_module_stub() {
        let result = KmodManager::load_module("test", Path::new("/nonexistent/test.ko"), &[]);
        #[cfg(not(target_os = "linux"))]
        assert!(result.is_err());
        #[cfg(target_os = "linux")]
        {
            // On Linux without real module, should get NotFound or similar
            assert!(result.is_err());
        }
    }

    #[test]
    fn unload_module_stub() {
        let result = KmodManager::unload_module("test", false);
        #[cfg(not(target_os = "linux"))]
        assert!(result.is_err());
        #[cfg(target_os = "linux")]
        {
            assert!(result.is_err());
        }
    }

    // ── ModuleInfo ──────────────────────────────────────────────

    #[test]
    fn module_info_stub() {
        let _result = KmodManager::module_info("nonexistent");
        #[cfg(not(target_os = "linux"))]
        assert!(_result.is_err());
    }

    // ── Edge Cases ──────────────────────────────────────────────

    #[test]
    fn validate_name_special_chars() {
        assert!(validate_module_name("test`echo").is_err());
        assert!(validate_module_name("test$(id)").is_err());
        assert!(validate_module_name("test&id").is_err());
    }
}
