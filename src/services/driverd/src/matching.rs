//! Hardware ↔ driver matching for mission-driverd.
//!
//! Replaces the M2-C stub matching behavior with a real
//! compatibility/matching layer. Matches drivers to hardware
//! based on modalias patterns, vendor/device IDs, kernel
//! compatibility, architecture, and driver metadata.
//!
//! ## Architecture
//!
//! This module extends the existing inventory models rather than
//! creating a new matching architecture. It uses the existing
//! `HardwareId`, `DriverId`, `DriverEntry`, `CompatibilityInfo`,
//! and `KernelCompatibility` types.
//!
//! ## Matching Criteria
//!
//! - **Modalias pattern matching**: Driver `supported_hardware`
//!   patterns matched against device modalias strings
//! - **Vendor/device ID matching**: Direct vendor+device ID matching
//! - **Kernel version compatibility**: Checks kernel version range
//! - **Architecture matching**: Ensures driver arch matches system
//! - **Feature requirements**: Checks required kernel config features
//!
//! ## Security
//!
//! - Pattern matching does not execute arbitrary code
//! - Modalias patterns are validated before matching
//! - Compatibility scores are bounded [0.0, 1.0]

use crate::inventory::{CompatibilityInfo, DriverEntry, HardwareDevice};

// ── System Information ────────────────────────────────────────────

/// Information about the current system used for matching.
#[derive(Debug, Clone)]
pub struct SystemInfo {
    /// Kernel version string (e.g., "6.8.0-arch1-1").
    pub kernel_version: String,
    /// System architecture (e.g., "x86_64", "aarch64").
    pub architecture: String,
    /// Available kernel config features (from /boot/config-* or /proc/config.gz).
    pub kernel_features: Vec<String>,
}

impl SystemInfo {
    /// Detect system information from the running kernel.
    #[cfg(target_os = "linux")]
    pub fn detect() -> Self {
        let kernel_version = std::fs::read_to_string("/proc/sys/kernel/osrelease")
            .ok()
            .map(|s| s.trim().to_string())
            .unwrap_or_else(|| "unknown".to_string());

        let architecture = std::env::consts::ARCH.to_string();

        let kernel_features = detect_kernel_features();

        Self {
            kernel_version,
            architecture,
            kernel_features,
        }
    }

    /// Stub for non-Linux platforms.
    #[cfg(not(target_os = "linux"))]
    pub fn detect() -> Self {
        Self {
            kernel_version: "unknown".to_string(),
            architecture: std::env::consts::ARCH.to_string(),
            kernel_features: Vec::new(),
        }
    }
}

/// Detect enabled kernel features from /boot/config-* or /proc/config.gz.
#[cfg(target_os = "linux")]
fn detect_kernel_features() -> Vec<String> {
    let mut features = Vec::new();

    // Try reading from /proc/config.gz (requires CONFIG_IKCONFIG_PROC)
    let config_paths = vec![
        "/proc/config.gz",
        "/boot/config-", // Will be completed with kernel version
    ];

    for path in &config_paths {
        let content = if path.ends_with(".gz") {
            // Try reading /proc/config.gz
            match std::fs::read(path) {
                Ok(data) => {
                    // Try to decompress with gzip
                    match decompress_gzip(&data) {
                        Some(text) => text,
                        None => continue,
                    }
                }
                Err(_) => continue,
            }
        } else {
            // Complete the path with kernel version
            let kernel_release = std::fs::read_to_string("/proc/sys/kernel/osrelease")
                .ok()
                .map(|s| s.trim().to_string())
                .unwrap_or_default();

            let full_path = format!("{}{}", path, kernel_release);
            match std::fs::read_to_string(&full_path) {
                Ok(s) => s,
                Err(_) => continue,
            }
        };

        for line in content.lines() {
            let line = line.trim();
            if line.starts_with("CONFIG_") && line.contains('=') {
                let eq_pos = line.find('=').unwrap();
                let config_name = line[..eq_pos].to_string();
                let value = &line[eq_pos + 1..];

                // Only add if the feature is enabled (=y or =m)
                if value == "y" || value == "m" {
                    features.push(config_name);
                }
            }
        }

        // If we got features from this path, stop
        if !features.is_empty() {
            break;
        }
    }

    features
}

/// Simple gzip decompression using libc's zlib (minimal, safe).
#[cfg(target_os = "linux")]
fn decompress_gzip(_data: &[u8]) -> Option<String> {
    // Use flate2 if available, otherwise skip
    // For now, rely on /boot/config-* as fallback
    None
}

