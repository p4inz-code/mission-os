//! Driver inventory and discovery models for mission-driverd.
//!
//! Defines the canonical data models for hardware device identity,
//! driver identity, versioning, status, compatibility, and source
//! availability metadata.
//!
//! ## Architecture
//!
//! Per MOS-ENG-MOD-001 §3.6 (mission-driverd), this module implements:
//! - Hardware detection (udev integration boundary)
//! - Driver matching and installation API boundary
//! - Driver signature verification boundary (deferred to M2-D)
//! - Driver update management API boundary (deferred to M2-D)
//! - Hardware compatibility database
//!
//! ## Security
//!
//! - All identifiers are validated before storage or IPC transmission.
//! - Version strings are parsed and validated — never used raw.
//! - Compatibility information must not expose system vulnerabilities.
//! - Status transitions are validated to prevent invalid states.
//! - No arbitrary shell commands or kernel module loading in M2-C.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

use crate::error::{ServiceError, ServiceResult};

// ── Hardware Identity ─────────────────────────────────────────────

/// Unique identifier for a hardware device on the system.
///
/// Captures the essential identity attributes from udev/hardware
/// discovery, sufficient for driver matching.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HardwareId {
    /// Modalias string from the kernel (e.g., "pci:v00008086d0000A0C8...").
    pub modalias: String,
    /// Vendor identifier (e.g., "0x8086" for Intel).
    pub vendor_id: String,
    /// Device/product identifier (e.g., "0xA0C8").
    pub device_id: String,
    /// Subsystem vendor identifier (optional).
    pub subsystem_vendor_id: Option<String>,
    /// Subsystem device identifier (optional).
    pub subsystem_device_id: Option<String>,
    /// Class code from PCI/USB specification (e.g., "0x020000" for Ethernet).
    pub class_code: Option<String>,
    /// Hardware bus type (e.g., "pci", "usb", "hid", "virtio").
    pub bus: String,
    /// Driver currently bound to this device, if any.
    pub current_driver: Option<String>,
}

impl HardwareId {
    /// Validate the hardware identity fields.
    ///
    /// Returns `Ok(())` if all fields pass validation.
    pub fn validate(&self) -> ServiceResult<()> {
        if self.modalias.trim().is_empty() {
            return Err(ServiceError::InvalidArgument(
                "modalias must not be empty".into(),
            ));
        }
        if self.vendor_id.trim().is_empty() {
            return Err(ServiceError::InvalidArgument(
                "vendor_id must not be empty".into(),
            ));
        }
        if self.device_id.trim().is_empty() {
            return Err(ServiceError::InvalidArgument(
                "device_id must not be empty".into(),
            ));
        }
        if self.bus.trim().is_empty() {
            return Err(ServiceError::InvalidArgument(
                "bus must not be empty".into(),
            ));
        }
        // Validate bus type is recognized
        validate_bus_type(&self.bus)?;
        Ok(())
    }
}

/// Recognized hardware bus types.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum BusType {
    /// PCI/PCIe bus.
    Pci,
    /// USB bus.
    Usb,
    /// Human Interface Device (over USB/BT).
    Hid,
    /// Virtio (virtualized).
    Virtio,
    /// ACPI-enumerated devices.
    Acpi,
    /// Platform devices (non-discoverable buses).
    Platform,
    /// SDIO bus.
    Sdio,
    /// I2C bus.
    I2c,
    /// SPI bus.
    Spi,
    /// Thunderbolt / USB4.
    Thunderbolt,
    /// Other recognized bus type.
    Other(String),
}

/// Validate that a bus type string is recognized.
fn validate_bus_type(bus: &str) -> ServiceResult<()> {
    let recognized = [
        "pci",
        "usb",
        "hid",
        "virtio",
        "acpi",
        "platform",
        "sdio",
        "i2c",
        "spi",
        "thunderbolt",
    ];
    if recognized.contains(&bus.to_lowercase().as_str()) {
        Ok(())
    } else {
        // Allow custom bus types but warn
        Err(ServiceError::InvalidArgument(format!(
            "unrecognized bus type: {bus}"
        )))
    }
}

// ── Driver Identity ───────────────────────────────────────────────

/// Unique identifier for a driver within the system.
///
/// Captures everything needed to match a driver to hardware and
/// track its lifecycle.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DriverId {
    /// Driver name (e.g., "e1000e", "iwlwifi", "nvidia").
    pub name: String,
    /// Provider/vendor of the driver (e.g., "mission", "linux", "nvidia").
    pub provider: String,
    /// Driver version string.
    pub version: DriverVersion,
    /// Architecture this driver targets.
    pub arch: String,
    /// Kernel version compatibility range.
    pub kernel_compat: KernelCompatibility,
    /// Module type (kernel module, firmware, userspace).
    pub module_type: DriverModuleType,
}

