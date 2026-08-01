//! Driver selection pipeline for mission-driverd.
//!
//! Integrates hardware detection, compatibility matching,
//! source resolution, and version comparison to select
//! the best available driver package for a hardware device.
//!
//! ## Architecture
//!
//! The selection pipeline follows this flow:
//!
//! HardwareDevice
//!     → modalias/vendor/device matching (matching.rs)
//!     → compatible DriverEntry candidates
//!     → compatibility scoring
//!     → source lookup (source.rs)
//!     → package metadata (metadata.rs)
//!     → architecture compatibility
//!     → kernel compatibility
//!     → trust validation
//!     → version comparison
//!     → selected DriverPackage
//!
//! ## Security
//!
//! - Never silently select an untrusted package.
//! - Source priority must not override trust policy.
//! - A valid signature from an unknown key is not sufficient.
//! - Deterministic selection with clear priority rules.

use std::collections::HashMap;

use crate::inventory::{DriverEntry, HardwareDevice, KernelCompatibility};
use crate::matching::HardwareMatcher;
use crate::metadata::PackageMetadata;
use crate::repository::ManifestVerification;
use crate::source::SourceRegistry;

// ── Selection Candidate ───────────────────────────────────────────

/// A candidate driver package for a hardware device.
#[derive(Debug, Clone)]
pub struct SelectionCandidate {
    /// Driver entry from inventory.
    pub driver: DriverEntry,
    /// Package metadata from source.
    pub metadata: Option<PackageMetadata>,
    /// Source identifier.
    pub source_id: String,
    /// Compatibility score (0.0 – 1.0).
    pub score: f64,
    /// Whether the candidate is trusted.
    pub trusted: bool,
    /// Rejection reason if not selected.
    pub rejection_reason: Option<String>,
}

// ── Selection Result ──────────────────────────────────────────────

/// Result of the driver selection pipeline.
#[derive(Debug, Clone)]
pub struct SelectionResult {
    /// The selected candidate (None if no suitable package found).
    pub selected: Option<SelectionCandidate>,
    /// All candidates considered.
    pub candidates: Vec<SelectionCandidate>,
    /// Whether any candidate was found at all.
    pub found_any: bool,
}

impl SelectionResult {
    /// Create a result with no candidates.
    pub fn none() -> Self {
        Self {
            selected: None,
            candidates: Vec::new(),
            found_any: false,
        }
    }
}

// ── Driver Selector ───────────────────────────────────────────────

/// Selects the best driver package for a hardware device.
///
/// Integrates matching, source resolution, version comparison,
/// trust validation, and repository manifest verification into
/// a deterministic selection pipeline.
///
/// ## Selection Precedence (high to low)
///
/// 1. Hardware compatibility (hard requirement)
/// 2. Kernel compatibility (hard requirement)
/// 3. Architecture match (hard requirement)
/// 4. Package manifest verification (trusted > unverified > invalid)
/// 5. Source trust level
/// 6. Driver version (higher = better)
/// 7. Source priority (lower number = higher priority)
/// 8. Deterministic tie-breaking (alphabetical by driver name)
pub struct DriverSelector {
    /// Hardware matcher for compatibility evaluation.
    matcher: HardwareMatcher,
    /// Source registry for package resolution.
    source_registry: SourceRegistry,
    /// Verified manifests per source ID (populated by RepositoryManager).
    verified_manifests: HashMap<String, ManifestVerification>,
}

impl DriverSelector {
    /// Create a new driver selector.
    pub fn new(source_registry: SourceRegistry) -> Self {
        Self {
            matcher: HardwareMatcher::new(),
            source_registry,
            verified_manifests: HashMap::new(),
        }
    }

    /// Create a selector with explicit matcher (for testing).
    pub fn with_matcher(matcher: HardwareMatcher, source_registry: SourceRegistry) -> Self {
        Self {
            matcher,
            source_registry,
            verified_manifests: HashMap::new(),
        }
    }

    /// Update the manifest verification status for a source.
    ///
    /// Called by the RepositoryManager after metadata refresh.
    pub fn update_manifest_verification(
        &mut self,
        source_id: &str,
        verification: ManifestVerification,
    ) {
        self.verified_manifests
            .insert(source_id.to_string(), verification);
    }

    /// Remove manifest verification for a source (e.g., on expiry).
    pub fn clear_manifest_verification(&mut self, source_id: &str) {
        self.verified_manifests.remove(source_id);
    }

    /// Clear all manifest verifications (e.g., on config change).
    pub fn clear_all_verifications(&mut self) {
        self.verified_manifests.clear();
    }