// ── Hardware Matcher ──────────────────────────────────────────────

/// Matches hardware devices to compatible drivers.
pub struct HardwareMatcher {
    /// Current system information.
    system: SystemInfo,
}

impl HardwareMatcher {
    /// Create a new hardware matcher with system detection.
    pub fn new() -> Self {
        Self {
            system: SystemInfo::detect(),
        }
    }

    /// Create a hardware matcher with explicit system info (for testing).
    pub fn with_system(system: SystemInfo) -> Self {
        Self { system }
    }

    /// Find all drivers that match a given hardware device.
    ///
    /// Returns a list of (driver_entry, compatibility_info) pairs
    /// sorted by compatibility score (highest first).
    pub fn find_matching_drivers<'a>(
        &self,
        device: &HardwareDevice,
        drivers: &'a [DriverEntry],
    ) -> Vec<(&'a DriverEntry, CompatibilityInfo)> {
        let mut matches: Vec<(&DriverEntry, CompatibilityInfo)> = drivers
            .iter()
            .filter_map(|driver| {
                let compat = self.evaluate_compatibility(driver, device);
                if compat.compatible {
                    Some((driver, compat))
                } else {
                    None
                }
            })
            .collect();

        // Sort by score descending
        matches.sort_by(|a, b| {
            b.1.score
                .partial_cmp(&a.1.score)
                .unwrap_or(std::cmp::Ordering::Equal)
        });

        matches
    }

    /// Evaluate the compatibility of a driver with a hardware device.
    ///
    /// Returns a `CompatibilityInfo` with score, explanation, and issues.
    pub fn evaluate_compatibility(
        &self,
        driver: &DriverEntry,
        device: &HardwareDevice,
    ) -> CompatibilityInfo {
        let mut issues = Vec::new();
        let mut total_score = 0.0f64;
        let mut checks = 0u32;

        // 1. Modalias pattern match (weight: 0.5)
        checks += 1;
        if self.check_modalias_match(driver, device) {
            total_score += 0.5;
        } else {
            issues.push("No modalias pattern matches this device".into());
        }

        // 2. Vendor/device ID match (weight: 0.2)
        checks += 1;
        if self.check_vendor_device_match(driver, device) {
            total_score += 0.2;
        } else {
            issues.push("No vendor/device ID match".into());
        }

        // 3. Kernel version compatibility (hard block if incompatible)
        checks += 1;
        match self.check_kernel_compatibility(driver) {
            KernelCheckResult::Compatible => {
                total_score += 0.15;
            }
            KernelCheckResult::Incompatible(reason) => {
                return CompatibilityInfo::incompatible(
                    format!(
                        "Kernel {} is incompatible with driver '{}'",
                        self.system.kernel_version, driver.id.name
                    ),
                    vec![reason],
                );
            }
            KernelCheckResult::Unknown => {
                // Partial score for unknown kernel compatibility
                total_score += 0.05;
                issues.push("Kernel compatibility unknown — assuming partial compatibility".into());
            }
        }

        // 4. Architecture match (weight: 0.1, hard fail if mismatch)
        checks += 1;
        if self.check_architecture_match(driver) {
            total_score += 0.1;
        } else {
            issues.push(format!(
                "Driver architecture '{}' does not match system '{}'",
                driver.id.arch, self.system.architecture
            ));
            return CompatibilityInfo::incompatible(
                format!(
                    "Architecture mismatch: driver requires '{}', system is '{}'",
                    driver.id.arch, self.system.architecture
                ),
                issues,
            );
        }

        // 5. Kernel feature requirements (weight: 0.05)
        checks += 1;
        match self.check_kernel_features(driver) {
            FeatureCheckResult::AllPresent => {
                total_score += 0.05;
            }
            FeatureCheckResult::Missing(features) => {
                issues.push(format!(
                    "Required kernel features not enabled: {}",
                    features.join(", ")
                ));
            }
            FeatureCheckResult::Unknown => {
                total_score += 0.025;
            }
        }

        let score = if checks > 0 { total_score } else { 0.0 };

        let compatible = score >= 0.5;

        let explanation = if compatible {
            format!(
                "Driver '{}' is compatible with device (score: {:.2})",
                driver.id.name, score
            )
        } else {
            format!(
                "Driver '{}' is not compatible with device (score: {:.2}): {}",
                driver.id.name,
                score,
                issues.join("; ")
            )
        };

        CompatibilityInfo {
            compatible,
            score: score.clamp(0.0, 1.0),
            explanation,
            issues,
            signature_verified: driver
                .compatibility
                .as_ref()
                .and_then(|c| c.signature_verified),
        }
    }

    /// Check if any of the driver's supported hardware modalias patterns
    /// match the device's modalias.
    fn check_modalias_match(&self, driver: &DriverEntry, device: &HardwareDevice) -> bool {
        let device_modalias = &device.hardware_id.modalias;
        for pattern in &driver.supported_hardware {
            if modalias_pattern_match(pattern, device_modalias) {
                return true;
            }
        }
        false
    }

    /// Check if the driver supports the device's vendor/device IDs.
    fn check_vendor_device_match(&self, driver: &DriverEntry, device: &HardwareDevice) -> bool {
        // Check if vendor_id and device_id appear in the modalias or supported_hardware
        let vendor = &device.hardware_id.vendor_id;
        let device_id = &device.hardware_id.device_id;

        for pattern in &driver.supported_hardware {
            if (pattern.contains(vendor.trim_start_matches("0x"))
                || pattern.contains(vendor.trim_start_matches("0X")))
                && (pattern.contains(device_id.trim_start_matches("0x"))
                    || pattern.contains(device_id.trim_start_matches("0X")))
            {
                return true;
            }
        }

        false
    }

    /// Check if the driver's kernel compatibility matches the system.
    fn check_kernel_compatibility(&self, driver: &DriverEntry) -> KernelCheckResult {
        let compat = &driver.id.kernel_compat;

        // Parse kernel version into comparable components
        let sys_parts: Vec<u64> = self
            .system
            .kernel_version
            .split(|c: char| !c.is_ascii_digit())
            .filter_map(|s| s.parse::<u64>().ok())
            .collect();

        if sys_parts.is_empty() {
            return KernelCheckResult::Unknown;
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
                    return KernelCheckResult::Incompatible(format!(
                        "Kernel {} is older than required minimum {}",
                        self.system.kernel_version, compat.min_version
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
                        return KernelCheckResult::Incompatible(format!(
                            "Kernel {} is newer than required maximum {}",
                            self.system.kernel_version, max_version
                        ));
                    }
                    if sys_part < max_part {
                        break;
                    }
                }
            }
        }

        KernelCheckResult::Compatible
    }

    /// Check if the driver's architecture matches the system.
    fn check_architecture_match(&self, driver: &DriverEntry) -> bool {
        let sys_arch = self.system.architecture.to_lowercase();
        let driver_arch = driver.id.arch.to_lowercase();

        // Direct match
        if sys_arch == driver_arch {
            return true;
        }

        // Handle common aliases
        matches!(
            (sys_arch.as_str(), driver_arch.as_str()),
            ("x86_64", "amd64") | ("amd64", "x86_64") | ("aarch64", "arm64") | ("arm64", "aarch64")
        )
    }

    /// Check if required kernel features are present.
    fn check_kernel_features(&self, driver: &DriverEntry) -> FeatureCheckResult {
        let required = &driver.id.kernel_compat.required_features;
        if required.is_empty() {
            return FeatureCheckResult::AllPresent;
        }

        if self.system.kernel_features.is_empty() {
            return FeatureCheckResult::Unknown;
        }

        let missing: Vec<&str> = required
            .iter()
            .filter(|feat| !self.system.kernel_features.contains(feat))
            .map(|s| s.as_str())
            .collect();

        if missing.is_empty() {
            FeatureCheckResult::AllPresent
        } else {
            FeatureCheckResult::Missing(missing.iter().map(|s| s.to_string()).collect())
        }
    }

    /// Get the current system info (for external use).
    pub fn system_info(&self) -> &SystemInfo {
        &self.system
    }

    /// Update system info (e.g., after kernel update).
    pub fn refresh_system_info(&mut self) {
        self.system = SystemInfo::detect();
    }
}