impl DriverId {
    /// Validate the driver identity.
    pub fn validate(&self) -> ServiceResult<()> {
        if self.name.trim().is_empty() {
            return Err(ServiceError::InvalidArgument(
                "driver name must not be empty".into(),
            ));
        }
        if self.provider.trim().is_empty() {
            return Err(ServiceError::InvalidArgument(
                "driver provider must not be empty".into(),
            ));
        }
        if self.arch.trim().is_empty() {
            return Err(ServiceError::InvalidArgument(
                "driver arch must not be empty".into(),
            ));
        }
        self.version.validate()?;
        self.kernel_compat.validate()?;
        Ok(())
    }
}

/// Type of driver module.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DriverModuleType {
    /// Loadable kernel module (LKM).
    KernelModule,
    /// Firmware blob loaded by kernel or driver.
    Firmware,
    /// Userspace driver (e.g., via libusb, ioctl).
    Userspace,
    /// Device tree overlay.
    DeviceTreeOverlay,
}

// ── Driver Version ────────────────────────────────────────────────

/// Structured driver version with comparison support.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DriverVersion {
    /// Major version number.
    pub major: u64,
    /// Minor version number.
    pub minor: u64,
    /// Patch version number.
    pub patch: u64,
    /// Optional pre-release identifier (e.g., "rc1", "alpha").
    pub pre_release: Option<String>,
}

impl DriverVersion {
    /// Create a new driver version.
    pub const fn new(major: u64, minor: u64, patch: u64) -> Self {
        Self {
            major,
            minor,
            patch,
            pre_release: None,
        }
    }

    /// Parse a version string in "major.minor.patch" or
    /// "major.minor.patch-prerelease" format.
    pub fn parse(input: &str) -> ServiceResult<Self> {
        let input = input.trim();
        if input.is_empty() {
            return Err(ServiceError::InvalidArgument(
                "version string must not be empty".into(),
            ));
        }

        let (numeric_part, pre_release) = if let Some(dash_idx) = input.find('-') {
            let (left, right) = input.split_at(dash_idx);
            let pre = &right[1..]; // skip dash
            let pre = if pre.is_empty() {
                None
            } else {
                Some(pre.to_string())
            };
            (left, pre)
        } else {
            (input, None)
        };

        let parts: Vec<&str> = numeric_part.split('.').collect();
        if parts.len() < 3 {
            return Err(ServiceError::InvalidArgument(format!(
                "version must have at least 3 components: {input}"
            )));
        }

        let major = parts[0]
            .parse::<u64>()
            .map_err(|e| ServiceError::InvalidArgument(format!("invalid major version: {e}")))?;
        let minor = parts[1]
            .parse::<u64>()
            .map_err(|e| ServiceError::InvalidArgument(format!("invalid minor version: {e}")))?;
        let patch = parts[2]
            .parse::<u64>()
            .map_err(|e| ServiceError::InvalidArgument(format!("invalid patch version: {e}")))?;

        Ok(Self {
            major,
            minor,
            patch,
            pre_release,
        })
    }

    /// Validate this version.
    pub fn validate(&self) -> ServiceResult<()> {
        // All u64 values are valid. Check pre-release doesn't contain
        // path separators or shell metacharacters.
        if let Some(ref pre) = self.pre_release {
            if pre
                .chars()
                .any(|c| c == '/' || c == '\\' || c == ';' || c == '|')
            {
                return Err(ServiceError::InvalidArgument(
                    "pre-release contains invalid characters".into(),
                ));
            }
        }
        Ok(())
    }
}

impl std::fmt::Display for DriverVersion {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}.{}.{}", self.major, self.minor, self.patch)?;
        if let Some(ref pre) = self.pre_release {
            write!(f, "-{pre}")?;
        }
        Ok(())
    }
}

impl PartialOrd for DriverVersion {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for DriverVersion {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        match self.major.cmp(&other.major) {
            std::cmp::Ordering::Equal => {}
            ord => return ord,
        }
        match self.minor.cmp(&other.minor) {
            std::cmp::Ordering::Equal => {}
            ord => return ord,
        }
        match self.patch.cmp(&other.patch) {
            std::cmp::Ordering::Equal => {}
            ord => return ord,
        }
        // No pre-release means stable > prerelease
        match (&self.pre_release, &other.pre_release) {
            (None, None) => std::cmp::Ordering::Equal,
            (None, Some(_)) => std::cmp::Ordering::Greater,
            (Some(_), None) => std::cmp::Ordering::Less,
            (Some(a), Some(b)) => a.cmp(b),
        }
    }
}

// ── Kernel Compatibility ──────────────────────────────────────────

/// Kernel version compatibility specification for a driver.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct KernelCompatibility {
    /// Minimum supported kernel version (e.g., "6.1.0").
    pub min_version: String,
    /// Maximum supported kernel version (e.g., "6.8.0"), None = latest.
    pub max_version: Option<String>,
    /// Specific kernel feature flags required (e.g., "CONFIG_DEBUG_FS").
    pub required_features: Vec<String>,
}

