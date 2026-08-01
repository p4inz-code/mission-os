//! Semantic version representation for Mission OS releases.
//!
//! Provides a well-defined semantic version type with deterministic
//! parsing, correct comparison, and structured error reporting.

use core::fmt;
use std::str::FromStr;

use serde::{Deserialize, Serialize};

/// Error returned when parsing a version string fails.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VersionParseError {
    input: String,
    kind: VersionParseErrorKind,
}

impl VersionParseError {
    /// The invalid input string.
    pub fn input(&self) -> &str {
        &self.input
    }

    /// The kind of parse failure.
    pub fn kind(&self) -> &VersionParseErrorKind {
        &self.kind
    }
}

impl fmt::Display for VersionParseError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self.kind {
            VersionParseErrorKind::Empty => write!(f, "version string is empty"),
            VersionParseErrorKind::MissingComponent => {
                write!(f, "version string is missing components: '{}'", self.input)
            }
            VersionParseErrorKind::InvalidMajor(ref e) => {
                write!(
                    f,
                    "invalid major version component: {e} in '{}'",
                    self.input
                )
            }
            VersionParseErrorKind::InvalidMinor(ref e) => {
                write!(
                    f,
                    "invalid minor version component: {e} in '{}'",
                    self.input
                )
            }
            VersionParseErrorKind::InvalidPatch(ref e) => {
                write!(
                    f,
                    "invalid patch version component: {e} in '{}'",
                    self.input
                )
            }
            VersionParseErrorKind::InvalidPrerelease(ref s) => {
                write!(
                    f,
                    "invalid pre-release identifier '{s}' in '{}'",
                    self.input
                )
            }
            VersionParseErrorKind::TrailingInput(ref s) => {
                write!(
                    f,
                    "unexpected trailing input '{s}' after version in '{}'",
                    self.input
                )
            }
        }
    }
}

impl std::error::Error for VersionParseError {}

/// Specific kind of version parse failure.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum VersionParseErrorKind {
    /// Input string was empty.
    Empty,
    /// Missing version component (e.g., "1." instead of "1.0.0").
    MissingComponent,
    /// Invalid major version number.
    InvalidMajor(String),
    /// Invalid minor version number.
    InvalidMinor(String),
    /// Invalid patch version number.
    InvalidPatch(String),
    /// Invalid pre-release identifier.
    InvalidPrerelease(String),
    /// Unexpected characters after valid version.
    TrailingInput(String),
}

/// A semantic version for Mission OS releases.
///
/// Follows the semver 2.0 specification for the core major.minor.pattern
/// representation. Pre-release and build metadata are supported for
/// development and staging releases.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Version {
    major: u64,
    minor: u64,
    patch: u64,
    /// Pre-release identifiers (e.g., "alpha.1", "rc.2").
    /// Empty means this is a stable release.
    pre: Vec<String>,
    /// Build metadata (e.g., "build.20260729").
    /// Empty means no build metadata.
    build: Vec<String>,
}

impl Version {
    /// Create a new `Version` without pre-release or build metadata.
    pub const fn new(major: u64, minor: u64, patch: u64) -> Self {
        Self {
            major,
            minor,
            patch,
            pre: Vec::new(),
            build: Vec::new(),
        }
    }

    /// Create a new `Version` with a pre-release tag.
    pub fn with_pre(major: u64, minor: u64, patch: u64, pre: &[&str]) -> Self {
        Self {
            major,
            minor,
            patch,
            pre: pre.iter().map(|s| s.to_string()).collect(),
            build: Vec::new(),
        }
    }

    /// Create a new `Version` with pre-release and build metadata.
    pub fn with_build(major: u64, minor: u64, patch: u64, build: &[&str]) -> Self {
        Self {
            major,
            minor,
            patch,
            pre: Vec::new(),
            build: build.iter().map(|s| s.to_string()).collect(),
        }
    }

    /// Create a new `Version` with both pre-release and build metadata.
    pub fn full(major: u64, minor: u64, patch: u64, pre: &[&str], build: &[&str]) -> Self {
        Self {
            major,
            minor,
            patch,
            pre: pre.iter().map(|s| s.to_string()).collect(),
            build: build.iter().map(|s| s.to_string()).collect(),
        }
    }

    /// Return the major version component.
    pub const fn major(&self) -> u64 {
        self.major
    }

    /// Return the minor version component.
    pub const fn minor(&self) -> u64 {
        self.minor
    }

