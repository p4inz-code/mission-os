//! Hardware detection module for mission-driverd.
//!
//! Provides real Linux udev-based hardware enumeration via sysfs,
//! udev event monitoring, and safe cross-platform stubs.
//!
//! ## Architecture
//!
//! Per MOS-ENG-MOD-001 §3.6, mission-driverd is responsible for
//! hardware detection via udev integration. This module provides
//! the real backend for M2-D, replacing the M2-C stub.
//!
//! ## Linux Implementation
//!
//! On Linux, this module reads `/sys/bus/*/devices/` to enumerate
//! hardware devices, parsing uevent files for modalias, vendor,
//! device, and class information. No external commands are executed.
//!
//! ## Non-Linux Implementation
//!
//! On non-Linux platforms, a stub implementation returns empty
//! results, allowing clean compilation during Windows development.
//!
//! ## Security
//!
//! - No arbitrary command execution
//! - No shelling out to lspci/lsusb
//! - sysfs paths are validated before reading
//! - Malformed udev data is handled gracefully (logged, skipped)
//! - No panics from malformed hardware data

#[cfg(target_os = "linux")]
use crate::error::ServiceError;
use crate::error::ServiceResult;
#[cfg(target_os = "linux")]
use crate::inventory::BusType;
use crate::inventory::HardwareDevice;
#[cfg(target_os = "linux")]
use crate::inventory::HardwareId;
use std::collections::HashMap;
#[cfg(target_os = "linux")]
use std::path::Path;
#[cfg(target_os = "linux")]
use std::path::PathBuf;

// Allow dead_code for Linux-specific items (not compiled on Windows)
#[cfg(not(target_os = "linux"))]
#[allow(dead_code)]
const _: () = ();

// ── Constants ─────────────────────────────────────────────────────

/// Standard sysfs mount point.
#[cfg(target_os = "linux")]
const SYSFS_PATH: &str = "/sys";

/// Recognized bus subsystems to enumerate.
#[cfg(target_os = "linux")]
const BUS_SUBSYSTEMS: &[&str] = &["pci", "usb", "virtio", "i2c", "spi", "sdio"];

/// File name for uevent data within a device directory.
#[cfg(target_os = "linux")]
const UEVENT_FILE: &str = "uevent";

/// File name for modalias within a device directory.
#[cfg(target_os = "linux")]
const MODALIAS_FILE: &str = "modalias";

// ── Parsed Uevent Data ────────────────────────────────────────────

/// Parsed key-value pairs from a uevent file.
#[derive(Debug, Clone, Default)]
pub struct UeventData {
    /// Key-value pairs parsed from uevent.
    pub pairs: HashMap<String, String>,
}

#[allow(dead_code)]
impl UeventData {
    /// Parse uevent content from a string.
    fn parse(content: &str) -> Self {
        let mut pairs = HashMap::new();
        for line in content.lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            if let Some(eq_pos) = line.find('=') {
                let key = line[..eq_pos].trim().to_string();
                let value = line[eq_pos + 1..].trim().to_string();
                pairs.insert(key, value);
            }
        }
        Self { pairs }
    }

    /// Get a value by key.
    fn get(&self, key: &str) -> Option<&str> {
        self.pairs.get(key).map(|s| s.as_str())
    }
}

// ── Sysfs Device Reader ───────────────────────────────────────────

/// Reads hardware device information from sysfs.
///
/// On Linux, this provides real device enumeration. On other
/// platforms, it returns empty results.
pub struct SysfsReader;

impl SysfsReader {
    /// Enumerate all hardware devices from sysfs.
    ///
    /// Walks `/sys/bus/<subsystem>/devices/` for each recognized
    /// bus subsystem and collects device information.
    #[cfg(target_os = "linux")]
    pub fn enumerate_all() -> ServiceResult<Vec<HardwareDevice>> {
        let mut devices = Vec::new();

        for subsystem in BUS_SUBSYSTEMS {
            let devices_path = PathBuf::from(SYSFS_PATH)
                .join("bus")
                .join(subsystem)
                .join("devices");

            match Self::enumerate_subsystem(&devices_path, subsystem) {
                Ok(mut subsystem_devices) => {
                    devices.append(&mut subsystem_devices);
                }
                Err(ServiceError::BackendUnavailable(_)) => {
                    // Subsystem doesn't exist, skip silently
                }
                Err(e) => {
                    // Log but continue enumeration of other subsystems
                    eprintln!("[hwdetect] error enumerating {subsystem}: {e}");
                }
            }
        }

        Ok(devices)
    }