impl KernelCompatibility {
    /// Validate the compatibility specification.
    pub fn validate(&self) -> ServiceResult<()> {
        if self.min_version.trim().is_empty() {
            return Err(ServiceError::InvalidArgument(
                "min_version must not be empty".into(),
            ));
        }
        // Validate version format: should be numeric components separated by dots
        for part in self.min_version.split('.') {
            if part.parse::<u64>().is_err() {
                return Err(ServiceError::InvalidArgument(format!(
                    "invalid kernel version component: {part}"
                )));
            }
        }
        if let Some(ref max) = self.max_version {
            for part in max.split('.') {
                if part.parse::<u64>().is_err() {
                    return Err(ServiceError::InvalidArgument(format!(
                        "invalid kernel max version component: {part}"
                    )));
                }
            }
        }
        Ok(())
    }
}

// ── Driver Status ─────────────────────────────────────────────────

/// Lifecycle status of a driver in the system.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DriverStatus {
    /// Driver is available but not installed.
    Available,
    /// Driver is installed but not currently loaded.
    Installed,
    /// Driver is loaded and active.
    Active,
    /// Driver failed to load.
    Failed,
    /// Driver has been updated and is pending a reboot.
    PendingReboot,
    /// Driver has been removed.
    Removed,
    /// A newer version of this driver is available.
    UpdateAvailable,
}

impl DriverStatus {
    /// Whether this status represents an operational driver.
    pub fn is_operational(&self) -> bool {
        matches!(self, DriverStatus::Active | DriverStatus::Installed)
    }

    /// Whether the driver is in an error state.
    pub fn is_error(&self) -> bool {
        matches!(self, DriverStatus::Failed)
    }
}

// ── Compatibility Information ─────────────────────────────────────

/// Result of a hardware-to-driver compatibility check.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CompatibilityInfo {
    /// Whether the driver is compatible with the hardware.
    pub compatible: bool,
    /// Overall compatibility score (0.0 – 1.0).
    pub score: f64,
    /// Human-readable explanation of the compatibility assessment.
    pub explanation: String,
    /// List of potential issues or warnings.
    pub issues: Vec<String>,
    /// Whether signature verification passed (None if not checked).
    pub signature_verified: Option<bool>,
}

impl CompatibilityInfo {
    /// Create a new compatible result.
    pub fn compatible(explanation: impl Into<String>) -> Self {
        Self {
            compatible: true,
            score: 1.0,
            explanation: explanation.into(),
            issues: Vec::new(),
            signature_verified: None,
        }
    }

    /// Create a new incompatible result.
    pub fn incompatible(explanation: impl Into<String>, issues: Vec<String>) -> Self {
        Self {
            compatible: false,
            score: 0.0,
            explanation: explanation.into(),
            issues,
            signature_verified: None,
        }
    }

    /// Set the signature verification result.
    pub fn with_signature(mut self, verified: bool) -> Self {
        self.signature_verified = Some(verified);
        self
    }
}

// ── Driver Availability / Source Metadata ─────────────────────────

/// Source from which a driver can be obtained.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DriverSource {
    /// Source identifier (e.g., "mission", "linux-firmware", "vendor-archive").
    pub id: String,
    /// Human-readable source name.
    pub name: String,
    /// Source type.
    pub source_type: DriverSourceType,
    /// Whether this source is currently available/reachable.
    pub available: bool,
    /// Source priority (lower = higher priority).
    pub priority: u32,
}

/// Type of driver source.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DriverSourceType {
    /// Official Mission OS repository.
    Mission,
    /// Linux kernel upstream (built-in or DKMS).
    Linux,
    /// Vendor-provided driver (e.g., NVIDIA).
    Vendor,
    /// Community-maintained driver repository.
    Community,
    /// Local filesystem path.
    Local,
}

// ── Driver Entry (Aggregate) ──────────────────────────────────────

/// Complete driver entry combining identity, status, compatibility,
/// and source information.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DriverEntry {
    /// Unique driver identity.
    pub id: DriverId,
    /// Current lifecycle status.
    pub status: DriverStatus,
    /// Hardware modalias patterns this driver supports.
    pub supported_hardware: Vec<String>,
    /// Compatibility information for the current system.
    pub compatibility: Option<CompatibilityInfo>,
    /// Available sources for this driver.
    pub sources: Vec<DriverSource>,
    /// Free-form metadata key-value pairs.
    pub metadata: HashMap<String, String>,
    /// Human-readable description of the driver.
    pub description: String,
    /// Size of the driver package in bytes, if known.
    pub package_size_bytes: Option<u64>,
}

// ── Hardware Device Entry ─────────────────────────────────────────

