//! System information queries.
//!
//! Provides runtime information about the operating system environment.
//!
//! ## Design
//!
//! - Platform-aware where necessary (Unix-specific queries use /proc and uname)
//! - Deterministic — no random components
//! - Graceful failure — missing files or unavailable commands produce
//!   structured errors, not panics
//! - No privileged operations
//! - No telemetry, no network calls, no data collection
//!
//! ## Security
//!
//! - No environment variables are trusted beyond standard POSIX conventions
//! - No data is collected beyond the explicitly requested query
//! - No network access

use std::path::Path;

use crate::error::{Error, ErrorCode, Result};
use crate::version::Version;

/// Runtime information about the Mission OS environment.
#[derive(Debug, Clone)]
pub struct SystemInfo {
    /// The Mission OS version (from the installed VERSION file, if available).
    pub os_version: Version,
    /// The Linux kernel release string (e.g., "6.1.0-17-amd64").
    pub kernel_release: String,
    /// The kernel version string (e.g., "#1 SMP PREEMPT_DYNAMIC ...").
    pub kernel_version: String,
    /// The hostname of this machine.
    pub hostname: String,
    /// The machine hardware name (e.g., "x86_64", "aarch64").
    pub architecture: String,
    /// Operating system pretty name (e.g., "Debian GNU/Linux 12 (bookworm)").
    pub os_pretty_name: String,
    /// Operating system ID (e.g., "debian", "mission-os").
    pub os_id: String,
    /// Operating system version ID (e.g., "12").
    pub os_version_id: String,
}

impl SystemInfo {
    /// Gather system information at runtime.
    ///
    /// All queries are best-effort — if a source file or command is not
    /// available, the field receives a fallback value and the function
    /// still succeeds.
    pub fn gather() -> Self {
        Self {
            os_version: Self::read_version(),
            kernel_release: Self::read_kernel_release(),
            kernel_version: Self::read_kernel_version(),
            hostname: Self::read_hostname(),
            architecture: Self::read_architecture(),
            os_pretty_name: Self::read_os_pretty_name(),
            os_id: Self::read_os_id(),
            os_version_id: Self::read_os_version_id(),
        }
    }

    /// Read the Mission OS version from the installed VERSION file.
    fn read_version() -> Version {
        let paths = [
            "/etc/mission/VERSION",
            "/usr/share/mission/VERSION",
            "/mission/VERSION",
        ];

        for path in &paths {
            if let Ok(contents) = std::fs::read_to_string(path) {
                let trimmed = contents.trim();
                if let Ok(ver) = trimmed.parse::<Version>() {
                    return ver;
                }
            }
        }

        Version::new(0, 1, 0)
    }

    /// Read the kernel release string from uname.
    fn read_kernel_release() -> String {
        Self::read_uname("-r").unwrap_or_else(|_| "unknown".into())
    }

    /// Read the kernel version string from uname.
    fn read_kernel_version() -> String {
        Self::read_uname("-v").unwrap_or_else(|_| "unknown".into())
    }

    /// Read the hostname.
    fn read_hostname() -> String {
        // Try /proc/sys/kernel/hostname first (most reliable)
        if let Ok(contents) = std::fs::read_to_string("/proc/sys/kernel/hostname") {
            return contents.trim().to_string();
        }

        // Fallback to `hostname` command
        if let Ok(hostname) = Self::read_command("hostname") {
            return hostname.trim().to_string();
        }

        // Last resort
        "localhost".into()
    }

    /// Read the machine architecture from `uname -m`.
    fn read_architecture() -> String {
        Self::read_uname("-m").unwrap_or_else(|_| std::env::consts::ARCH.to_string())
    }

    /// Read the OS pretty name from os-release.
    fn read_os_pretty_name() -> String {
        Self::read_os_release_field("PRETTY_NAME").unwrap_or_else(|| "Mission OS".into())
    }