    /// Enumerate devices within a single subsystem directory.
    #[cfg(target_os = "linux")]
    fn enumerate_subsystem(
        devices_path: &Path,
        subsystem: &str,
    ) -> ServiceResult<Vec<HardwareDevice>> {
        let read_dir = match std::fs::read_dir(devices_path) {
            Ok(rd) => rd,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                return Err(ServiceError::BackendUnavailable(format!(
                    "subsystem {subsystem} not found"
                )));
            }
            Err(e) => {
                return Err(ServiceError::Internal(format!(
                    "cannot read {devices_path:?}: {e}"
                )));
            }
        };

        let mut devices = Vec::new();

        for entry in read_dir.flatten() {
            let device_path = entry.path();

            // Resolve symlink to real device path
            let real_path = match std::fs::canonicalize(&device_path) {
                Ok(p) => p,
                Err(_) => continue,
            };

            match Self::read_device(&real_path, subsystem) {
                Ok(Some(device)) => devices.push(device),
                Ok(None) => { /* skip devices without modalias */ }
                Err(e) => {
                    eprintln!(
                        "[hwdetect] error reading device {:?}: {e}",
                        real_path.file_name().unwrap_or_default()
                    );
                }
            }
        }

        Ok(devices)
    }

    /// Read a single hardware device from its sysfs directory.
    #[cfg(target_os = "linux")]
    fn read_device(sysfs_path: &Path, subsystem: &str) -> ServiceResult<Option<HardwareDevice>> {
        // Read modalias
        let modalias_path = sysfs_path.join(MODALIAS_FILE);
        let modalias = match std::fs::read_to_string(&modalias_path) {
            Ok(content) => content.trim().to_string(),
            Err(_) => return Ok(None), // No modalias = not a real device
        };

        if modalias.is_empty() {
            return Ok(None);
        }

        // Read uevent for additional metadata
        let uevent_path = sysfs_path.join(UEVENT_FILE);
        let uevent = std::fs::read_to_string(&uevent_path).ok();
        let uevent_data = uevent
            .as_ref()
            .map(|c| UeventData::parse(c))
            .unwrap_or_default();

        // Extract vendor ID from modalias or uevent
        let vendor_id = uevent_data
            .get("VENDOR_ID")
            .map(|s| s.to_string())
            .or_else(|| extract_vendor_from_modalias(&modalias))
            .unwrap_or_else(|| "unknown".into());

        // Extract device ID
        let device_id = uevent_data
            .get("DEVICE_ID")
            .map(|s| s.to_string())
            .or_else(|| extract_device_from_modalias(&modalias))
            .unwrap_or_else(|| "unknown".into());

        // Determine bus type
        let bus_type = match subsystem {
            "pci" => BusType::Pci,
            "usb" => BusType::Usb,
            "virtio" => BusType::Virtio,
            "i2c" => BusType::I2c,
            "spi" => BusType::Spi,
            "sdio" => BusType::Sdio,
            other => BusType::Other(other.to_string()),
        };

        // Get class code from uevent
        let class_code = uevent_data.get("PCI_CLASS").map(|s| s.to_string());

        // Get device name from uevent
        let device_name_fallback = sysfs_path
            .file_name()
            .map(|n| n.to_string_lossy().to_string());
        let device_name = uevent_data
            .get("DEVNAME")
            .or(uevent_data.get("DRIVER"))
            .or(device_name_fallback.as_deref())
            .unwrap_or("Unknown Device")
            .to_string();

        // Get vendor name from uevent or use generic
        let vendor_name = uevent_data.get("VENDOR").map(|s| s.to_string());

        // Get currently bound driver
        let driver_path = sysfs_path.join("driver");
        let current_driver = if driver_path.exists() {
            std::fs::canonicalize(&driver_path)
                .ok()
                .and_then(|p| p.file_name().map(|n| n.to_string_lossy().to_string()))
        } else {
            None
        };

        // Check if device is operational
        let operational = current_driver.is_some();

        // Validate that required fields are present
        let hardware_id = HardwareId {
            modalias: modalias.clone(),
            vendor_id,
            device_id,
            subsystem_vendor_id: uevent_data.get("SUBVENDOR_ID").map(|s| s.to_string()),
            subsystem_device_id: uevent_data.get("SUBDEVICE_ID").map(|s| s.to_string()),
            class_code,
            bus: subsystem.to_string(),
            current_driver: current_driver.clone(),
        };

        // Validate the hardware ID (skip if invalid)
        if let Err(e) = hardware_id.validate() {
            eprintln!("[hwdetect] skipping device with invalid hardware ID: {e}");
            return Ok(None);
        }

        Ok(Some(HardwareDevice {
            hardware_id,
            device_name,
            vendor_name,
            bus_type,
            bound_driver: current_driver,
            operational,
            matched_drivers: Vec::new(),
        }))
    }

    /// Stub implementation for non-Linux platforms.
    #[cfg(not(target_os = "linux"))]
    pub fn enumerate_all() -> ServiceResult<Vec<HardwareDevice>> {
        Ok(Vec::new())
    }
}