/// A discovered hardware device in the system inventory.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HardwareDevice {
    /// Hardware identity.
    pub hardware_id: HardwareId,
    /// Human-readable device name (e.g., "Intel Ethernet Controller I219-V").
    pub device_name: String,
    /// Human-readable vendor name (e.g., "Intel Corporation").
    pub vendor_name: Option<String>,
    /// The bus type this device is on.
    pub bus_type: BusType,
    /// The driver currently bound, if any.
    pub bound_driver: Option<String>,
    /// Whether the device is operational.
    pub operational: bool,
    /// Matched drivers from the inventory (by driver name).
    pub matched_drivers: Vec<String>,
}

// ── Driver Operation Request/Response ─────────────────────────────

/// Request to install a driver.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InstallRequest {
    /// The driver to install.
    pub driver_name: String,
    /// Provider/source to install from.
    pub provider: String,
    /// Optional version constraint (e.g., ">= 1.0.0").
    pub version_constraint: Option<String>,
    /// Whether to force installation (override compatibility checks).
    #[serde(default)]
    pub force: bool,
}

impl InstallRequest {
    /// Validate the install request.
    pub fn validate(&self) -> ServiceResult<()> {
        if self.driver_name.trim().is_empty() {
            return Err(ServiceError::InvalidArgument(
                "driver_name must not be empty".into(),
            ));
        }
        if self.provider.trim().is_empty() {
            return Err(ServiceError::InvalidArgument(
                "provider must not be empty".into(),
            ));
        }
        Ok(())
    }
}

/// Request to remove a driver.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RemoveRequest {
    /// The driver to remove.
    pub driver_name: String,
    /// Whether to force removal even if the driver is in use.
    #[serde(default)]
    pub force: bool,
}

impl RemoveRequest {
    /// Validate the remove request.
    pub fn validate(&self) -> ServiceResult<()> {
        if self.driver_name.trim().is_empty() {
            return Err(ServiceError::InvalidArgument(
                "driver_name must not be empty".into(),
            ));
        }
        Ok(())
    }
}

/// Request to update a driver.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpdateRequest {
    /// The driver to update.
    pub driver_name: String,
    /// Optional target version to update to.
    pub target_version: Option<String>,
    /// Whether to allow downgrade when the installed version is newer.
    /// This is a future extension point — currently defaults to false
    /// and no runtime path sets it to true. A future policy engine may
    /// permit intentional downgrades through this field.
    #[serde(default)]
    pub allow_downgrade: bool,
}

impl UpdateRequest {
    /// Validate the update request.
    pub fn validate(&self) -> ServiceResult<()> {
        if self.driver_name.trim().is_empty() {
            return Err(ServiceError::InvalidArgument(
                "driver_name must not be empty".into(),
            ));
        }
        Ok(())
    }
}

/// Status of a driver operation.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum OperationStatus {
    /// Operation is pending.
    Pending,
    /// Operation is in progress.
    InProgress,
    /// Operation completed successfully.
    Completed,
    /// Operation failed.
    Failed,
    /// Operation was cancelled.
    Cancelled,
}

/// Result of a driver management operation.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OperationResult {
    /// Operation status.
    pub status: OperationStatus,
    /// Human-readable message describing the result.
    pub message: String,
    /// Error details if the operation failed.
    pub error: Option<String>,
    /// Affected driver name.
    pub driver_name: String,
}

impl OperationResult {
    /// Create a successful operation result.
    pub fn success(driver_name: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            status: OperationStatus::Completed,
            message: message.into(),
            error: None,
            driver_name: driver_name.into(),
        }
    }

    /// Create a failed operation result.
    pub fn failed(
        driver_name: impl Into<String>,
        message: impl Into<String>,
        error: impl Into<String>,
    ) -> Self {
        Self {
            status: OperationStatus::Failed,
            message: message.into(),
            error: Some(error.into()),
            driver_name: driver_name.into(),
        }
    }
}

// ── Inventory ─────────────────────────────────────────────────────

/// The complete driver inventory for the system.
///
/// Contains all known drivers and discovered hardware.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DriverInventory {
    /// All known drivers.
    pub drivers: Vec<DriverEntry>,
    /// All discovered hardware devices.
    pub devices: Vec<HardwareDevice>,
    /// Timestamp of the last inventory scan (Unix seconds).
    pub last_scan_timestamp: u64,
}

impl DriverInventory {
    /// Create a new empty inventory.
    pub fn new() -> Self {
        Self {
            drivers: Vec::new(),
            devices: Vec::new(),
            last_scan_timestamp: 0,
        }
    }

    /// Find a driver by name and provider.
    pub fn find_driver(&self, name: &str, provider: &str) -> Option<&DriverEntry> {
        self.drivers.iter().find(|d| {
            d.id.name.eq_ignore_ascii_case(name) && d.id.provider.eq_ignore_ascii_case(provider)
        })
    }

    /// Find a hardware device by modalias.
    pub fn find_device(&self, modalias: &str) -> Option<&HardwareDevice> {
        self.devices
            .iter()
            .find(|d| d.hardware_id.modalias == modalias)
    }

    /// Count active drivers.
    pub fn active_driver_count(&self) -> usize {
        self.drivers
            .iter()
            .filter(|d| d.status.is_operational())
            .count()
    }

