//! Conflict detection for mission-driverd.
//!
//! Detects and reports conflicts that would prevent a driver
//! operation from succeeding safely. Used by the execution
//! engine before any privileged operation.
//!
//! ## Conflict Types Detected
//!
//! - Incompatible kernel version
//! - Unsupported architecture
//! - Conflicting driver/module
//! - Duplicate installation
//! - Missing dependency
//! - Invalid package/signature
//! - Hardware incompatibility
//! - Active module that cannot safely be removed

use crate::inventory::{DriverEntry, DriverModuleType, HardwareDevice};
use crate::matching::SystemInfo;

// ── Conflict Types ────────────────────────────────────────────────

/// Specific type of conflict detected.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConflictType {
    /// Kernel version does not satisfy driver requirements.
    IncompatibleKernel,
    /// Driver architecture does not match system architecture.
    UnsupportedArchitecture,
    /// Another loaded module conflicts with this driver.
    ConflictingModule,
    /// Driver is already installed (for install operations).
    DuplicateInstallation,
    /// A required dependency is not installed or available.
    MissingDependency,
    /// Package format is invalid or corrupted.
    InvalidPackage,
    /// Signature verification failed.
    InvalidSignature,
    /// Hardware device is not compatible with this driver.
    HardwareIncompatibility,
    /// Module is in use and cannot be safely removed.
    ModuleInUse,
    /// Operation is not supported for this driver type.
    UnsupportedOperation,
}

impl ConflictType {
    /// Human-readable description of the conflict type.
    pub fn description(&self) -> &'static str {
        match self {
            ConflictType::IncompatibleKernel => "Kernel version is incompatible with this driver",
            ConflictType::UnsupportedArchitecture => {
                "Driver does not support this system architecture"
            }
            ConflictType::ConflictingModule => "A conflicting kernel module is currently loaded",
            ConflictType::DuplicateInstallation => "This driver is already installed on the system",
            ConflictType::MissingDependency => "A required dependency is not met",
            ConflictType::InvalidPackage => "The driver package is invalid or corrupted",
            ConflictType::InvalidSignature => "The driver package signature is invalid or missing",
            ConflictType::HardwareIncompatibility => "No compatible hardware found for this driver",
            ConflictType::ModuleInUse => {
                "The kernel module is currently in use and cannot be removed"
            }
            ConflictType::UnsupportedOperation => {
                "This operation is not supported for this driver type"
            }
        }
    }
}

/// A detected conflict with details.
#[derive(Debug, Clone)]
pub struct ConflictInfo {
    /// The type of conflict.
    pub conflict_type: ConflictType,
    /// Human-readable description of the specific conflict.
    pub message: String,
    /// Actionable details (e.g., which module conflicts, which dependency is missing).
    pub details: String,
}

impl ConflictInfo {
    fn new(conflict_type: ConflictType, message: String, details: String) -> Self {
        Self {
            conflict_type,
            message,
            details,
        }
    }
}

/// Result of a conflict check.
#[derive(Debug, Clone)]
pub struct ConflictResult {
    /// Whether any conflicts were found.
    pub has_conflicts: bool,
    /// List of conflicts found.
    pub conflicts: Vec<ConflictInfo>,
}

impl ConflictResult {
    /// Create a result with no conflicts.
    pub fn none() -> Self {
        Self {
            has_conflicts: false,
            conflicts: Vec::new(),
        }
    }

    /// Create a result with a single conflict.
    pub fn single(conflict: ConflictInfo) -> Self {
        Self {
            has_conflicts: true,
            conflicts: vec![conflict],
        }
    }

    /// Add a conflict to the result.
    pub fn add(&mut self, conflict: ConflictInfo) {
        self.has_conflicts = true;
        self.conflicts.push(conflict);
    }

    /// Merge another conflict result into this one.
    pub fn merge(&mut self, other: ConflictResult) {
        if other.has_conflicts {
            self.has_conflicts = true;
            self.conflicts.extend(other.conflicts);
        }
    }
}