// ── Udev Event Monitor ────────────────────────────────────────────

/// A detected hardware event (add, remove, change).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum UdevEvent {
    /// A new device was added.
    DeviceAdded(HardwareDevice),
    /// A device was removed.
    DeviceRemoved(String), // modalias of removed device
    /// A device changed state.
    DeviceChanged(HardwareDevice),
}

/// Monitor for udev hardware events.
///
/// On Linux, polls sysfs directories for changes using file
/// modification timestamps (a safe, portable alternative to
/// netlink-based udev monitoring that doesn't require libudev).
///
/// On non-Linux, returns no events.
pub struct UdevMonitor {
    /// Timestamp of last poll per subsystem (for Linux).
    #[cfg(target_os = "linux")]
    last_poll: HashMap<String, u64>,
}

impl UdevMonitor {
    /// Create a new udev event monitor.
    pub fn new() -> Self {
        Self {
            #[cfg(target_os = "linux")]
            last_poll: HashMap::new(),
        }
    }

    /// Poll for hardware events since the last poll.
    ///
    /// Returns a list of detected events. May return empty vec
    /// even if events occurred (best-effort detection).
    ///
    /// This is a simplified polling approach. A full netlink-based
    /// udev monitor would require the `udev` crate. This approach
    /// avoids additional FFI dependencies.
    #[cfg(target_os = "linux")]
    pub fn poll_events(&mut self) -> Vec<UdevEvent> {
        let mut events = Vec::new();

        for subsystem in BUS_SUBSYSTEMS {
            let devices_path = PathBuf::from(SYSFS_PATH)
                .join("bus")
                .join(subsystem)
                .join("devices");

            let mtime = match sysfs_mtime(&devices_path) {
                Some(t) => t,
                None => continue,
            };

            let last = self.last_poll.get(*subsystem).copied().unwrap_or(0);

            if mtime > last {
                // Something changed — re-enumerate
                if let Ok(new_devices) = SysfsReader::enumerate_subsystem(&devices_path, subsystem)
                {
                    events.push(UdevEvent::DeviceChanged(
                        new_devices.first().cloned().unwrap_or_else(|| {
                            // A device was removed; we can't identify which one
                            // without tracking state, so skip
                            HardwareDevice {
                                hardware_id: HardwareId {
                                    modalias: String::new(),
                                    vendor_id: String::new(),
                                    device_id: String::new(),
                                    subsystem_vendor_id: None,
                                    subsystem_device_id: None,
                                    class_code: None,
                                    bus: subsystem.to_string(),
                                    current_driver: None,
                                },
                                device_name: String::new(),
                                vendor_name: None,
                                bus_type: match *subsystem {
                                    "pci" => BusType::Pci,
                                    "usb" => BusType::Usb,
                                    "virtio" => BusType::Virtio,
                                    "i2c" => BusType::I2c,
                                    "spi" => BusType::Spi,
                                    "sdio" => BusType::Sdio,
                                    _ => BusType::Other((*subsystem).to_string()),
                                },
                                bound_driver: None,
                                operational: false,
                                matched_drivers: Vec::new(),
                            }
                        }),
                    ));
                }
            }

            self.last_poll.insert((*subsystem).to_string(), mtime);
        }

        events
    }