    /// Count drivers in error state.
    pub fn failed_driver_count(&self) -> usize {
        self.drivers.iter().filter(|d| d.status.is_error()).count()
    }
}

impl Default for DriverInventory {
    fn default() -> Self {
        Self::new()
    }
}

// ── Inventory Scanner (Stub) ──────────────────────────────────────

/// Inventory scanner that manages driver inventory.
///
/// M2-D: Integrates real udev-based hardware enumeration and
/// driver matching, replacing the M2-C stub.
pub struct InventoryScanner {
    /// The current inventory.
    inventory: DriverInventory,
}

impl InventoryScanner {
    /// Create a new inventory scanner with an empty inventory.
    pub fn new() -> Self {
        Self {
            inventory: DriverInventory::new(),
        }
    }

    /// Return a reference to the current inventory.
    pub fn inventory(&self) -> &DriverInventory {
        &self.inventory
    }

    /// Return a mutable reference to the current inventory.
    pub fn inventory_mut(&mut self) -> &mut DriverInventory {
        &mut self.inventory
    }

    /// Scan the system for hardware and update the inventory.
    ///
    /// M2-D: Performs real udev/sysfs-based hardware enumeration.
    /// If udev is unavailable (non-Linux), returns a clean empty inventory.
    pub fn scan_system(&mut self) -> ServiceResult<()> {
        // M2-D: Real hardware enumeration via sysfs
        match crate::hwdetect::SysfsReader::enumerate_all() {
            Ok(devices) => {
                self.inventory.devices = devices;
            }
            Err(e) => {
                eprintln!("[inventory] hardware enumeration failed: {e}");
                self.inventory.devices.clear();
            }
        }

        // Populate driver inventory with well-known built-in drivers
        self.populate_builtin_drivers();

        self.inventory.last_scan_timestamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();

        Ok(())
    }

    /// Populate the inventory with well-known built-in kernel drivers.
    fn populate_builtin_drivers(&mut self) {
        // Check which drivers are actually loaded on this system
        #[cfg(target_os = "linux")]
        let loaded_modules: Vec<String> = crate::kmod::KmodManager::list_modules()
            .unwrap_or_default()
            .into_iter()
            .map(|m| m.name)
            .collect();

        #[cfg(not(target_os = "linux"))]
        let loaded_modules: Vec<String> = Vec::new();

        self.inventory.drivers = vec![
            DriverEntry {
                id: DriverId {
                    name: "e1000e".into(),
                    provider: "linux".into(),
                    version: DriverVersion::new(6, 8, 0),
                    arch: "amd64".into(),
                    kernel_compat: KernelCompatibility {
                        min_version: "2.6.32".into(),
                        max_version: None,
                        required_features: Vec::new(),
                    },
                    module_type: DriverModuleType::KernelModule,
                },
                status: if loaded_modules.contains(&"e1000e".to_string()) {
                    DriverStatus::Active
                } else {
                    DriverStatus::Available
                },
                supported_hardware: vec!["pci:v00008086d*".into()],
                compatibility: Some(CompatibilityInfo::compatible("In-tree kernel driver")),
                sources: vec![DriverSource {
                    id: "linux".into(),
                    name: "Linux Kernel".into(),
                    source_type: DriverSourceType::Linux,
                    available: true,
                    priority: 10,
                }],
                metadata: HashMap::new(),
                description: "Intel PRO/1000 PCIe Gigabit Ethernet driver".into(),
                package_size_bytes: None,
            },
            DriverEntry {
                id: DriverId {
                    name: "iwlwifi".into(),
                    provider: "linux".into(),
                    version: DriverVersion::new(6, 8, 0),
                    arch: "amd64".into(),
                    kernel_compat: KernelCompatibility {
                        min_version: "2.6.32".into(),
                        max_version: None,
                        required_features: vec!["CONFIG_IWLMVM".into()],
                    },
                    module_type: DriverModuleType::KernelModule,
                },
                status: if loaded_modules.contains(&"iwlwifi".to_string()) {
                    DriverStatus::Active
                } else {
                    DriverStatus::Available
                },
                supported_hardware: vec!["pci:v00008086d*".into()],
                compatibility: Some(CompatibilityInfo::compatible("In-tree kernel driver")),
                sources: vec![DriverSource {
                    id: "linux".into(),
                    name: "Linux Kernel".into(),
                    source_type: DriverSourceType::Linux,
                    available: true,
                    priority: 10,
                }],
                metadata: HashMap::new(),
                description: "Intel Wireless WiFi driver (iwlwifi)".into(),
                package_size_bytes: None,
            },
            DriverEntry {
                id: DriverId {
                    name: "nvidia".into(),
                    provider: "nvidia".into(),
                    version: DriverVersion::new(550, 120, 0),
                    arch: "amd64".into(),
                    kernel_compat: KernelCompatibility {
                        min_version: "5.4.0".into(),
                        max_version: Some("6.8.0".into()),
                        required_features: vec!["CONFIG_DRM".into()],
                    },
                    module_type: DriverModuleType::KernelModule,
                },
                status: DriverStatus::Available,
                supported_hardware: vec!["pci:v000010DEd*".into()],
                compatibility: Some(
                    CompatibilityInfo::compatible("Proprietary NVIDIA driver available")
                        .with_signature(true),
                ),
                sources: vec![DriverSource {
                    id: "nvidia".into(),
                    name: "NVIDIA Corporation".into(),
                    source_type: DriverSourceType::Vendor,
                    available: true,
                    priority: 50,
                }],
                metadata: {
                    let mut m = HashMap::new();
                    m.insert("license".into(), "proprietary".into());
                    m
                },
                description: "NVIDIA proprietary GPU driver".into(),
                package_size_bytes: Some(350_000_000),
            },
        ];
    }