    /// Return the patch version component.
    pub const fn patch(&self) -> u64 {
        self.patch
    }

    /// Return the pre-release identifiers, if any.
    pub fn pre(&self) -> &[String] {
        &self.pre
    }

    /// Return the build metadata identifiers, if any.
    pub fn build(&self) -> &[String] {
        &self.build
    }

    /// Is this a stable release (no pre-release tag)?
    pub fn is_stable(&self) -> bool {
        self.pre.is_empty()
    }

    /// Parse a version string strictly, returning a structured error on failure.
    pub fn parse(input: &str) -> Result<Self, VersionParseError> {
        if input.is_empty() {
            return Err(VersionParseError {
                input: input.to_string(),
                kind: VersionParseErrorKind::Empty,
            });
        }

        // Split off build metadata after '+'
        let (core, build) = if let Some(plus_idx) = input.find('+') {
            let (left, right) = input.split_at(plus_idx);
            let build_str = &right[1..]; // skip '+'
            if build_str.is_empty() {
                (left, Vec::new())
            } else {
                let ids: Vec<String> = build_str.split('.').map(|s| s.to_string()).collect();
                (left, ids)
            }
        } else {
            (input, Vec::new())
        };

        // Split off pre-release after '-'
        let (numeric, pre) = if let Some(dash_idx) = core.find('-') {
            let (left, right) = core.split_at(dash_idx);
            let pre_str = &right[1..]; // skip '-'
            if pre_str.is_empty() {
                (left, Vec::new())
            } else {
                let ids: Vec<String> = pre_str.split('.').map(|s| s.to_string()).collect();
                (left, ids)
            }
        } else {
            (core, Vec::new())
        };

        // Parse numeric components
        let parts: Vec<&str> = numeric.split('.').collect();
        if parts.len() < 3 {
            return Err(VersionParseError {
                input: input.to_string(),
                kind: VersionParseErrorKind::MissingComponent,
            });
        }

        if parts.len() > 3 {
            return Err(VersionParseError {
                input: input.to_string(),
                kind: VersionParseErrorKind::TrailingInput(parts[3..].join(".")),
            });
        }

        let major = parts[0].parse::<u64>().map_err(|e| VersionParseError {
            input: input.to_string(),
            kind: VersionParseErrorKind::InvalidMajor(e.to_string()),
        })?;

        let minor = parts[1].parse::<u64>().map_err(|e| VersionParseError {
            input: input.to_string(),
            kind: VersionParseErrorKind::InvalidMinor(e.to_string()),
        })?;

        let patch = parts[2].parse::<u64>().map_err(|e| VersionParseError {
            input: input.to_string(),
            kind: VersionParseErrorKind::InvalidPatch(e.to_string()),
        })?;

        Ok(Self {
            major,
            minor,
            patch,
            pre,
            build,
        })
    }
}

impl FromStr for Version {
    type Err = VersionParseError;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        Version::parse(s)
    }
}

impl fmt::Display for Version {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}.{}.{}", self.major, self.minor, self.patch)?;
        if !self.pre.is_empty() {
            write!(f, "-{}", self.pre.join("."))?;
        }
        if !self.build.is_empty() {
            write!(f, "+{}", self.build.join("."))?;
        }
        Ok(())
    }
}

/// Correct semver 2.0 comparison.
///
/// Pre-release versions have lower precedence than the associated
/// normal version. A version with a pre-release tag is always
/// less than a version without one (same major.minor.patch).
impl PartialOrd for Version {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for Version {
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

        // No pre-release on either: equal
        match (self.pre.is_empty(), other.pre.is_empty()) {
            (true, true) => std::cmp::Ordering::Equal,
            // Stable > pre-release
            (true, false) => std::cmp::Ordering::Greater,
            // Pre-release < stable
            (false, true) => std::cmp::Ordering::Less,
            // Both have pre-release: compare lexicographically
            (false, false) => compare_pre_release(&self.pre, &other.pre),
        }
    }
}

/// Compare pre-release identifiers per semver 2.0 §11.
fn compare_pre_release(a: &[String], b: &[String]) -> std::cmp::Ordering {
    let min_len = a.len().min(b.len());
    for i in 0..min_len {
        let ord = compare_pre_release_id(&a[i], &b[i]);
        if ord != std::cmp::Ordering::Equal {
            return ord;
        }
    }
    a.len().cmp(&b.len())
}