    /// Stub implementation for non-Linux platforms.
    #[cfg(not(target_os = "linux"))]
    pub fn poll_events(&mut self) -> Vec<UdevEvent> {
        Vec::new()
    }
}

impl Default for UdevMonitor {
    fn default() -> Self {
        Self::new()
    }
}

// ── Modalias Parsing Helpers ──────────────────────────────────────

#[allow(dead_code)]
/// Extract vendor ID from a modalias string.
///
/// PCI modalias format: `pci:v00008086d0000A0C8sv...`
/// USB modalias format: `usb:v1234p5678...`
fn extract_vendor_from_modalias(modalias: &str) -> Option<String> {
    // Check for PCI-style v0000XXXX first (skip the v0000 prefix, 5 chars)
    if let Some(v_start) = modalias.find("v0000") {
        let rest = &modalias[v_start..];
        if rest.len() >= 9 {
            let vendor = &rest[5..9];
            if vendor.chars().all(|c| c.is_ascii_hexdigit()) {
                return Some(format!("0x{}", vendor));
            }
        }
        // Edge case: short match like "v0000" with nothing after
        return Some("0x0000".into());
    }
    // USB-style: "v" followed by 4 hex digits
    if let Some(v_start) = modalias.find('v') {
        let rest = &modalias[v_start + 1..];
        if rest.len() >= 4 {
            let vendor = &rest[..4];
            if vendor.chars().all(|c| c.is_ascii_hexdigit()) {
                return Some(format!("0x{vendor}"));
            }
        }
    }
    None
}

#[allow(dead_code)]
/// Extract device ID from a modalias string.
///
/// PCI modalias format: `pci:v00008086d0000A0C8sv...`
/// USB modalias format: `usb:v1234p5678...`
fn extract_device_from_modalias(modalias: &str) -> Option<String> {
    if let Some(d_start) = modalias.find("d0000") {
        // PCI device is 4 hex digits after "d0000" (skip 5 chars)
        if modalias.len() >= d_start + 9 {
            let device = &modalias[d_start + 5..d_start + 9];
            return Some(format!("0x{}", device));
        }
        None
    } else if let Some(p_start) = modalias.find('p') {
        // USB-like: "p" followed by 4 hex digits
        let rest = &modalias[p_start + 1..];
        if rest.len() >= 4 {
            let device = &rest[..4];
            if device.chars().all(|c| c.is_ascii_hexdigit()) {
                return Some(format!("0x{device}"));
            }
        }
        None
    } else {
        None
    }
}

// ── Sysfs Utilities ───────────────────────────────────────────────