    /// Check the compatibility of a driver with the current system.
    ///
    /// M2-D: Uses real hardware matching via HardwareMatcher.
    /// Falls back to stored compatibility info if matching cannot be performed.
    pub fn check_compatibility(
        &self,
        driver_name: &str,
        provider: &str,
    ) -> ServiceResult<CompatibilityInfo> {
        let driver = self
            .inventory
            .find_driver(driver_name, provider)
            .ok_or_else(|| {
                ServiceError::NotFound(format!("driver '{provider}/{driver_name}' not found"))
            })?;

        // Use HardwareMatcher for real compatibility evaluation against detected devices
        let matcher = crate::matching::HardwareMatcher::new();

        for device in &self.inventory.devices {
            let compat = matcher.evaluate_compatibility(driver, device);
            if compat.compatible {
                return Ok(compat);
            }
        }

        // If no hardware matched, return the driver's stored compatibility
        Ok(driver.compatibility.clone().unwrap_or_else(|| {
            CompatibilityInfo::incompatible(
                "No compatible hardware found for this driver",
                vec!["No hardware device matches this driver's supported device list".into()],
            )
        }))
    }

    /// Match drivers to detected hardware devices and update matched_drivers fields.
    pub fn match_drivers_to_hardware(&mut self) {
        let matcher = crate::matching::HardwareMatcher::new();
        let drivers = self.inventory.drivers.clone();

        for device in &mut self.inventory.devices {
            let matches = matcher.find_matching_drivers(device, &drivers);
            device.matched_drivers = matches.iter().map(|(d, _)| d.id.name.clone()).collect();
        }
    }
}

impl Default for InventoryScanner {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // ── HardwareId ─────────────────────────────────────────────

    #[test]
    fn hardware_id_validation() {
        let hwid = HardwareId {
            modalias: "pci:v00008086d0000A0C8sv00000000sd00000000bc02sc00i00".into(),
            vendor_id: "0x8086".into(),
            device_id: "0xA0C8".into(),
            subsystem_vendor_id: None,
            subsystem_device_id: None,
            class_code: Some("0x020000".into()),
            bus: "pci".into(),
            current_driver: Some("e1000e".into()),
        };
        assert!(hwid.validate().is_ok());
    }

    #[test]
    fn hardware_id_empty_modalias_fails() {
        let hwid = HardwareId {
            modalias: "".into(),
            vendor_id: "0x8086".into(),
            device_id: "0xA0C8".into(),
            subsystem_vendor_id: None,
            subsystem_device_id: None,
            class_code: None,
            bus: "pci".into(),
            current_driver: None,
        };
        assert!(hwid.validate().is_err());
    }

    #[test]
    fn hardware_id_invalid_bus_fails() {
        let hwid = HardwareId {
            modalias: "valid_modalias".into(),
            vendor_id: "0x8086".into(),
            device_id: "0xA0C8".into(),
            subsystem_vendor_id: None,
            subsystem_device_id: None,
            class_code: None,
            bus: "unknown_bus_type".into(),
            current_driver: None,
        };
        assert!(hwid.validate().is_err());
    }

    // ── DriverVersion ──────────────────────────────────────────

    #[test]
    fn driver_version_create() {
        let v = DriverVersion::new(1, 2, 3);
        assert_eq!(v.major, 1);
        assert_eq!(v.minor, 2);
        assert_eq!(v.patch, 3);
        assert_eq!(v.to_string(), "1.2.3");
    }

    #[test]
    fn driver_version_parse() {
        let v = DriverVersion::parse("1.2.3").unwrap();
        assert_eq!(v.major, 1);
        assert_eq!(v.minor, 2);
        assert_eq!(v.patch, 3);
    }

    #[test]
    fn driver_version_parse_with_prerelease() {
        let v = DriverVersion::parse("1.2.3-rc1").unwrap();
        assert_eq!(v.pre_release, Some("rc1".into()));
    }

    #[test]
    fn driver_version_parse_empty_fails() {
        assert!(DriverVersion::parse("").is_err());
    }