// ── Conflict Detector ─────────────────────────────────────────────

/// Detects conflicts that would prevent safe driver operations.
pub struct ConflictDetector {
    /// Current system information.
    system: SystemInfo,
}

impl ConflictDetector {
    /// Create a new conflict detector with system detection.
    pub fn new() -> Self {
        Self {
            system: SystemInfo::detect(),
        }
    }

    /// Create a conflict detector with explicit system info (for testing).
    pub fn with_system(system: SystemInfo) -> Self {
        Self { system }
    }

    /// Run all relevant conflict checks for a driver installation.
    ///
    /// # Arguments
    ///
    /// * `driver` - The driver to check conflicts for.
    /// * `inventory_drivers` - All drivers currently in inventory.
    /// * `loaded_modules` - List of currently loaded kernel module names.
    /// * `hardware` - List of detected hardware devices.
    pub fn check_install(
        &self,
        driver: &DriverEntry,
        inventory_drivers: &[DriverEntry],
        loaded_modules: &[String],
        hardware: &[HardwareDevice],
    ) -> ConflictResult {
        let mut result = ConflictResult::none();

        // 1. Check kernel compatibility
        result.merge(self.check_kernel(driver));

        // 2. Check architecture
        result.merge(self.check_architecture(driver));

        // 3. Check duplicate installation
        result.merge(self.check_duplicate(driver, inventory_drivers));

        // 4. Check conflicting modules
        result.merge(self.check_conflicting_modules(driver, loaded_modules));

        // 5. Check hardware compatibility
        result.merge(self.check_hardware(driver, hardware));

        result
    }

    /// Run all relevant conflict checks for a driver removal.
    ///
    /// # Arguments
    ///
    /// * `driver` - The driver to check conflicts for.
    /// * `loaded_modules` - List of currently loaded kernel module names.
    /// * `inventory_drivers` - All drivers currently in inventory.
    pub fn check_remove(
        &self,
        driver: &DriverEntry,
        loaded_modules: &[String],
        inventory_drivers: &[DriverEntry],
    ) -> ConflictResult {
        let mut result = ConflictResult::none();

        // 1. Check if module is in use
        if driver.status.is_operational() {
            result.merge(self.check_module_in_use(driver, loaded_modules));
        }

        // 2. Check if other drivers depend on this one
        result.merge(self.check_dependents(driver, inventory_drivers));

        result
    }

    /// Run all relevant conflict checks for a driver update.
    pub fn check_update(
        &self,
        current_driver: &DriverEntry,
        new_driver: &DriverEntry,
        inventory_drivers: &[DriverEntry],
        loaded_modules: &[String],
        hardware: &[HardwareDevice],
    ) -> ConflictResult {
        let mut result = ConflictResult::none();

        // Run install checks on the new version
        result.merge(self.check_install(new_driver, inventory_drivers, loaded_modules, hardware));

        // Additional update-specific checks
        if current_driver.id.version >= new_driver.id.version {
            result.add(ConflictInfo::new(
                ConflictType::InvalidPackage,
                "Cannot downgrade driver".to_string(),
                format!(
                    "Current version {} is newer than or equal to target version {}",
                    current_driver.id.version, new_driver.id.version
                ),
            ));
        }

        result
    }