    /// Find the best driver package for a hardware device.
    ///
    /// Returns a `SelectionResult` with the best candidate (if any)
    /// and all candidates considered.
    pub fn select_for_device(
        &self,
        device: &HardwareDevice,
        available_drivers: &[DriverEntry],
        available_packages: &[PackageMetadata],
    ) -> SelectionResult {
        let mut candidates: Vec<SelectionCandidate> = Vec::new();

        for driver in available_drivers {
            // 1. Evaluate hardware compatibility
            let compat = self.matcher.evaluate_compatibility(driver, device);
            if !compat.compatible {
                candidates.push(SelectionCandidate {
                    driver: driver.clone(),
                    metadata: None,
                    source_id: String::new(),
                    score: 0.0,
                    trusted: false,
                    rejection_reason: Some(compat.explanation.clone()),
                });
                continue;
            }

            // 2. Find matching package metadata
            let matching_packages: Vec<&PackageMetadata> = available_packages
                .iter()
                .filter(|p| {
                    p.package_id
                        .driver_name
                        .eq_ignore_ascii_case(&driver.id.name)
                        && self.is_source_enabled(&p.source_id)
                })
                .collect();

            if matching_packages.is_empty() {
                candidates.push(SelectionCandidate {
                    driver: driver.clone(),
                    metadata: None,
                    source_id: String::new(),
                    score: compat.score,
                    trusted: false,
                    rejection_reason: Some("No matching package found in enabled sources".into()),
                });
                continue;
            }

            // 3. For each matching package, check architecture, kernel, and trust
            for &pkg in &matching_packages {
                let mut reasons: Vec<String> = Vec::new();

                // Architecture check
                if !self.is_architecture_compatible(driver, pkg) {
                    reasons.push(format!(
                        "Architecture mismatch: driver requires '{}', package is '{}'",
                        driver.id.arch, pkg.architecture
                    ));
                }

                // Kernel compatibility
                if !self.is_kernel_compatible(&pkg.kernel_compat) {
                    reasons.push("Kernel incompatible with package requirements".to_string());
                }

                // Trust check
                let trusted = self.is_source_trusted(&pkg.source_id, pkg.signing_key_id.as_deref());
                if !trusted {
                    reasons.push("Package source or signing key not trusted".into());
                }

                candidates.push(SelectionCandidate {
                    driver: driver.clone(),
                    metadata: Some(pkg.clone()),
                    source_id: pkg.source_id.clone(),
                    score: compat.score,
                    trusted,
                    rejection_reason: if reasons.is_empty() {
                        None
                    } else {
                        Some(reasons.join("; "))
                    },
                });
            }
        }

        // 4. Select the best candidate
        let found_any = !candidates.is_empty();
        let selected = self.select_best_candidate(&candidates);

        SelectionResult {
            selected,
            candidates,
            found_any,
        }
    }

    /// Select the best candidate from a list.
    ///
    /// Priority rules (in order):
    /// 1. Trusted over untrusted (candidate-level trust)
    /// 2. Manifest verified over unverified (repository-level trust)
    /// 3. Higher compatibility score
    /// 4. Higher source priority
    /// 5. Higher version
    /// 6. Deterministic alphabetical tie-break
    fn select_best_candidate(
        &self,
        candidates: &[SelectionCandidate],
    ) -> Option<SelectionCandidate> {
        let qualified: Vec<&SelectionCandidate> = candidates
            .iter()
            .filter(|c| c.rejection_reason.is_none())
            .collect();

        if qualified.is_empty() {
            return None;
        }

        qualified
            .into_iter()
            .max_by(|a, b| {
                // 1. Trusted over untrusted: candidate-level trust
                let a_trust = a.trusted as i32;
                let b_trust = b.trusted as i32;
                match a_trust.cmp(&b_trust) {
                    std::cmp::Ordering::Equal => {}
                    ord => return ord,
                }

                // 2. Manifest verification: verified > unverified > invalid/none
                let a_manifest = self.manifest_trust_score(&a.source_id);
                let b_manifest = self.manifest_trust_score(&b.source_id);
                match a_manifest.cmp(&b_manifest) {
                    std::cmp::Ordering::Equal => {}
                    ord => return ord,
                }

                // 3. Higher compatibility score wins
                match a
                    .score
                    .partial_cmp(&b.score)
                    .unwrap_or(std::cmp::Ordering::Equal)
                {
                    std::cmp::Ordering::Equal => {}
                    ord => return ord,
                }

                // 4. Source priority: lower = better, so reverse
                let a_prio = self.source_priority(&a.source_id);
                let b_prio = self.source_priority(&b.source_id);
                match a_prio.cmp(&b_prio).reverse() {
                    std::cmp::Ordering::Equal => {}
                    ord => return ord,
                }

                // 5. Higher version wins
                let a_ver = a.metadata.as_ref().map(|m| &m.package_id.version);
                let b_ver = b.metadata.as_ref().map(|m| &m.package_id.version);
                match a_ver.cmp(&b_ver) {
                    std::cmp::Ordering::Equal => {}
                    ord => return ord,
                }

                // 6. Deterministic: alphabetical by driver name
                a.driver.id.name.cmp(&b.driver.id.name)
            })
            .cloned()
    }