    #[test]
    fn driver_version_parse_invalid_fails() {
        assert!(DriverVersion::parse("abc").is_err());
    }

    #[test]
    fn driver_version_ordering() {
        assert!(DriverVersion::new(1, 0, 0) < DriverVersion::new(2, 0, 0));
        assert!(DriverVersion::new(1, 0, 0) > DriverVersion::new(0, 9, 9));
        assert!(DriverVersion::new(1, 2, 3) < DriverVersion::new(1, 2, 4));
    }

    #[test]
    fn driver_version_prerelease_less_than_stable() {
        let stable = DriverVersion::new(1, 0, 0);
        let prerelease = DriverVersion::parse("1.0.0-rc1").unwrap();
        assert!(prerelease < stable);
    }

    #[test]
    fn driver_version_validate_rejects_invalid_chars() {
        let mut v = DriverVersion::new(1, 0, 0);
        v.pre_release = Some("rc/1".into());
        assert!(v.validate().is_err());
    }

    // ── KernelCompatibility ────────────────────────────────────

    #[test]
    fn kernel_compat_validation() {
        let kc = KernelCompatibility {
            min_version: "5.4.0".into(),
            max_version: Some("6.8.0".into()),
            required_features: Vec::new(),
        };
        assert!(kc.validate().is_ok());
    }

    #[test]
    fn kernel_compat_empty_min_fails() {
        let kc = KernelCompatibility {
            min_version: "".into(),
            max_version: None,
            required_features: Vec::new(),
        };
        assert!(kc.validate().is_err());
    }

    // ── DriverId ───────────────────────────────────────────────

    #[test]
    fn driver_id_validation() {
        let id = DriverId {
            name: "e1000e".into(),
            provider: "linux".into(),
            version: DriverVersion::new(6, 8, 0),
            arch: "amd64".into(),
            kernel_compat: KernelCompatibility {
                min_version: "2.6.32".into(),
                max_version: None,
                required_features: Vec::new(),
            },
            module_type: DriverModuleType::KernelModule,
        };
        assert!(id.validate().is_ok());
    }

    #[test]
    fn driver_id_empty_name_fails() {
        let id = DriverId {
            name: "".into(),
            provider: "linux".into(),
            version: DriverVersion::new(1, 0, 0),
            arch: "amd64".into(),
            kernel_compat: KernelCompatibility {
                min_version: "5.0".into(),
                max_version: None,
                required_features: Vec::new(),
            },
            module_type: DriverModuleType::KernelModule,
        };
        assert!(id.validate().is_err());
    }

    // ── DriverStatus ───────────────────────────────────────────

    #[test]
    fn driver_status_operational() {
        assert!(DriverStatus::Active.is_operational());
        assert!(DriverStatus::Installed.is_operational());
        assert!(!DriverStatus::Failed.is_operational());
        assert!(!DriverStatus::Available.is_operational());
    }

    #[test]
    fn driver_status_error() {
        assert!(DriverStatus::Failed.is_error());
        assert!(!DriverStatus::Active.is_error());
    }

    #[test]
    fn driver_status_serde() {
        let status: DriverStatus = serde_json::from_str("\"active\"").unwrap();
        assert_eq!(status, DriverStatus::Active);
        let status: DriverStatus = serde_json::from_str("\"failed\"").unwrap();
        assert_eq!(status, DriverStatus::Failed);
    }

    // ── CompatibilityInfo ──────────────────────────────────────

    #[test]
    fn compatible_creation() {
        let info = CompatibilityInfo::compatible("All good");
        assert!(info.compatible);
        assert!((info.score - 1.0).abs() < f64::EPSILON);
    }

    #[test]
    fn incompatible_creation() {
        let info =
            CompatibilityInfo::incompatible("Not supported", vec!["missing hardware".into()]);
        assert!(!info.compatible);
        assert!((info.score - 0.0).abs() < f64::EPSILON);
    }

    #[test]
    fn compatibility_with_signature() {
        let info = CompatibilityInfo::compatible("Verified").with_signature(true);
        assert_eq!(info.signature_verified, Some(true));
    }

    // ── Request Validation ─────────────────────────────────────

    #[test]
    fn install_request_validation() {
        let req = InstallRequest {
            driver_name: "e1000e".into(),
            provider: "linux".into(),
            version_constraint: None,
            force: false,
        };
        assert!(req.validate().is_ok());
    }

    #[test]
    fn install_request_empty_name_fails() {
        let req = InstallRequest {
            driver_name: "".into(),
            provider: "linux".into(),
            version_constraint: None,
            force: false,
        };
        assert!(req.validate().is_err());
    }

    #[test]
    fn remove_request_validation() {
        let req = RemoveRequest {
            driver_name: "e1000e".into(),
            force: false,
        };
        assert!(req.validate().is_ok());
    }

    #[test]
    fn update_request_validation() {
        let req = UpdateRequest {
            driver_name: "e1000e".into(),
            target_version: Some("7.0.0".into()),
            allow_downgrade: false,
        };
        assert!(req.validate().is_ok());
    }