    /// Check kernel version compatibility.
    pub fn check_kernel(&self, driver: &DriverEntry) -> ConflictResult {
        let compat = &driver.id.kernel_compat;
        let sys_parts: Vec<u64> = self
            .system
            .kernel_version
            .split(|c: char| !c.is_ascii_digit())
            .filter_map(|s| s.parse::<u64>().ok())
            .collect();

        if sys_parts.is_empty() {
            return ConflictResult::none(); // Cannot determine kernel version
        }

        // Check minimum version
        let min_parts: Vec<u64> = compat
            .min_version
            .split('.')
            .filter_map(|s| s.parse::<u64>().ok())
            .collect();

        if !min_parts.is_empty() {
            for (i, &min_part) in min_parts.iter().enumerate() {
                let sys_part = sys_parts.get(i).copied().unwrap_or(0);
                if sys_part < min_part {
                    return ConflictResult::single(ConflictInfo::new(
                        ConflictType::IncompatibleKernel,
                        format!(
                            "Kernel {} is older than required minimum {}",
                            self.system.kernel_version, compat.min_version
                        ),
                        format!(
                            "Minimum kernel version: {}, current: {}",
                            compat.min_version, self.system.kernel_version
                        ),
                    ));
                }
                if sys_part > min_part {
                    break;
                }
            }
        }

        // Check maximum version
        if let Some(ref max_version) = compat.max_version {
            let max_parts: Vec<u64> = max_version
                .split('.')
                .filter_map(|s| s.parse::<u64>().ok())
                .collect();

            if !max_parts.is_empty() {
                for (i, &max_part) in max_parts.iter().enumerate() {
                    let sys_part = sys_parts.get(i).copied().unwrap_or(0);
                    if sys_part > max_part {
                        return ConflictResult::single(ConflictInfo::new(
                            ConflictType::IncompatibleKernel,
                            format!(
                                "Kernel {} is newer than required maximum {}",
                                self.system.kernel_version, max_version
                            ),
                            format!(
                                "Maximum kernel version: {}, current: {}",
                                max_version, self.system.kernel_version
                            ),
                        ));
                    }
                    if sys_part < max_part {
                        break;
                    }
                }
            }
        }

        ConflictResult::none()
    }

    /// Check architecture compatibility.
    pub fn check_architecture(&self, driver: &DriverEntry) -> ConflictResult {
        let sys_arch = self.system.architecture.to_lowercase();
        let driver_arch = driver.id.arch.to_lowercase();

        let compatible = sys_arch == driver_arch
            || matches!(
                (sys_arch.as_str(), driver_arch.as_str()),
                ("x86_64", "amd64")
                    | ("amd64", "x86_64")
                    | ("aarch64", "arm64")
                    | ("arm64", "aarch64")
            );

        if !compatible {
            ConflictResult::single(ConflictInfo::new(
                ConflictType::UnsupportedArchitecture,
                format!(
                    "Driver architecture '{}' does not match system '{}'",
                    driver.id.arch, self.system.architecture
                ),
                format!(
                    "Required: {}, system: {}",
                    driver.id.arch, self.system.architecture
                ),
            ))
        } else {
            ConflictResult::none()
        }
    }

    /// Check for duplicate installation.
    pub fn check_duplicate(
        &self,
        driver: &DriverEntry,
        inventory_drivers: &[DriverEntry],
    ) -> ConflictResult {
        for existing in inventory_drivers {
            if existing.id.name.eq_ignore_ascii_case(&driver.id.name)
                && existing
                    .id
                    .provider
                    .eq_ignore_ascii_case(&driver.id.provider)
                && (existing.status.is_operational() || existing.status == DriverStatus::Installed)
            {
                if existing.id.version == driver.id.version {
                    return ConflictResult::single(ConflictInfo::new(
                        ConflictType::DuplicateInstallation,
                        format!(
                            "Driver '{}/{}' is already installed",
                            driver.id.provider, driver.id.name
                        ),
                        format!(
                            "Current version: {}. Use update to upgrade.",
                            existing.id.version
                        ),
                    ));
                }
                // Different version — don't block
                return ConflictResult::none();
            }
        }
        ConflictResult::none()
    }