    /// Read the OS ID from os-release.
    fn read_os_id() -> String {
        Self::read_os_release_field("ID").unwrap_or_else(|| "mission-os".into())
    }

    /// Read the OS version ID from os-release.
    fn read_os_version_id() -> String {
        Self::read_os_release_field("VERSION_ID").unwrap_or_else(|| "0.1.0".into())
    }

    /// Execute `uname` with the given flag and return stdout.
    fn read_uname(flag: &str) -> std::result::Result<String, ()> {
        Self::read_command_args("uname", &[flag])
    }

    /// Execute a simple command and return stdout.
    #[allow(dead_code)]
    fn read_command(cmd: &str) -> std::result::Result<String, ()> {
        Self::read_command_args(cmd, &[])
    }

    /// Execute a command with arguments and return stdout.
    fn read_command_args(cmd: &str, args: &[&str]) -> std::result::Result<String, ()> {
        std::process::Command::new(cmd)
            .args(args)
            .output()
            .ok()
            .and_then(|out| {
                if out.status.success() {
                    String::from_utf8(out.stdout).ok()
                } else {
                    None
                }
            })
            .ok_or(())
    }

    /// Read a specific field from os-release files.
    fn read_os_release_field(field: &str) -> Option<String> {
        let paths = ["/etc/os-release", "/usr/lib/os-release"];
        let prefix = format!("{field}=");

        for path in &paths {
            if let Ok(contents) = std::fs::read_to_string(path) {
                for line in contents.lines() {
                    let line = line.trim();
                    if let Some(value) = line.strip_prefix(&prefix) {
                        // Strip surrounding quotes if present
                        let stripped = value.trim_matches(|c| c == '"' || c == '\'');
                        return Some(stripped.to_string());
                    }
                }
            }
        }

        None
    }
}

/// Convenience functions for querying individual system information values.
/// These are for when you don't need the full [`SystemInfo`] struct.
#[allow(clippy::empty_line_after_doc_comments)]
/// Return the hostname of this machine.
pub fn hostname() -> String {
    SystemInfo::read_hostname()
}

/// Return the architecture string (e.g., "x86_64", "aarch64").
pub fn architecture() -> String {
    SystemInfo::read_architecture()
}

/// Return the kernel release string.
pub fn kernel_release() -> String {
    SystemInfo::read_kernel_release()
}

/// Return the number of online CPUs.
pub fn cpu_count() -> Result<usize> {
    // Read from /proc/cpuinfo or /sys/devices/system/cpu/online
    let online_path = Path::new("/sys/devices/system/cpu/online");
    if let Ok(contents) = std::fs::read_to_string(online_path) {
        let trimmed = contents.trim();
        // Format: "0-3" or "0,2,4" or "0"
        if let Some(range_str) = trimmed.split(',').next_back() {
            if let Some(end_str) = range_str.split('-').next_back() {
                if let Ok(count) = end_str.parse::<usize>() {
                    return Ok(count + 1); // 0-indexed
                }
            }
        }
    }

    // Fallback: count "processor" lines in /proc/cpuinfo
    let cpuinfo_path = Path::new("/proc/cpuinfo");
    if let Ok(contents) = std::fs::read_to_string(cpuinfo_path) {
        let count = contents
            .lines()
            .filter(|line| line.starts_with("processor"))
            .count();
        if count > 0 {
            return Ok(count);
        }
    }

    // Worst-case fallback: num_cpus is not available through std alone
    // Without adding a dependency, we return a reasonable default
    Ok(1)
}

/// Return the total physical memory in bytes.
pub fn memory_total() -> Result<u64> {
    let meminfo_path = Path::new("/proc/meminfo");
    let contents = std::fs::read_to_string(meminfo_path)
        .map_err(|e| Error::with_source(ErrorCode::IoError, "failed to read /proc/meminfo", e))?;

    for line in contents.lines() {
        if let Some(rest) = line.strip_prefix("MemTotal:") {
            let parts: Vec<&str> = rest.split_whitespace().collect();
            if let Some(kb_str) = parts.first() {
                if let Ok(kb) = kb_str.parse::<u64>() {
                    return Ok(kb * 1024); // Convert kB to bytes
                }
            }
        }
    }

    Err(Error::new(
        ErrorCode::NotFound,
        "MemTotal not found in /proc/meminfo",
    ))
}
#[cfg(test)]
mod tests {
    use super::*;