/// Get the modification time of a sysfs directory (used for change detection).
#[cfg(target_os = "linux")]
fn sysfs_mtime(path: &Path) -> Option<u64> {
    let metadata = std::fs::metadata(path).ok()?;
    let modified = metadata.modified().ok()?;
    Some(
        modified
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    // ── UeventData Parsing ─────────────────────────────────────

    #[test]
    fn uevent_parses_simple() {
        let content = "VENDOR_ID=0x8086\nDEVICE_ID=0xA0C8\nPCI_CLASS=0x020000\n";
        let data = UeventData::parse(content);
        assert_eq!(data.get("VENDOR_ID"), Some("0x8086"));
        assert_eq!(data.get("DEVICE_ID"), Some("0xA0C8"));
        assert_eq!(data.get("PCI_CLASS"), Some("0x020000"));
    }

    #[test]
    fn uevent_skips_comments_and_blanks() {
        let content = "# This is a comment\n\nVENDOR_ID=0x8086\n\n# Another comment\n";
        let data = UeventData::parse(content);
        assert_eq!(data.get("VENDOR_ID"), Some("0x8086"));
        assert!(data.get("DEVICE_ID").is_none());
    }

    #[test]
    fn uevent_empty_returns_no_data() {
        let data = UeventData::parse("");
        assert!(data.pairs.is_empty());
    }

    #[test]
    fn uevent_whitespace_handling() {
        let content = "  VENDOR_ID  =  0x8086  \nDEVICE_ID=0xA0C8\n";
        let data = UeventData::parse(content);
        assert_eq!(data.get("VENDOR_ID"), Some("0x8086"));
    }

    // ── Modalias Parsing ────────────────────────────────────────

    #[test]
    fn extract_vendor_from_pci_modalias() {
        let modalias = "pci:v00008086d0000A0C8sv00000000sd00000000bc02sc00i00";
        assert_eq!(
            extract_vendor_from_modalias(modalias),
            Some("0x8086".into())
        );
    }

    #[test]
    fn extract_device_from_pci_modalias() {
        let modalias = "pci:v00008086d0000A0C8sv00000000sd00000000bc02sc00i00";
        assert_eq!(
            extract_device_from_modalias(modalias),
            Some("0xA0C8".into())
        );
    }

    #[test]
    fn extract_vendor_from_usb_modalias() {
        let modalias = "usb:v1234p5678d0001dc00sc00ip00";
        assert_eq!(
            extract_vendor_from_modalias(modalias),
            Some("0x1234".into())
        );
    }

    #[test]
    fn extract_device_from_usb_modalias() {
        let modalias = "usb:v1234p5678d0001dc00sc00ip00";
        assert_eq!(
            extract_device_from_modalias(modalias),
            Some("0x5678".into())
        );
    }

    #[test]
    fn extract_vendor_from_empty_modalias() {
        assert_eq!(extract_vendor_from_modalias(""), None);
    }

    #[test]
    fn extract_vendor_from_unknown_format() {
        assert_eq!(extract_vendor_from_modalias("acpi:XXXXX"), None);
    }

    // ── SysfsReader (stub tests) ────────────────────────────────

    #[test]
    fn sysfs_reader_enumerate_does_not_panic() {
        // Should always return Ok, even on non-Linux
        let result = SysfsReader::enumerate_all();
        assert!(result.is_ok());
    }

    // ── UdevMonitor ─────────────────────────────────────────────

    #[test]
    fn udev_monitor_new() {
        let mut monitor = UdevMonitor::new();
        let _events = monitor.poll_events();
        // Should not panic — on Linux, may return real hardware events
        // On non-Linux, the stub returns empty
        #[cfg(not(target_os = "linux"))]
        assert!(_events.is_empty());
    }

    #[test]
    fn udev_monitor_multiple_polls() {
        let mut monitor = UdevMonitor::new();
        let _ = monitor.poll_events();
        let _ = monitor.poll_events();
        // Multiple polls should not panic
    }

    // ── Edge Cases ──────────────────────────────────────────────

    #[test]
    fn uevent_malformed_line() {
        let content = "VENDOR_ID=0x8086\nNO_EQUALS\nDEVICE_ID=0xA0C8\n";
        let data = UeventData::parse(content);
        assert_eq!(data.get("VENDOR_ID"), Some("0x8086"));
        assert_eq!(data.get("DEVICE_ID"), Some("0xA0C8"));
        // Line without '=' should be skipped
    }

    #[test]
    fn extract_vendor_edge_cases() {
        assert_eq!(
            extract_vendor_from_modalias("pci:v0000"),
            Some("0x0000".into())
        );
        // v0000abcd — 4 hex digits after the prefix are "abcd"
        assert_eq!(
            extract_vendor_from_modalias("pci:v0000abcd"),
            Some("0xabcd".into())
        );
    }
}