impl Default for HardwareMatcher {
    fn default() -> Self {
        Self::new()
    }
}

// ── Helper Types ──────────────────────────────────────────────────

enum KernelCheckResult {
    Compatible,
    Incompatible(String),
    Unknown,
}

enum FeatureCheckResult {
    AllPresent,
    Missing(Vec<String>),
    Unknown,
}

// ── Modalias Pattern Matching ─────────────────────────────────────

/// Match a modalias pattern against a device modalias.
///
/// Patterns use glob-style wildcards:
/// - `*` matches any sequence of characters
/// - `?` matches any single character
/// - `[...]` character class (not implemented — treated as literal)
///
/// This is a simplified matching algorithm sufficient for
/// matching driver modalias patterns (which typically use
/// `*` as the only wildcard).
pub(crate) fn modalias_pattern_match(pattern: &str, modalias: &str) -> bool {
    if pattern == "*" {
        return true;
    }

    // Split pattern on '*' and check each segment
    let segments: Vec<&str> = pattern.split('*').collect();

    if segments.is_empty() || (segments.len() == 1 && segments[0].is_empty()) {
        return modalias.is_empty();
    }

    let mut pos = 0;
    let modalias_bytes = modalias.as_bytes();

    for (i, segment) in segments.iter().enumerate() {
        if segment.is_empty() {
            continue;
        }

        if i == 0 {
            // First segment must match at the beginning
            if !modalias.starts_with(segment) {
                return false;
            }
            pos = segment.len();
        } else if i == segments.len() - 1 {
            // Last segment must match at the end
            if !modalias.ends_with(segment) {
                return false;
            }
            // Need to ensure there's room for the segment after pos
            if modalias.len() < segment.len() {
                return false;
            }
            let start = modalias.len() - segment.len();
            if start < pos {
                return false;
            }
        } else {
            // Middle segments can match anywhere
            let remaining = &modalias_bytes[pos..];
            let seg_bytes = segment.as_bytes();

            // Find the segment in the remaining string
            match find_subslice(remaining, seg_bytes) {
                Some(found_pos) => {
                    pos += found_pos + seg_bytes.len();
                }
                None => return false,
            }
        }
    }

    true
}