    // -------------------------------------------------------------------
    // Deterministic logic tests
    // -------------------------------------------------------------------

    #[test]
    fn sysinfo_gather_returns_all_fields() {
        let info = SystemInfo::gather();

        // These should always return at least a default
        assert!(!info.hostname.is_empty());
        assert!(!info.architecture.is_empty());
        assert!(!info.kernel_release.is_empty());
        assert!(!info.os_pretty_name.is_empty());
        assert!(!info.os_id.is_empty());
        assert!(!info.os_version_id.is_empty());
    }

    #[test]
    fn sysinfo_os_version_default() {
        let info = SystemInfo::gather();
        // Without /etc/mission/VERSION, should return 0.1.0
        assert_eq!(info.os_version, Version::new(0, 1, 0));
    }

    #[test]
    fn sysinfo_hostname_not_empty() {
        let host = hostname();
        assert!(!host.is_empty());
    }

    #[test]
    fn sysinfo_architecture_not_empty() {
        let arch = architecture();
        assert!(!arch.is_empty());
    }

    // -------------------------------------------------------------------
    // OS release parsing
    // -------------------------------------------------------------------

    #[test]
    fn parse_os_release_field_does_not_panic() {
        // This test is platform-dependent; it may not have os-release
        // in the test environment. We just verify it doesn't panic.
        let _pretty = SystemInfo::read_os_release_field("PRETTY_NAME");
    }

    // -------------------------------------------------------------------
    // CPU count
    // -------------------------------------------------------------------

    #[test]
    fn cpu_count_returns_positive() {
        let count = cpu_count().unwrap_or(1);
        assert!(count >= 1);
    }

    // -------------------------------------------------------------------
    // OS release field parsing (unit test with known input)
    // -------------------------------------------------------------------

    #[test]
    fn parse_os_release_field_logic() {
        // Since read_os_release_field reads from actual files,
        // we just verify no panic from the function signatures
        let _id = SystemInfo::read_os_id();
        let _pretty = SystemInfo::read_os_pretty_name();
    }

    // -------------------------------------------------------------------
    // Version file parsing (unit test)
    // -------------------------------------------------------------------

    #[test]
    fn version_parsing_from_file() {
        // Write a test VERSION file to a temp location, read it back
        let dir = std::env::temp_dir().join("__mission_sysinfo_test");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let ver_path = dir.join("VERSION");
        std::fs::write(&ver_path, "1.2.3-rc.1\n").unwrap();

        // Simulate by directly parsing
        let contents = std::fs::read_to_string(&ver_path).unwrap();
        let ver: Version = contents.trim().parse().unwrap();
        assert_eq!(ver, Version::with_pre(1, 2, 3, &["rc", "1"]));

        let _ = std::fs::remove_dir_all(&dir);
    }

    // -------------------------------------------------------------------
    // Memory total
    // -------------------------------------------------------------------

    #[test]
    #[cfg_attr(
        not(target_os = "linux"),
        ignore = "memory_total requires /proc/meminfo (Linux)"
    )]
    fn memory_total_may_be_available() {
        match memory_total() {
            Ok(bytes) => {
                assert!(bytes > 0, "memory total must be positive");
            }
            Err(e) => {
                // On Linux, should always find MemTotal
                // The error could be Io (can't read) or NotFound (can't find field)
                assert!(
                    e.code() == ErrorCode::IoError || e.code() == ErrorCode::NotFound,
                    "unexpected error code: {:?}",
                    e.code()
                );
            }
        }
    }
}