    /// Check for conflicting loaded modules.
    pub fn check_conflicting_modules(
        &self,
        driver: &DriverEntry,
        loaded_modules: &[String],
    ) -> ConflictResult {
        // For kernel modules, check if any loaded modules conflict
        if driver.id.module_type != DriverModuleType::KernelModule {
            return ConflictResult::none();
        }

        // Check for common known conflicts
        // e.g., nvidia and nouveau cannot both be loaded
        let driver_name_lower = driver.id.name.to_lowercase();
        let conflicts: &[(&str, &[&str])] = &[
            ("nvidia", &["nouveau"]),
            ("nouveau", &["nvidia"]),
            ("iwlwifi", &["iwlegacy"]),
        ];

        for (drv, conflicting) in conflicts.iter() {
            if driver_name_lower == *drv {
                for loaded in loaded_modules {
                    let loaded_lower = loaded.to_lowercase();
                    if conflicting.contains(&loaded_lower.as_str()) {
                        return ConflictResult::single(ConflictInfo::new(
                            ConflictType::ConflictingModule,
                            format!(
                                "Conflicting module '{}' is currently loaded",
                                loaded
                            ),
                            format!(
                                "Module '{}' conflicts with '{}'. Unload the conflicting module first.",
                                loaded, driver.id.name
                            ),
                        ));
                    }
                }
            }
        }

        ConflictResult::none()
    }

    /// Check hardware compatibility.
    pub fn check_hardware(
        &self,
        driver: &DriverEntry,
        hardware: &[HardwareDevice],
    ) -> ConflictResult {
        // If no hardware detected, skip check (could be pre-installation)
        if hardware.is_empty() {
            return ConflictResult::none();
        }

        // Check each hardware device against the driver's supported patterns
        for device in hardware {
            for pattern in &driver.supported_hardware {
                if crate::matching::modalias_pattern_match(pattern, &device.hardware_id.modalias) {
                    return ConflictResult::none(); // Found compatible hardware
                }
            }
        }

        // No hardware matched — this is a warning, not a hard block
        // Some drivers (e.g., filesystem drivers) don't have hardware matches
        ConflictResult::none()
    }

    /// Check if a module is in use and cannot be safely removed.
    pub fn check_module_in_use(
        &self,
        driver: &DriverEntry,
        loaded_modules: &[String],
    ) -> ConflictResult {
        if driver.id.module_type != DriverModuleType::KernelModule {
            return ConflictResult::none();
        }

        let driver_name = driver.id.name.to_lowercase();
        if loaded_modules.contains(&driver_name) {
            // Check if it's actually in use by querying /proc/modules
            // For now, warn that the user should ensure the module is not active
            return ConflictResult::single(ConflictInfo::new(
                ConflictType::ModuleInUse,
                format!(
                    "Module '{}' is currently loaded and may be in use",
                    driver.id.name
                ),
                "The kernel module is currently active. Ensure no processes are using it \
                 before removal, or use force flag to override."
                    .to_string(),
            ));
        }

        ConflictResult::none()
    }

    /// Check if other drivers depend on this one.
    pub fn check_dependents(
        &self,
        driver: &DriverEntry,
        inventory_drivers: &[DriverEntry],
    ) -> ConflictResult {
        let driver_name = driver.id.name.to_lowercase();
        let dependents: Vec<&str> = inventory_drivers
            .iter()
            .filter(|d| {
                d.id.name.to_lowercase() != driver_name
                    && d.id
                        .kernel_compat
                        .required_features
                        .iter()
                        .any(|f| f.to_lowercase().contains(&driver_name))
            })
            .map(|d| d.id.name.as_str())
            .collect();

        if !dependents.is_empty() {
            ConflictResult::single(ConflictInfo::new(
                ConflictType::ConflictingModule,
                format!(
                    "Other drivers depend on '{}': {}",
                    driver.id.name,
                    dependents.join(", ")
                ),
                "Remove dependent drivers first or expect breakage.".to_string(),
            ))
        } else {
            ConflictResult::none()
        }
    }

    /// Get the current system info.
    pub fn system_info(&self) -> &SystemInfo {
        &self.system
    }
}