/// Compare two pre-release identifiers (numeric vs string per semver).
fn compare_pre_release_id(a: &str, b: &str) -> std::cmp::Ordering {
    match (a.parse::<u64>(), b.parse::<u64>()) {
        (Ok(an), Ok(bn)) => an.cmp(&bn),
        // Numeric < ASCII (per semver 2.0)
        (Ok(_), Err(_)) => std::cmp::Ordering::Less,
        (Err(_), Ok(_)) => std::cmp::Ordering::Greater,
        (Err(_), Err(_)) => a.cmp(b),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // -------------------------------------------------------------------
    // Construction
    // -------------------------------------------------------------------

    #[test]
    fn version_construction() {
        let v = Version::new(0, 1, 0);
        assert_eq!(v.major(), 0);
        assert_eq!(v.minor(), 1);
        assert_eq!(v.patch(), 0);
        assert!(v.pre().is_empty());
        assert!(v.build().is_empty());
        assert!(v.is_stable());
    }

    #[test]
    fn version_with_pre_release() {
        let v = Version::with_pre(1, 0, 0, &["alpha", "1"]);
        assert_eq!(v.to_string(), "1.0.0-alpha.1");
        assert!(!v.is_stable());
    }

    #[test]
    fn version_with_build_metadata() {
        let v = Version::with_build(1, 0, 0, &["20260729"]);
        assert_eq!(v.to_string(), "1.0.0+20260729");
    }

    #[test]
    fn version_with_pre_and_build() {
        let v = Version::full(2, 3, 1, &["rc", "2"], &["build", "42"]);
        assert_eq!(v.to_string(), "2.3.1-rc.2+build.42");
    }

    // -------------------------------------------------------------------
    // Display
    // -------------------------------------------------------------------

    #[test]
    fn version_display_stable() {
        let v = Version::new(1, 2, 3);
        assert_eq!(v.to_string(), "1.2.3");
    }

    #[test]
    fn version_display_zero() {
        let v = Version::new(0, 0, 0);
        assert_eq!(v.to_string(), "0.0.0");
    }

    // -------------------------------------------------------------------
    // Parsing -- valid
    // -------------------------------------------------------------------

    #[test]
    fn parse_stable() {
        let v = "1.2.3".parse::<Version>().unwrap();
        assert_eq!(v.major(), 1);
        assert_eq!(v.minor(), 2);
        assert_eq!(v.patch(), 3);
    }

    #[test]
    fn parse_with_prerelease() {
        let v = "1.0.0-alpha.1".parse::<Version>().unwrap();
        assert_eq!(v.major(), 1);
        assert_eq!(v.pre(), &["alpha", "1"]);
    }

    #[test]
    fn parse_with_build() {
        let v = "2.0.0+build.42".parse::<Version>().unwrap();
        assert_eq!(v.build(), &["build", "42"]);
    }

    #[test]
    fn parse_with_prerelease_and_build() {
        let v = "0.9.0-rc.1+exp.sha.5114f85".parse::<Version>().unwrap();
        assert_eq!(v.pre(), &["rc", "1"]);
        assert_eq!(v.build(), &["exp", "sha", "5114f85"]);
    }

    #[test]
    fn parse_large_numbers() {
        let v = "999999.999999.999999".parse::<Version>().unwrap();
        assert_eq!(v.major(), 999999);
        assert_eq!(v.minor(), 999999);
        assert_eq!(v.patch(), 999999);
    }

    #[test]
    fn parse_zero() {
        let v = "0.0.0".parse::<Version>().unwrap();
        assert_eq!(v, Version::new(0, 0, 0));
    }

    // -------------------------------------------------------------------
    // Parsing -- invalid
    // -------------------------------------------------------------------

    #[test]
    fn parse_empty_fails() {
        let result = "".parse::<Version>();
        assert!(result.is_err());
        assert_eq!(*result.unwrap_err().kind(), VersionParseErrorKind::Empty);
    }

    #[test]
    fn parse_missing_component_fails() {
        let result = "1.2".parse::<Version>();
        assert!(result.is_err());
        assert_eq!(
            *result.unwrap_err().kind(),
            VersionParseErrorKind::MissingComponent
        );
    }

    #[test]
    fn parse_single_component_fails() {
        let result = "1".parse::<Version>();
        assert!(result.is_err());
    }

    #[test]
    fn parse_non_numeric_major_fails() {
        let result = "abc.1.0".parse::<Version>();
        assert!(result.is_err());
    }

    #[test]
    fn parse_negative_major_fails() {
        let result = "-1.0.0".parse::<Version>();
        assert!(result.is_err());
    }

    #[test]
    fn parse_trailing_dot_version_fails() {
        let result = "1.2.3.".parse::<Version>();
        // The trailing dot would cause split to produce ["1", "2", "3", ""]
        // which is > 3 parts
        assert!(result.is_err());
    }

    // -------------------------------------------------------------------
    // Comparison
    // -------------------------------------------------------------------

    #[test]
    fn version_ordering() {
        assert!(Version::new(0, 9, 0) < Version::new(1, 0, 0));
        assert!(Version::new(1, 0, 0) > Version::new(0, 9, 0));
        assert!(Version::new(1, 0, 0) > Version::new(0, 99, 99));
    }

    #[test]
    fn version_equality() {
        assert_eq!(Version::new(0, 1, 0), Version::new(0, 1, 0));
        assert_ne!(Version::new(1, 0, 0), Version::new(0, 1, 0));
    }

    #[test]
    fn stable_greater_than_prerelease() {
        let stable = Version::new(1, 0, 0);
        let prerelease = Version::with_pre(1, 0, 0, &["rc", "1"]);
        assert!(stable > prerelease);
        assert!(prerelease < stable);
    }

    #[test]
    fn prerelease_ordering() {
        let alpha = Version::with_pre(1, 0, 0, &["alpha"]);
        let beta = Version::with_pre(1, 0, 0, &["beta"]);
        let rc = Version::with_pre(1, 0, 0, &["rc", "1"]);

        assert!(alpha < beta);
        assert!(beta < rc);
    }

    #[test]
    fn numeric_prerelease_ordering() {
        // Per semver: numeric identifiers compare numerically
        let v1 = Version::with_pre(1, 0, 0, &["1"]);
        let v2 = Version::with_pre(1, 0, 0, &["2"]);
        assert!(v1 < v2);
    }

    #[test]
    fn prerelease_longer_is_greater() {
        let v1 = Version::with_pre(1, 0, 0, &["alpha"]);
        let v2 = Version::with_pre(1, 0, 0, &["alpha", "1"]);
        assert!(v1 < v2);
    }

    #[test]
    fn numeric_less_than_alpha_in_prerelease() {
        // Per semver 2.0: numeric < alphanumeric
        let v1 = Version::with_pre(1, 0, 0, &["1"]);
        let v2 = Version::with_pre(1, 0, 0, &["alpha"]);
        assert!(v1 < v2);
    }

    // -------------------------------------------------------------------
    // FromStr
    // -------------------------------------------------------------------

    #[test]
    fn from_str_roundtrip() {
        let inputs = [
            "0.0.0",
            "1.0.0",
            "1.2.3",
            "1.0.0-alpha",
            "1.0.0-alpha.1",
            "1.0.0+20260729",
            "1.0.0-rc.1+build.42",
        ];
        for input in &inputs {
            let v: Version = input.parse().unwrap();
            assert_eq!(&v.to_string(), input, "roundtrip failed for {input}");
        }
    }

    // -------------------------------------------------------------------
    // Serialization (serde)
    // -------------------------------------------------------------------

    #[test]
    fn serde_roundtrip_json() {
        let v = Version::full(1, 2, 3, &["rc", "2"], &["20260729"]);
        let json = serde_json::to_string(&v).unwrap();
        let deserialized: Version = serde_json::from_str(&json).unwrap();
        assert_eq!(v, deserialized);
    }

    // -------------------------------------------------------------------
    // Edge cases
    // -------------------------------------------------------------------

    #[test]
    fn is_stable_true_without_prerelease() {
        assert!(Version::new(0, 1, 0).is_stable());
    }

    #[test]
    fn is_stable_false_with_prerelease() {
        assert!(!Version::with_pre(0, 1, 0, &["dev"]).is_stable());
    }

    #[test]
    fn build_metadata_affects_equality() {
        // Build metadata IS part of the struct identity for PartialEq,
        // but does NOT affect precedence comparison (cmp).
        let a = Version::with_build(1, 0, 0, &["1"]);
        let b = Version::with_build(1, 0, 0, &["2"]);
        assert_ne!(a, b); // Different build metadata
        assert_eq!(a.cmp(&b), std::cmp::Ordering::Equal); // Same precedence
    }
}