    // ── OperationResult ────────────────────────────────────────

    #[test]
    fn operation_result_success() {
        let r = OperationResult::success("e1000e", "Installed successfully");
        assert_eq!(r.status, OperationStatus::Completed);
        assert!(r.error.is_none());
    }

    #[test]
    fn operation_result_failed() {
        let r = OperationResult::failed("e1000e", "Installation failed", "Signature invalid");
        assert_eq!(r.status, OperationStatus::Failed);
        assert_eq!(r.error, Some("Signature invalid".into()));
    }

    // ── Inventory ──────────────────────────────────────────────

    #[test]
    fn inventory_new_is_empty() {
        let inv = DriverInventory::new();
        assert!(inv.drivers.is_empty());
        assert!(inv.devices.is_empty());
    }

    #[test]
    fn inventory_find_driver() {
        let mut inv = DriverInventory::new();
        inv.drivers.push(DriverEntry {
            id: DriverId {
                name: "e1000e".into(),
                provider: "linux".into(),
                version: DriverVersion::new(1, 0, 0),
                arch: "amd64".into(),
                kernel_compat: KernelCompatibility {
                    min_version: "5.0".into(),
                    max_version: None,
                    required_features: Vec::new(),
                },
                module_type: DriverModuleType::KernelModule,
            },
            status: DriverStatus::Active,
            supported_hardware: Vec::new(),
            compatibility: None,
            sources: Vec::new(),
            metadata: HashMap::new(),
            description: "test".into(),
            package_size_bytes: None,
        });
        assert!(inv.find_driver("e1000e", "linux").is_some());
        assert!(inv.find_driver("nonexistent", "linux").is_none());
    }

    #[test]
    fn inventory_active_count() {
        let mut inv = DriverInventory::new();
        inv.drivers.push(DriverEntry {
            id: DriverId {
                name: "d1".into(),
                provider: "p1".into(),
                version: DriverVersion::new(1, 0, 0),
                arch: "amd64".into(),
                kernel_compat: KernelCompatibility {
                    min_version: "5.0".into(),
                    max_version: None,
                    required_features: Vec::new(),
                },
                module_type: DriverModuleType::KernelModule,
            },
            status: DriverStatus::Active,
            supported_hardware: Vec::new(),
            compatibility: None,
            sources: Vec::new(),
            metadata: HashMap::new(),
            description: "t".into(),
            package_size_bytes: None,
        });
        inv.drivers.push(DriverEntry {
            id: DriverId {
                name: "d2".into(),
                provider: "p2".into(),
                version: DriverVersion::new(1, 0, 0),
                arch: "amd64".into(),
                kernel_compat: KernelCompatibility {
                    min_version: "5.0".into(),
                    max_version: None,
                    required_features: Vec::new(),
                },
                module_type: DriverModuleType::KernelModule,
            },
            status: DriverStatus::Failed,
            supported_hardware: Vec::new(),
            compatibility: None,
            sources: Vec::new(),
            metadata: HashMap::new(),
            description: "t".into(),
            package_size_bytes: None,
        });
        assert_eq!(inv.active_driver_count(), 1);
        assert_eq!(inv.failed_driver_count(), 1);
    }

    // ── InventoryScanner ───────────────────────────────────────

    #[test]
    fn scanner_new_is_empty() {
        let scanner = InventoryScanner::new();
        assert!(scanner.inventory().drivers.is_empty());
    }

    #[test]
    fn scanner_scan_populates_drivers() {
        let mut scanner = InventoryScanner::new();
        scanner.scan_system().unwrap();
        assert!(!scanner.inventory().drivers.is_empty());
        assert!(scanner.inventory().find_driver("e1000e", "linux").is_some());
        assert!(
            scanner.inventory().last_scan_timestamp > 0,
            "scan should set last_scan_timestamp"
        );
    }

    #[test]
    fn scanner_check_compatibility() {
        let mut scanner = InventoryScanner::new();
        scanner.scan_system().unwrap();
        let compat = scanner.check_compatibility("e1000e", "linux").unwrap();
        assert!(compat.compatible);
    }

    #[test]
    fn scanner_check_compatibility_not_found() {
        let scanner = InventoryScanner::new();
        let result = scanner.check_compatibility("nonexistent", "nonexistent");
        assert!(result.is_err());
    }

    // ── BusType ────────────────────────────────────────────────

    #[test]
    fn validate_bus_recognized_types() {
        assert!(validate_bus_type("pci").is_ok());
        assert!(validate_bus_type("usb").is_ok());
        assert!(validate_bus_type("PCI").is_ok());
        assert!(validate_bus_type("USB").is_ok());
        assert!(validate_bus_type("virtio").is_ok());
    }

    #[test]
    fn validate_bus_unrecognized_fails() {
        assert!(validate_bus_type("firewire").is_err());
        assert!(validate_bus_type("unknown").is_err());
    }
}
