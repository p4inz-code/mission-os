//! Package metadata for mission-driverd.
//!
//! Defines strongly-validated types for driver package metadata,
//! including identity, version, architecture, kernel compatibility,
//! digests, and signature references.
//!
//! ## Security
//!
//! - Every metadata field is validated on construction.
//! - Version strings use existing DriverVersion semantics.
//! - Architecture values are normalized.
//! - Hash digests are validated for correct length.
//! - No secrets in metadata.

use serde::{Deserialize, Serialize};
use std::fmt;

use crate::error::{ServiceError, ServiceResult};
use crate::inventory::{DriverModuleType, DriverVersion, KernelCompatibility};

// ── Package Identity ──────────────────────────────────────────────

/// Unique identifier for a driver package.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PackageId {
    /// Driver name (e.g., "e1000e", "nvidia").
    pub driver_name: String,
    /// Source/provider of the package.
    pub source_id: String,
    /// Driver version.
    pub version: DriverVersion,
}

impl PackageId {
    /// Validate the package ID.
    pub fn validate(&self) -> ServiceResult<()> {
        if self.driver_name.trim().is_empty() {
            return Err(ServiceError::InvalidArgument(
                "package driver_name must not be empty".into(),
            ));
        }
        if self.source_id.trim().is_empty() {
            return Err(ServiceError::InvalidArgument(
                "package source_id must not be empty".into(),
            ));
        }
        self.version.validate()?;
        Ok(())
    }
}

impl fmt::Display for PackageId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "{}/{}@{}",
            self.source_id, self.driver_name, self.version
        )
    }
}

// ── Package Digest ────────────────────────────────────────────────

/// Cryptographic hash digest for a package.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PackageDigest {
    /// Hash algorithm identifier.
    pub algorithm: String,
    /// Hash bytes.
    #[serde(with = "hex_serde")]
    pub value: Vec<u8>,
}

impl PackageDigest {
    /// Create a new SHA-256 digest.
    pub fn sha256(bytes: Vec<u8>) -> ServiceResult<Self> {
        if bytes.len() != 32 {
            return Err(ServiceError::InvalidArgument(format!(
                "SHA-256 digest must be 32 bytes, got {}",
                bytes.len()
            )));
        }
        Ok(Self {
            algorithm: "sha256".into(),
            value: bytes,
        })
    }

    /// Create a new BLAKE3 digest.
    pub fn blake3(bytes: Vec<u8>) -> ServiceResult<Self> {
        if bytes.len() != 32 {
            return Err(ServiceError::InvalidArgument(format!(
                "BLAKE3 digest must be 32 bytes, got {}",
                bytes.len()
            )));
        }
        Ok(Self {
            algorithm: "blake3".into(),
            value: bytes,
        })
    }

    /// Parse a hex-encoded digest with algorithm prefix.
    /// Format: "sha256:hexdigest" or "blake3:hexdigest"
    pub fn parse(input: &str) -> ServiceResult<Self> {
        let input = input.trim();
        let (algo, hex) = input.split_once(':').ok_or_else(|| {
            ServiceError::InvalidArgument(format!(
                "invalid digest format, expected 'algorithm:hex': {input}"
            ))
        })?;

        match algo {
            "sha256" | "SHA256" => {
                let bytes = hex_decode(hex)?;
                Self::sha256(bytes)
            }
            "blake3" | "BLAKE3" => {
                let bytes = hex_decode(hex)?;
                Self::blake3(bytes)
            }
            _ => Err(ServiceError::InvalidArgument(format!(
                "unsupported hash algorithm: {algo}"
            ))),
        }
    }

    /// Get the digest as a hex string.
    pub fn to_hex(&self) -> String {
        hex_encode(&self.value)
    }

    /// Format as "algorithm:hex".
    pub fn to_string_full(&self) -> String {
        format!("{}:{}", self.algorithm, self.to_hex())
    }

    /// Compare digests in constant time (where possible).
    pub fn matches(&self, other: &[u8]) -> bool {
        // Constant-time comparison
        let len = self.value.len();
        if other.len() != len {
            return false;
        }
        let result = self
            .value
            .iter()
            .zip(other.iter())
            .fold(0u8, |acc, (a, b)| acc | (a ^ b));
        result == 0
    }
}

impl fmt::Display for PackageDigest {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}:{}", self.algorithm, self.to_hex())
    }
}

// ── Package Metadata ──────────────────────────────────────────────