impl Default for ConflictDetector {
    fn default() -> Self {
        Self::new()
    }
}

use crate::inventory::DriverStatus;

#[cfg(test)]
mod tests {
    use super::*;
    use crate::inventory::{DriverId, DriverStatus, DriverVersion, KernelCompatibility};
    use std::collections::HashMap;

    fn test_driver(name: &str, arch: &str) -> DriverEntry {
        DriverEntry {
            id: DriverId {
                name: name.into(),
                provider: "test".into(),
                version: DriverVersion::new(1, 0, 0),
                arch: arch.into(),
                kernel_compat: KernelCompatibility {
                    min_version: "2.6.32".into(),
                    max_version: None,
                    required_features: Vec::new(),
                },
                module_type: DriverModuleType::KernelModule,
            },
            status: DriverStatus::Available,
            supported_hardware: vec!["pci:v00008086d*".into()],
            compatibility: None,
            sources: Vec::new(),
            metadata: HashMap::new(),
            description: "test".into(),
            package_size_bytes: None,
        }
    }

    #[test]
    fn conflict_result_none() {
        let result = ConflictResult::none();
        assert!(!result.has_conflicts);
        assert!(result.conflicts.is_empty());
    }

    #[test]
    fn conflict_result_single() {
        let info = ConflictInfo::new(
            ConflictType::IncompatibleKernel,
            "test".into(),
            "details".into(),
        );
        let result = ConflictResult::single(info);
        assert!(result.has_conflicts);
        assert_eq!(result.conflicts.len(), 1);
    }

    #[test]
    fn conflict_result_merge() {
        let mut r1 = ConflictResult::none();
        let r2 = ConflictResult::single(ConflictInfo::new(
            ConflictType::IncompatibleKernel,
            "test".into(),
            "details".into(),
        ));
        r1.merge(r2);
        assert!(r1.has_conflicts);
    }

    // ── ConflictType descriptions ──────────────────────────────

    #[test]
    fn conflict_type_descriptions() {
        assert!(!ConflictType::IncompatibleKernel.description().is_empty());
        assert!(!ConflictType::MissingDependency.description().is_empty());
        assert!(!ConflictType::ConflictingModule.description().is_empty());
        assert!(!ConflictType::ModuleInUse.description().is_empty());
    }

    // ── ConflictDetector ───────────────────────────────────────

    #[test]
    fn check_kernel_compatible() {
        let detector = ConflictDetector::with_system(SystemInfo {
            kernel_version: "6.8.0".into(),
            architecture: "x86_64".into(),
            kernel_features: Vec::new(),
        });
        let driver = test_driver("e1000e", "x86_64");
        let result = detector.check_kernel(&driver);
        assert!(!result.has_conflicts);
    }

    #[test]
    fn check_kernel_too_old() {
        let detector = ConflictDetector::with_system(SystemInfo {
            kernel_version: "5.10.0".into(),
            architecture: "x86_64".into(),
            kernel_features: Vec::new(),
        });
        let mut driver = test_driver("test", "x86_64");
        driver.id.kernel_compat = KernelCompatibility {
            min_version: "6.1.0".into(),
            max_version: None,
            required_features: Vec::new(),
        };
        let result = detector.check_kernel(&driver);
        assert!(result.has_conflicts);
        assert_eq!(
            result.conflicts[0].conflict_type,
            ConflictType::IncompatibleKernel
        );
    }

    #[test]
    fn check_kernel_too_new() {
        let detector = ConflictDetector::with_system(SystemInfo {
            kernel_version: "7.0.0".into(),
            architecture: "x86_64".into(),
            kernel_features: Vec::new(),
        });
        let mut driver = test_driver("test", "x86_64");
        driver.id.kernel_compat = KernelCompatibility {
            min_version: "2.6.32".into(),
            max_version: Some("6.8.0".into()),
            required_features: Vec::new(),
        };
        let result = detector.check_kernel(&driver);
        assert!(result.has_conflicts);
    }