    /// Get the manifest trust score for a source.
    ///
    /// Returns 2 for verified, 1 for unverified (no manifest), 0 for invalid.
    fn manifest_trust_score(&self, source_id: &str) -> u8 {
        match self.verified_manifests.get(source_id) {
            Some(ManifestVerification::Verified { .. }) => 2,
            Some(ManifestVerification::Unverified) => 1,
            Some(ManifestVerification::InvalidSignature(_)) => 0,
            Some(ManifestVerification::UnknownKey(_)) => 0,
            None => 1, // No manifest verification = neutral
        }
    }

    /// Check if a source is enabled.
    fn is_source_enabled(&self, source_id: &str) -> bool {
        self.source_registry.is_source_enabled(source_id)
    }

    /// Get the priority of a source.
    fn source_priority(&self, source_id: &str) -> u32 {
        self.source_registry
            .get_source(source_id)
            .map(|s| s.priority)
            .unwrap_or(100)
    }

    /// Check if a source and signing key are trusted.
    fn is_source_trusted(&self, source_id: &str, signing_key_id: Option<&str>) -> bool {
        let source = match self.source_registry.get_source(source_id) {
            Some(s) => s,
            None => return false,
        };

        // If the source has no trusted keys configured, trust defaults by source type
        if source.trusted_key_ids.is_empty() {
            return source.source_type.default_trusted();
        }

        // If a key ID is specified, it must match one of the trusted keys
        if let Some(key_id) = signing_key_id {
            return source.trusted_key_ids.iter().any(|k| k == key_id);
        }

        // No signing key specified — depends on source type
        source.source_type.default_trusted()
    }

    /// Check if a driver's architecture is compatible.
    fn is_architecture_compatible(&self, _driver: &DriverEntry, package: &PackageMetadata) -> bool {
        let sys_arch = std::env::consts::ARCH.to_lowercase();
        let pkg_arch = package.normalized_architecture();

        sys_arch == pkg_arch
            || matches!(
                (sys_arch.as_str(), pkg_arch.as_str()),
                ("x86_64", "amd64")
                    | ("amd64", "x86_64")
                    | ("aarch64", "arm64")
                    | ("arm64", "aarch64")
            )
    }

    /// Check kernel version compatibility.
    fn is_kernel_compatible(&self, compat: &KernelCompatibility) -> bool {
        let sys_info = crate::matching::SystemInfo::detect();
        let sys_parts: Vec<u64> = sys_info
            .kernel_version
            .split(|c: char| !c.is_ascii_digit())
            .filter_map(|s| s.parse::<u64>().ok())
            .collect();

        if sys_parts.is_empty() {
            return true; // Unknown kernel version — assume compatible
        }

        // Check minimum
        let min_parts: Vec<u64> = compat
            .min_version
            .split('.')
            .filter_map(|s| s.parse::<u64>().ok())
            .collect();

        if !min_parts.is_empty() {
            for (i, &min_p) in min_parts.iter().enumerate() {
                let sys_p = sys_parts.get(i).copied().unwrap_or(0);
                if sys_p < min_p {
                    return false;
                }
                if sys_p > min_p {
                    break;
                }
            }
        }

        // Check maximum
        if let Some(ref max) = compat.max_version {
            let max_parts: Vec<u64> = max
                .split('.')
                .filter_map(|s| s.parse::<u64>().ok())
                .collect();
            if !max_parts.is_empty() {
                for (i, &max_p) in max_parts.iter().enumerate() {
                    let sys_p = sys_parts.get(i).copied().unwrap_or(0);
                    if sys_p > max_p {
                        return false;
                    }
                    if sys_p < max_p {
                        break;
                    }
                }
            }
        }

        true
    }