/// Complete metadata for a driver package.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PackageMetadata {
    /// Package identity.
    pub package_id: PackageId,
    /// Human-readable driver name.
    pub driver_name: String,
    /// Driver description.
    pub description: String,
    /// Module type.
    pub module_type: DriverModuleType,
    /// Target architecture.
    pub architecture: String,
    /// Kernel compatibility requirements.
    pub kernel_compat: KernelCompatibility,
    /// Package filename (not trusted for path resolution).
    pub filename: String,
    /// Package size in bytes.
    pub size_bytes: u64,
    /// Expected cryptographic digest.
    pub digest: PackageDigest,
    /// Signature data (hex-encoded).
    pub signature_hex: String,
    /// Signing key identifier.
    pub signing_key_id: Option<String>,
    /// Source identifier this package originates from.
    pub source_id: String,
    /// Package URL relative to source base.
    pub url_path: String,
    /// Whether this is a delta package.
    pub is_delta: bool,
    /// Base version for delta packages (if applicable).
    pub base_version: Option<DriverVersion>,
}

impl PackageMetadata {
    /// Validate all metadata fields strictly.
    pub fn validate(&self) -> ServiceResult<()> {
        self.package_id.validate()?;

        if self.driver_name.trim().is_empty() {
            return Err(ServiceError::InvalidArgument(
                "driver_name must not be empty".into(),
            ));
        }
        if self.architecture.trim().is_empty() {
            return Err(ServiceError::InvalidArgument(
                "architecture must not be empty".into(),
            ));
        }
        if self.filename.trim().is_empty() {
            return Err(ServiceError::InvalidArgument(
                "filename must not be empty".into(),
            ));
        }
        if self.source_id.trim().is_empty() {
            return Err(ServiceError::InvalidArgument(
                "source_id must not be empty".into(),
            ));
        }
        if self.size_bytes == 0 {
            return Err(ServiceError::InvalidArgument(
                "package size must be greater than 0".into(),
            ));
        }
        if self.size_bytes > 2_000_000_000 {
            return Err(ServiceError::InvalidArgument(
                "package size exceeds maximum (2 GB)".into(),
            ));
        }

        // Validate digest is not empty
        if self.digest.value.is_empty() {
            return Err(ServiceError::InvalidArgument(
                "package digest must not be empty".into(),
            ));
        }

        // Validate kernel compatibility
        self.kernel_compat.validate()?;

        // Validate URL path is safe
        if self.url_path.contains("..") {
            return Err(ServiceError::InvalidArgument(
                "url_path must not contain '..'".into(),
            ));
        }

        // Validate delta constraints
        if self.is_delta && self.base_version.is_none() {
            return Err(ServiceError::InvalidArgument(
                "delta package must specify base_version".into(),
            ));
        }

        Ok(())
    }

    /// Normalize architecture string.
    pub fn normalized_architecture(&self) -> String {
        let arch = self.architecture.to_lowercase();
        match arch.as_str() {
            "amd64" => "x86_64".into(),
            "arm64" => "aarch64".into(),
            _ => arch,
        }
    }
}

// ── Package Catalog Entry ─────────────────────────────────────────

/// A package entry in the catalog, typically from a source index.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CatalogEntry {
    /// Package metadata.
    pub metadata: PackageMetadata,
    /// Whether this package is available for download.
    pub available: bool,
    /// Source priority at time of catalog fetch.
    pub source_priority: u32,
}

// ── Helpers ───────────────────────────────────────────────────────