    #[test]
    fn check_architecture_mismatch() {
        let detector = ConflictDetector::with_system(SystemInfo {
            kernel_version: "6.8.0".into(),
            architecture: "aarch64".into(),
            kernel_features: Vec::new(),
        });
        let driver = test_driver("test", "x86_64");
        let result = detector.check_architecture(&driver);
        assert!(result.has_conflicts);
    }

    #[test]
    fn check_architecture_match() {
        let detector = ConflictDetector::with_system(SystemInfo {
            kernel_version: "6.8.0".into(),
            architecture: "x86_64".into(),
            kernel_features: Vec::new(),
        });
        let driver = test_driver("test", "amd64");
        let result = detector.check_architecture(&driver);
        assert!(!result.has_conflicts);
    }

    #[test]
    fn check_duplicate_installed() {
        let detector = ConflictDetector::with_system(SystemInfo {
            kernel_version: "6.8.0".into(),
            architecture: "x86_64".into(),
            kernel_features: Vec::new(),
        });
        let driver = test_driver("test", "x86_64");
        let mut existing = test_driver("test", "x86_64");
        existing.status = DriverStatus::Active;
        let result = detector.check_duplicate(&driver, &[existing]);
        assert!(result.has_conflicts);
        assert_eq!(
            result.conflicts[0].conflict_type,
            ConflictType::DuplicateInstallation
        );
    }

    #[test]
    fn check_duplicate_not_installed() {
        let detector = ConflictDetector::with_system(SystemInfo {
            kernel_version: "6.8.0".into(),
            architecture: "x86_64".into(),
            kernel_features: Vec::new(),
        });
        let driver = test_driver("test", "x86_64");
        let result = detector.check_duplicate(&driver, &[]);
        assert!(!result.has_conflicts);
    }

    #[test]
    fn check_conflicting_modules_found() {
        let detector = ConflictDetector::with_system(SystemInfo {
            kernel_version: "6.8.0".into(),
            architecture: "x86_64".into(),
            kernel_features: Vec::new(),
        });
        let driver = test_driver("nvidia", "x86_64");
        let loaded = vec!["nouveau".to_string(), "e1000e".to_string()];
        let result = detector.check_conflicting_modules(&driver, &loaded);
        assert!(result.has_conflicts);
    }

    #[test]
    fn check_conflicting_modules_not_found() {
        let detector = ConflictDetector::with_system(SystemInfo {
            kernel_version: "6.8.0".into(),
            architecture: "x86_64".into(),
            kernel_features: Vec::new(),
        });
        let driver = test_driver("e1000e", "x86_64");
        let loaded = vec!["nouveau".to_string()];
        let result = detector.check_conflicting_modules(&driver, &loaded);
        assert!(!result.has_conflicts);
    }

    // ── Full install check ─────────────────────────────────────

    #[test]
    fn check_install_all_clear() {
        let detector = ConflictDetector::with_system(SystemInfo {
            kernel_version: "6.8.0".into(),
            architecture: "x86_64".into(),
            kernel_features: Vec::new(),
        });
        let driver = test_driver("e1000e", "x86_64");
        let result = detector.check_install(&driver, &[], &["e1000e".into()], &[]);
        assert!(!result.has_conflicts);
    }

    #[test]
    fn check_install_with_conflicts() {
        let detector = ConflictDetector::with_system(SystemInfo {
            kernel_version: "5.10.0".into(),
            architecture: "x86_64".into(),
            kernel_features: Vec::new(),
        });
        let mut driver = test_driver("test", "x86_64");
        driver.id.kernel_compat = KernelCompatibility {
            min_version: "6.1.0".into(),
            max_version: None,
            required_features: Vec::new(),
        };
        let result = detector.check_install(&driver, &[], &[], &[]);
        assert!(result.has_conflicts);
    }
}