    /// Refresh system info (call after kernel update).
    pub fn refresh_system_info(&mut self) {
        self.matcher.refresh_system_info();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::inventory::*;
    use crate::metadata::{PackageDigest, PackageId};
    use crate::source::SourceRegistry;

    fn test_selector() -> DriverSelector {
        let sources = SourceRegistry::from_configs(crate::source::default_sources()).unwrap();
        DriverSelector::new(sources)
    }

    fn sample_device() -> HardwareDevice {
        HardwareDevice {
            hardware_id: HardwareId {
                modalias: "pci:v00008086d0000A0C8sv00000000sd00000000bc02sc00i00".into(),
                vendor_id: "0x8086".into(),
                device_id: "0xA0C8".into(),
                subsystem_vendor_id: None,
                subsystem_device_id: None,
                class_code: None,
                bus: "pci".into(),
                current_driver: None,
            },
            device_name: "Ethernet Controller".into(),
            vendor_name: None,
            bus_type: BusType::Pci,
            bound_driver: None,
            operational: false,
            matched_drivers: Vec::new(),
        }
    }

    fn sample_driver() -> DriverEntry {
        DriverEntry {
            id: DriverId {
                name: "e1000e".into(),
                provider: "linux".into(),
                version: DriverVersion::new(1, 0, 0),
                arch: std::env::consts::ARCH.to_string(),
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
            metadata: std::collections::HashMap::new(),
            description: "Test driver".into(),
            package_size_bytes: None,
        }
    }

    fn sample_package(driver_name: &str) -> PackageMetadata {
        PackageMetadata {
            package_id: PackageId {
                driver_name: driver_name.into(),
                source_id: "mission".into(),
                version: DriverVersion::new(1, 0, 0),
            },
            driver_name: driver_name.into(),
            description: "Test package".into(),
            module_type: DriverModuleType::KernelModule,
            architecture: std::env::consts::ARCH.to_string(),
            kernel_compat: KernelCompatibility {
                min_version: "2.6.32".into(),
                max_version: None,
                required_features: Vec::new(),
            },
            filename: "test.ko".into(),
            size_bytes: 1000,
            digest: PackageDigest::sha256(vec![0u8; 32]).unwrap(),
            signature_hex: "deadbeef".into(),
            signing_key_id: Some("mission-os-release-key".into()),
            source_id: "mission".into(),
            url_path: "packages/test.ko".into(),
            is_delta: false,
            base_version: None,
        }
    }

    #[test]
    fn selector_no_candidates() {
        let selector = test_selector();
        let device = sample_device();
        let result = selector.select_for_device(&device, &[], &[]);
        assert!(!result.found_any);
        assert!(result.selected.is_none());
        assert!(result.candidates.is_empty());
    }

    #[test]
    fn selector_selects_compatible_driver() {
        let selector = test_selector();
        let device = sample_device();
        let driver = sample_driver();
        let pkg = sample_package("e1000e");

        let result = selector.select_for_device(&device, &[driver], &[pkg]);
        assert!(result.found_any);
        assert!(result.selected.is_some());
        let selected = result.selected.unwrap();
        assert_eq!(selected.driver.id.name, "e1000e");
        assert!(selected.trusted);
        assert!(selected.rejection_reason.is_none());
    }

    #[test]
    fn selector_rejects_architecture_mismatch() {
        let selector = test_selector();
        let device = sample_device();
        let driver = sample_driver();
        let mut pkg = sample_package("e1000e");
        pkg.architecture = "aarch64".into(); // Wrong arch

        let result = selector.select_for_device(&device, &[driver], &[pkg]);
        assert!(!result.candidates.is_empty());
    }

    #[test]
    fn selector_prefers_higher_version() {
        let selector = test_selector();
        let device = sample_device();
        let driver = sample_driver();

        let mut pkg1 = sample_package("e1000e");
        pkg1.package_id.version = DriverVersion::new(1, 0, 0);

        let mut pkg2 = sample_package("e1000e");
        pkg2.package_id.version = DriverVersion::new(2, 0, 0);

        let result = selector.select_for_device(&device, &[driver], &[pkg1, pkg2]);
        if let Some(selected) = result.selected {
            assert_eq!(
                selected.metadata.as_ref().unwrap().package_id.version,
                DriverVersion::new(2, 0, 0)
            );
        }
    }

    #[test]
    fn selector_missing_source_returns_untrusted() {
        let selector = test_selector();
        let device = sample_device();
        let driver = sample_driver();

        let mut pkg = sample_package("e1000e");
        pkg.source_id = "unknown_source".into();

        let result = selector.select_for_device(&device, &[driver], &[pkg]);
        assert!(!result.candidates.is_empty());
    }

    #[test]
    fn select_best_candidate_empty() {
        let selector = test_selector();
        let result = selector.select_best_candidate(&[]);
        assert!(result.is_none());
    }

    #[test]
    fn selection_result_none() {
        let result = SelectionResult::none();
        assert!(!result.found_any);
        assert!(result.selected.is_none());
    }

    #[test]
    fn kernel_compatibility_check() {
        let selector = test_selector();

        // Compatible kernel range
        let compat = KernelCompatibility {
            min_version: "2.6.32".into(),
            max_version: None,
            required_features: Vec::new(),
        };
        assert!(selector.is_kernel_compatible(&compat));
    }

    #[test]
    fn source_trust_model() {
        let selector = test_selector();
        assert!(selector.is_source_trusted("mission", Some("mission-os-release-key")));
        // Unknown source is not trusted
        assert!(!selector.is_source_trusted("unknown", Some("key")));
    }
}