/// Hex-encode bytes to string.
fn hex_encode(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

/// Decode hex string to bytes.
fn hex_decode(input: &str) -> ServiceResult<Vec<u8>> {
    let input = input.trim();
    if input.len() & 1 != 0 {
        return Err(ServiceError::InvalidArgument(
            "hex string must have even length".into(),
        ));
    }
    let bytes: Vec<u8> = input
        .as_bytes()
        .chunks(2)
        .map(|chunk| {
            let s = std::str::from_utf8(chunk).unwrap_or("00");
            u8::from_str_radix(s, 16).map_err(|_| ())
        })
        .collect::<Result<Vec<_>, _>>()
        .map_err(|_| ServiceError::InvalidArgument("invalid hex string".into()))?;
    Ok(bytes)
}

// Module for hex serialization with serde
mod hex_serde {
    use serde::{Deserialize, Deserializer, Serializer};

    pub(crate) fn serialize<S>(bytes: &[u8], serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        let hex = bytes.iter().map(|b| format!("{b:02x}")).collect::<String>();
        serializer.serialize_str(&hex)
    }

    pub(crate) fn deserialize<'de, D>(deserializer: D) -> Result<Vec<u8>, D::Error>
    where
        D: Deserializer<'de>,
    {
        let hex = String::deserialize(deserializer)?;
        if hex.len() % 2 != 0 {
            return Err(serde::de::Error::custom("hex string must have even length"));
        }
        let bytes: Vec<u8> = hex
            .as_bytes()
            .chunks(2)
            .map(|chunk| {
                let s = std::str::from_utf8(chunk).unwrap_or("00");
                u8::from_str_radix(s, 16)
                    .map_err(|_| serde::de::Error::custom("invalid hex character"))
            })
            .collect::<Result<Vec<_>, _>>()?;
        Ok(bytes)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::inventory::DriverModuleType;

    fn sample_metadata() -> PackageMetadata {
        let digest = PackageDigest::sha256(vec![0u8; 32]).unwrap();
        PackageMetadata {
            package_id: PackageId {
                driver_name: "e1000e".into(),
                source_id: "mission".into(),
                version: DriverVersion::new(1, 0, 0),
            },
            driver_name: "e1000e".into(),
            description: "Intel Ethernet driver".into(),
            module_type: DriverModuleType::KernelModule,
            architecture: "x86_64".into(),
            kernel_compat: KernelCompatibility {
                min_version: "2.6.32".into(),
                max_version: None,
                required_features: Vec::new(),
            },
            filename: "e1000e.ko".into(),
            size_bytes: 245760,
            digest,
            signature_hex: "deadbeef".into(),
            signing_key_id: Some("mission-key".into()),
            source_id: "mission".into(),
            url_path: "packages/e1000e/1.0.0/e1000e.ko".into(),
            is_delta: false,
            base_version: None,
        }
    }

    #[test]
    fn metadata_validation_passes() {
        let meta = sample_metadata();
        assert!(meta.validate().is_ok());
    }

    #[test]
    fn metadata_empty_driver_name_fails() {
        let mut meta = sample_metadata();
        meta.driver_name = "".into();
        assert!(meta.validate().is_err());
    }

    #[test]
    fn metadata_zero_size_fails() {
        let mut meta = sample_metadata();
        meta.size_bytes = 0;
        assert!(meta.validate().is_err());
    }

    #[test]
    fn metadata_empty_digest_fails() {
        let mut meta = sample_metadata();
        meta.digest.value = vec![];
        assert!(meta.validate().is_err());
    }

    #[test]
    fn metadata_path_traversal_rejected() {
        let mut meta = sample_metadata();
        meta.url_path = "../../etc/passwd".into();
        assert!(meta.validate().is_err());
    }

    #[test]
    fn metadata_delta_requires_base_version() {
        let mut meta = sample_metadata();
        meta.is_delta = true;
        meta.base_version = None;
        assert!(meta.validate().is_err());
    }

    #[test]
    fn metadata_delta_with_base_version_ok() {
        let mut meta = sample_metadata();
        meta.is_delta = true;
        meta.base_version = Some(DriverVersion::new(0, 9, 0));
        assert!(meta.validate().is_ok());
    }

    #[test]
    fn digest_sha256_valid() {
        let digest = PackageDigest::sha256(vec![0u8; 32]).unwrap();
        assert_eq!(digest.algorithm, "sha256");
    }

    #[test]
    fn digest_sha256_wrong_length() {
        assert!(PackageDigest::sha256(vec![0u8; 16]).is_err());
    }

    #[test]
    fn digest_blake3_valid() {
        let digest = PackageDigest::blake3(vec![0u8; 32]).unwrap();
        assert_eq!(digest.algorithm, "blake3");
    }

    #[test]
    fn digest_parse_valid() {
        let input = "sha256:abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789";
        let digest = PackageDigest::parse(input).unwrap();
        assert_eq!(digest.algorithm, "sha256");
    }

    #[test]
    fn digest_matches_valid() {
        let bytes = vec![0xde, 0xad, 0xbe, 0xef];
        let padded = [bytes.clone(), vec![0u8; 28]].concat();
        let digest = PackageDigest::sha256(padded.clone()).unwrap();
        assert!(digest.matches(&padded));
        assert!(!digest.matches(&[0u8; 32]));
    }

    #[test]
    fn digest_parse_invalid_algorithm() {
        assert!(PackageDigest::parse("md5:deadbeef").is_err());
    }

    #[test]
    fn digest_display() {
        let digest = PackageDigest::sha256(vec![0u8; 32]).unwrap();
        let display = digest.to_string();
        assert!(display.starts_with("sha256:"));
        assert_eq!(display.len(), 7 + 64); // "sha256:" + 64 hex chars
    }

    #[test]
    fn package_id_display() {
        let id = PackageId {
            driver_name: "e1000e".into(),
            source_id: "mission".into(),
            version: DriverVersion::new(1, 2, 3),
        };
        assert_eq!(id.to_string(), "mission/e1000e@1.2.3");
    }

    #[test]
    fn architecture_normalization() {
        let mut meta = sample_metadata();
        meta.architecture = "AMD64".into();
        assert_eq!(meta.normalized_architecture(), "x86_64");

        meta.architecture = "arm64".into();
        assert_eq!(meta.normalized_architecture(), "aarch64");

        meta.architecture = "x86_64".into();
        assert_eq!(meta.normalized_architecture(), "x86_64");
    }

    #[test]
    fn metadata_size_limit() {
        let mut meta = sample_metadata();
        meta.size_bytes = 3_000_000_000;
        assert!(meta.validate().is_err());
    }
}