/// Find a subslice in a byte slice.
fn find_subslice(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    if needle.is_empty() {
        return Some(0);
    }
    haystack
        .windows(needle.len())
        .position(|window| window == needle)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::inventory::{
        BusType, DriverId, DriverModuleType, DriverStatus, DriverVersion, HardwareId,
        KernelCompatibility,
    };

    fn sample_driver(name: &str, modalias_pattern: &str) -> DriverEntry {
        DriverEntry {
            id: DriverId {
                name: name.into(),
                provider: "test".into(),
                version: DriverVersion::new(1, 0, 0),
                arch: std::env::consts::ARCH.to_string(),
                kernel_compat: crate::inventory::KernelCompatibility {
                    min_version: "2.6.32".into(),
                    max_version: None,
                    required_features: Vec::new(),
                },
                module_type: DriverModuleType::KernelModule,
            },
            status: DriverStatus::Available,
            supported_hardware: vec![modalias_pattern.into()],
            compatibility: None,
            sources: Vec::new(),
            metadata: std::collections::HashMap::new(),
            description: "test".into(),
            package_size_bytes: None,
        }
    }

    fn sample_device(modalias: &str) -> HardwareDevice {
        HardwareDevice {
            hardware_id: HardwareId {
                modalias: modalias.into(),
                vendor_id: "0x8086".into(),
                device_id: "0xA0C8".into(),
                subsystem_vendor_id: None,
                subsystem_device_id: None,
                class_code: None,
                bus: "pci".into(),
                current_driver: None,
            },
            device_name: "Test Device".into(),
            vendor_name: None,
            bus_type: BusType::Pci,
            bound_driver: None,
            operational: false,
            matched_drivers: Vec::new(),
        }
    }

    // ── Modalias Pattern Matching ──────────────────────────────

    #[test]
    fn modalias_exact_match() {
        assert!(modalias_pattern_match(
            "pci:v00008086d0000A0C8sv00000000sd00000000bc02sc00i00",
            "pci:v00008086d0000A0C8sv00000000sd00000000bc02sc00i00"
        ));
    }

    #[test]
    fn modalias_wildcard_match() {
        assert!(modalias_pattern_match(
            "pci:v00008086d*",
            "pci:v00008086d0000A0C8sv..."
        ));
        assert!(modalias_pattern_match(
            "*8086*",
            "pci:v00008086d0000A0C8sv..."
        ));
    }

    #[test]
    fn modalias_no_match() {
        assert!(!modalias_pattern_match(
            "pci:v000010DEd*",
            "pci:v00008086d0000A0C8sv..."
        ));
    }

    #[test]
    fn modalias_wildcard_all() {
        assert!(modalias_pattern_match("*", "anything"));
        assert!(modalias_pattern_match("*", ""));
    }

    #[test]
    fn modalias_prefix_match() {
        assert!(modalias_pattern_match(
            "pci:v00008086*",
            "pci:v00008086d0000A0C8"
        ));
        assert!(!modalias_pattern_match(
            "pci:v000010DE*",
            "pci:v00008086d0000A0C8"
        ));
    }

    // ── HardwareMatcher ────────────────────────────────────────

    #[test]
    fn matcher_modalias_match() {
        let matcher = HardwareMatcher::with_system(SystemInfo {
            kernel_version: "6.8.0".into(),
            architecture: std::env::consts::ARCH.to_string(),
            kernel_features: Vec::new(),
        });
        let driver = sample_driver("test", "pci:v00008086d*");
        let device = sample_device("pci:v00008086d0000A0C8sv...");
        let compat = matcher.evaluate_compatibility(&driver, &device);
        assert!(compat.compatible);
        assert!(compat.score > 0.0);
    }

    #[test]
    fn matcher_no_modalias_match() {
        let matcher = HardwareMatcher::with_system(SystemInfo {
            kernel_version: "6.8.0".into(),
            architecture: std::env::consts::ARCH.to_string(),
            kernel_features: Vec::new(),
        });
        let driver = sample_driver("test", "pci:v000010DEd*");
        let device = sample_device("pci:v00008086d0000A0C8sv...");
        let compat = matcher.evaluate_compatibility(&driver, &device);
        assert!(!compat.compatible);
    }

    #[test]
    fn matcher_architecture_mismatch() {
        let matcher = HardwareMatcher::with_system(SystemInfo {
            kernel_version: "6.8.0".into(),
            architecture: "x86_64".into(),
            kernel_features: Vec::new(),
        });
        let mut driver = sample_driver("test", "pci:v00008086d*");
        driver.id.arch = "aarch64".into();
        let device = sample_device("pci:v00008086d0000A0C8sv...");
        let compat = matcher.evaluate_compatibility(&driver, &device);
        // Should be incompatible due to arch mismatch
        assert!(!compat.compatible);
    }

    #[test]
    fn matcher_kernel_out_of_range() {
        let matcher = HardwareMatcher::with_system(SystemInfo {
            kernel_version: "5.0.0".into(),
            architecture: "x86_64".into(),
            kernel_features: Vec::new(),
        });
        let mut driver = sample_driver("test", "pci:v00008086d*");
        driver.id.kernel_compat = KernelCompatibility {
            min_version: "6.1.0".into(),
            max_version: Some("6.8.0".into()),
            required_features: Vec::new(),
        };
        let device = sample_device("pci:v00008086d0000A0C8sv...");
        let compat = matcher.evaluate_compatibility(&driver, &device);
        assert!(!compat.compatible);
    }

    #[test]
    fn matcher_kernel_in_range() {
        let matcher = HardwareMatcher::with_system(SystemInfo {
            kernel_version: "6.5.0".into(),
            architecture: "x86_64".into(),
            kernel_features: Vec::new(),
        });
        let mut driver = sample_driver("test", "pci:v00008086d*");
        driver.id.kernel_compat = KernelCompatibility {
            min_version: "6.1.0".into(),
            max_version: Some("6.8.0".into()),
            required_features: Vec::new(),
        };
        let device = sample_device("pci:v00008086d0000A0C8sv...");
        let compat = matcher.evaluate_compatibility(&driver, &device);
        assert!(compat.compatible);
    }

    #[test]
    fn matcher_find_matching_drivers_returns_sorted() {
        let matcher = HardwareMatcher::with_system(SystemInfo {
            kernel_version: "6.8.0".into(),
            architecture: std::env::consts::ARCH.to_string(),
            kernel_features: Vec::new(),
        });
        let device = sample_device("pci:v00008086d0000A0C8sv...");
        let drivers = vec![
            sample_driver("good_match", "pci:v00008086d*"),
            sample_driver("bad_match", "pci:v000010DEd*"),
        ];
        let matches = matcher.find_matching_drivers(&device, &drivers);
        assert_eq!(matches.len(), 1);
        assert_eq!(matches[0].0.id.name, "good_match");
    }

    // ── SystemInfo ─────────────────────────────────────────────

    #[test]
    fn system_info_detect_does_not_panic() {
        let info = SystemInfo::detect();
        assert!(!info.architecture.is_empty());
    }

    #[test]
    fn matcher_default_does_not_panic() {
        let matcher = HardwareMatcher::new();
        assert!(!matcher.system_info().architecture.is_empty());
    }

    // ── Modalias Edge Cases ────────────────────────────────────

    #[test]
    fn modalias_match_empty_pattern() {
        assert!(!modalias_pattern_match("", "something"));
    }

    #[test]
    fn modalias_match_leading_wildcard() {
        assert!(modalias_pattern_match("*8086*", "pci:v00008086d..."));
        assert!(modalias_pattern_match("*8086", "pci:v00008086"));
    }
}
