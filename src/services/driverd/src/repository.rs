//! M2-F: Multi-source repository metadata model with authenticated
//! metadata verification, freshness/anti-replay protection, and
//! trusted key management.
//!
//! ## Architecture
//!
//! This module extends the existing driverd source abstraction
//! (SourceRegistry) with repository-level metadata that enables
//! multiple configured driver repositories, each with its own
//! trust configuration, key material, and package catalog.
//!
//! ## Trust Model
//!
//! Repository metadata is cryptographically signed using Ed25519
//! (reusing mission-crypto's signing infrastructure). A repository
//! manifest includes:
//!
//! - Repository identity and version
//! - Issued-at and expires-at timestamps (anti-replay)
//! - Signing key identity
//! - Package catalog with digest algorithms and values
//!
//! Metadata is NOT trusted merely because it arrived over HTTPS.
//! The signature is verified against a trusted key before any
//! package entries are accepted.
//!
//! ## Security
//!
//! - Metadata is verified before use — never trusted raw
//! - Expired or future-timestamped metadata is rejected
//! - Unknown signing keys cause explicit rejection
//! - Tampered metadata is detected via signature verification
//! - No secret material in errors or logs
//! - Unsigned metadata is never accepted as trusted
//!
//! ## Dependencies
//!
//! Reuses mission-crypto for Ed25519 verification (no new
//! cryptographic dependencies). Reuses existing metric types
//! from metadata.rs (PackageDigest, DriverVersion, etc.).

use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};

use crate::audit::{AuditBackend, AuditEvent, EventCategory, EventSeverity};
use crate::error::{ServiceError, ServiceResult};

// ── Constants ─────────────────────────────────────────────────────

/// Maximum size for a repository manifest (1 MB).
pub const MAX_MANIFEST_SIZE: u64 = 1_048_576;

/// Default clock skew tolerance (300 seconds = 5 minutes).
pub const DEFAULT_CLOCK_SKEW_SECS: u64 = 300;

/// Default metadata freshness (expiry) in seconds: 24 hours.
pub const DEFAULT_FRESHNESS_SECS: u64 = 86_400;

/// Minimum allowed freshness in seconds: 1 hour.
pub const MIN_FRESHNESS_SECS: u64 = 3_600;

/// Maximum allowed freshness in seconds: 7 days.
pub const MAX_FRESHNESS_SECS: u64 = 604_800;

/// Supported digest algorithms for repository metadata packages.
const SUPPORTED_DIGEST_ALGORITHMS: &[&str] = &["sha256", "blake3"];

/// Supported architectures.
const SUPPORTED_ARCHITECTURES: &[&str] = &["x86_64", "amd64", "aarch64", "arm64"];

// ── Repository Identity ───────────────────────────────────────────

/// Stable identifier for a driver source/repository.
///
/// This is the primary key for looking up sources in the registry.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct RepositoryId(String);

impl RepositoryId {
    /// Create a new repository ID. Validates that the ID is non-empty
    /// and contains only safe characters.
    pub fn new(id: impl Into<String>) -> ServiceResult<Self> {
        let id = id.into();
        if id.trim().is_empty() {
            return Err(ServiceError::InvalidArgument(
                "repository ID must not be empty".into(),
            ));
        }
        if id.len() > 128 {
            return Err(ServiceError::InvalidArgument(
                "repository ID exceeds maximum length (128)".into(),
            ));
        }
        // Only allow alphanumeric, hyphens, underscores, and dots
        if !id
            .chars()
            .all(|c| c.is_alphanumeric() || c == '-' || c == '_' || c == '.')
        {
            return Err(ServiceError::InvalidArgument(format!(
                "repository ID '{id}' contains invalid characters"
            )));
        }
        Ok(Self(id))
    }

    /// Return the inner string.
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl std::fmt::Display for RepositoryId {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.0)
    }
}

impl From<RepositoryId> for String {
    fn from(id: RepositoryId) -> Self {
        id.0
    }
}

// ── Trust Configuration ───────────────────────────────────────────

/// Level of trust for a repository source.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TrustLevel {
    /// Repository is fully trusted. Signed metadata is required.
    Trusted,
    /// Repository is untrusted. Packages from this source will be
    /// rejected unless explicitly overridden by the user.
    Untrusted,
    /// Repository trust is unknown. Requires user confirmation.
    Unknown,
}

/// Configuration for repository trust.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrustConfig {
    /// Trust level for this repository.
    pub level: TrustLevel,
    /// Hex-encoded Ed25519 public keys that are authorized to sign
    /// this repository's metadata. At least one key is required
    /// for Trusted repositories.
    pub trusted_keys: Vec<String>,
    /// Optional key identity hint (e.g., "Mission OS Release Key 2026").
    pub key_identity: Option<String>,
}

impl TrustConfig {
    /// Create a new trust configuration for a trusted repository.
    pub fn trusted(keys: Vec<String>) -> Self {
        Self {
            level: TrustLevel::Trusted,
            trusted_keys: keys,
            key_identity: None,
        }
    }

    /// Create a new trust configuration for an untrusted repository.
    pub fn untrusted() -> Self {
        Self {
            level: TrustLevel::Untrusted,
            trusted_keys: Vec::new(),
            key_identity: None,
        }
    }

    /// Whether this configuration has at least one trusted key.
    pub fn has_keys(&self) -> bool {
        !self.trusted_keys.is_empty()
    }
}

// ── Freshness / Anti-Replay Policy ───────────────────────────────

/// Configuration for repository metadata freshness checks.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FreshnessPolicy {
    /// Maximum clock skew tolerance in seconds.
    pub clock_skew_secs: u64,
    /// Maximum age of metadata in seconds before it expires.
    pub max_age_secs: u64,
}

impl FreshnessPolicy {
    /// Create a strict freshness policy (minimal tolerance).
    pub fn strict() -> Self {
        Self {
            clock_skew_secs: 60,
            max_age_secs: 3600,
        }
    }

    /// Validate the policy parameters.
    pub fn validate(&self) -> ServiceResult<()> {
        if self.max_age_secs < MIN_FRESHNESS_SECS {
            return Err(ServiceError::InvalidArgument(format!(
                "max_age_secs {} is below minimum {}",
                self.max_age_secs, MIN_FRESHNESS_SECS
            )));
        }
        if self.max_age_secs > MAX_FRESHNESS_SECS {
            return Err(ServiceError::InvalidArgument(format!(
                "max_age_secs {} exceeds maximum {}",
                self.max_age_secs, MAX_FRESHNESS_SECS
            )));
        }
        Ok(())
    }
}

impl Default for FreshnessPolicy {
    fn default() -> Self {
        Self {
            clock_skew_secs: DEFAULT_CLOCK_SKEW_SECS,
            max_age_secs: DEFAULT_FRESHNESS_SECS,
        }
    }
}

// ── Repository Manifest (Metadata) ────────────────────────────────

/// A single package entry in a repository manifest.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RepositoryPackageEntry {
    /// Package name (must match a DriverEntry name).
    pub name: String,
    /// Package version string (e.g., "1.2.3").
    pub version: String,
    /// URL/path to the driver package.
    pub url: String,
    /// Package size in bytes.
    #[serde(default)]
    pub size: Option<u64>,
    /// Digest algorithm identifier (e.g., "sha256", "blake3").
    pub digest_algorithm: String,
    /// Hex-encoded digest value.
    pub digest_value: String,
    /// Target architecture (e.g., "amd64", "arm64").
    #[serde(default)]
    pub architecture: Option<String>,
    /// Kernel version compatibility (e.g., ">= 5.4.0, < 6.9.0").
    #[serde(default)]
    pub kernel_compat: Option<String>,
    /// Modalias patterns for hardware matching.
    #[serde(default)]
    pub modalias_patterns: Vec<String>,
    /// Package metadata version (for format evolution).
    #[serde(default = "default_metadata_version")]
    pub metadata_version: u32,
    /// Optional release channel (e.g., "stable", "beta", "testing").
    #[serde(default)]
    pub channel: Option<String>,
}

fn default_metadata_version() -> u32 {
    1
}

/// Top-level repository manifest containing the package catalog
/// and metadata authentication information.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RepositoryManifest {
    /// Repository identity.
    pub repository_id: String,
    /// Manifest format version.
    pub manifest_version: u32,
    /// Unix timestamp when this manifest was generated (seconds since epoch).
    pub issued_at: u64,
    /// Unix timestamp when this manifest expires.
    pub expires_at: u64,
    /// Identity of the signing key (hex-encoded public key fingerprint).
    pub signing_key_id: String,
    /// Package catalog.
    pub packages: Vec<RepositoryPackageEntry>,
    /// Signature verification info (populated after verification).
    #[serde(skip)]
    pub verification: ManifestVerification,
}

/// The result of manifest signature verification.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub enum ManifestVerification {
    /// Manifest has not been verified yet.
    #[default]
    Unverified,
    /// Manifest is cryptographically valid and signed by a trusted key.
    Verified {
        /// The hex-encoded public key that signed this manifest.
        key_id: String,
    },
    /// Signature verification failed.
    InvalidSignature(String),
    /// Signing key is not in the trusted key set.
    UnknownKey(String),
}

impl ManifestVerification {
    /// Whether the manifest is trusted (verified with known key).
    pub fn is_trusted(&self) -> bool {
        matches!(self, ManifestVerification::Verified { .. })
    }
}

// ── Package Metadata Validation ───────────────────────────────────

impl RepositoryPackageEntry {
    /// Validate all fields of this package entry.
    pub fn validate(&self) -> ServiceResult<()> {
        // Package name
        if self.name.trim().is_empty() {
            return Err(ServiceError::MetadataError(
                "package name must not be empty".into(),
            ));
        }
        if self.name.len() > 256 {
            return Err(ServiceError::MetadataError(
                "package name exceeds maximum length".into(),
            ));
        }

        // Version string must be parseable
        if self.version.trim().is_empty() {
            return Err(ServiceError::MetadataError(
                "package version must not be empty".into(),
            ));
        }
        let _ = crate::inventory::DriverVersion::parse(&self.version).map_err(|e| {
            ServiceError::MetadataError(format!("invalid package version '{}': {e}", self.version))
        })?;

        // URL validation — must be http/https or relative path
        self.validate_url()?;

        // Size must be positive if present
        if let Some(size) = self.size {
            if size == 0 {
                return Err(ServiceError::MetadataError(
                    "package size must be positive if specified".into(),
                ));
            }
        }

        // Digest algorithm must be supported
        let algo_lower = self.digest_algorithm.to_lowercase();
        if !SUPPORTED_DIGEST_ALGORITHMS.contains(&algo_lower.as_str()) {
            return Err(ServiceError::MetadataError(format!(
                "unsupported digest algorithm '{}'",
                self.digest_algorithm
            )));
        }

        // Digest value must be valid hex and correct length for the algorithm
        let expected_len = match algo_lower.as_str() {
            "sha256" => 64, // 32 bytes * 2 hex chars
            "blake3" => 64, // 32 bytes * 2 hex chars (default 256-bit)
            _ => {
                return Err(ServiceError::MetadataError(format!(
                    "unsupported digest algorithm '{}'",
                    self.digest_algorithm
                )));
            }
        };

        if self.digest_value.len() != expected_len {
            return Err(ServiceError::MetadataError(format!(
                "digest value length {} does not match expected {} for algorithm '{}'",
                self.digest_value.len(),
                expected_len,
                self.digest_algorithm
            )));
        }
        if !self.digest_value.chars().all(|c| c.is_ascii_hexdigit()) {
            return Err(ServiceError::MetadataError(
                "digest value must be valid hexadecimal".into(),
            ));
        }

        // Architecture validation
        if let Some(ref arch) = self.architecture {
            let arch_lower = arch.to_lowercase();
            if !SUPPORTED_ARCHITECTURES.contains(&arch_lower.as_str()) {
                return Err(ServiceError::MetadataError(format!(
                    "unsupported architecture '{}'",
                    arch
                )));
            }
        }

        // Channel validation
        if let Some(ref channel) = self.channel {
            let valid_channels = ["stable", "beta", "testing", "nightly", "rc"];
            if !valid_channels.contains(&channel.as_str()) {
                return Err(ServiceError::MetadataError(format!(
                    "invalid release channel '{}'",
                    channel
                )));
            }
        }

        Ok(())
    }

    /// Validate the URL field.
    fn validate_url(&self) -> ServiceResult<()> {
        let url = self.url.trim();

        if url.is_empty() {
            return Err(ServiceError::MetadataError(
                "package URL must not be empty".into(),
            ));
        }

        // Reject path traversal attempts
        if url.contains("..") {
            return Err(ServiceError::MetadataError(
                "package URL must not contain path traversal sequences".into(),
            ));
        }

        if url.contains("\\") {
            return Err(ServiceError::MetadataError(
                "package URL must not contain backslashes".into(),
            ));
        }

        // Must start with http://, https://, or /
        if !url.starts_with("http://") && !url.starts_with("https://") && !url.starts_with('/') {
            return Err(ServiceError::MetadataError(format!(
                "package URL must be http/https or absolute path: '{url}'"
            )));
        }

        Ok(())
    }
}

// ── Manifest Validation ───────────────────────────────────────────

impl RepositoryManifest {
    /// Validate the manifest structure and all package entries.
    pub fn validate(&self) -> ServiceResult<()> {
        // Repository ID
        if self.repository_id.trim().is_empty() {
            return Err(ServiceError::MetadataError(
                "repository_id must not be empty".into(),
            ));
        }

        // Manifest version (currently only version 1)
        if self.manifest_version != 1 {
            return Err(ServiceError::MetadataError(format!(
                "unsupported manifest version: {}",
                self.manifest_version
            )));
        }

        // Signing key ID
        if self.signing_key_id.trim().is_empty() {
            return Err(ServiceError::MetadataError(
                "signing_key_id must not be empty".into(),
            ));
        }

        // Timestamps
        if self.issued_at == 0 {
            return Err(ServiceError::MetadataError(
                "issued_at must not be zero".into(),
            ));
        }
        if self.expires_at == 0 {
            return Err(ServiceError::MetadataError(
                "expires_at must not be zero".into(),
            ));
        }
        if self.expires_at <= self.issued_at {
            return Err(ServiceError::MetadataError(
                "expires_at must be after issued_at".into(),
            ));
        }

        // Package validation — check for exact duplicates (same name AND version)
        let mut seen: std::collections::HashSet<(String, String)> =
            std::collections::HashSet::new();
        for pkg in &self.packages {
            pkg.validate()?;
            if !seen.insert((pkg.name.clone(), pkg.version.clone())) {
                return Err(ServiceError::MetadataError(format!(
                    "duplicate package entry '{}' version {}",
                    pkg.name, pkg.version
                )));
            }
        }

        Ok(())
    }

    /// Check whether the manifest is fresh (not expired, not from the future).
    ///
    /// Returns `Ok(())` if the manifest is within the valid time window.
    /// Returns `Err` with a descriptive error if the manifest is too old
    /// or from the future beyond the allowed clock skew.
    pub fn check_freshness(&self, policy: &FreshnessPolicy) -> ServiceResult<()> {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();

        // Check if manifest is from the future (beyond clock skew)
        if self.issued_at > now + policy.clock_skew_secs {
            return Err(ServiceError::MetadataError(format!(
                "manifest issued_at {} is in the future (skew tolerance: {}s)",
                self.issued_at, policy.clock_skew_secs
            )));
        }

        // Check if manifest has expired
        if self.expires_at < now.saturating_sub(policy.clock_skew_secs) {
            return Err(ServiceError::MetadataError(format!(
                "manifest expired at {} (current time: {}, skew tolerance: {}s)",
                self.expires_at, now, policy.clock_skew_secs
            )));
        }

        // Check max age
        let age = now.saturating_sub(self.issued_at);
        if age > policy.max_age_secs {
            return Err(ServiceError::MetadataError(format!(
                "manifest age {}s exceeds maximum {}s",
                age, policy.max_age_secs
            )));
        }

        Ok(())
    }

    /// Check freshness and emit an audit event on failure.
    pub fn check_freshness_audited(
        &self,
        policy: &FreshnessPolicy,
        audit: &dyn AuditBackend,
        subject: &str,
    ) -> ServiceResult<()> {
        match self.check_freshness(policy) {
            Ok(()) => Ok(()),
            Err(e) => {
                let event = AuditEvent::new(
                    EventCategory::Integrity,
                    EventSeverity::Warning,
                    "metadata_freshness_rejected",
                    subject,
                    format!("Repository '{}': {}", self.repository_id, e),
                );
                audit.record(&event);
                Err(e)
            }
        }
    }
}

// ── Signature Verification ───────────────────────────────────────

/// Verify a repository manifest's signature.
///
/// # Arguments
///
/// * `manifest_json` - The raw JSON bytes of the manifest (before signature removal).
/// * `signature_hex` - The hex-encoded Ed25519 signature.
/// * `trusted_keys` - The set of trusted hex-encoded Ed25519 public keys.
///
/// # Returns
///
/// `ManifestVerification` indicating the verification result.
pub fn verify_manifest_signature(
    manifest_json: &[u8],
    signature_hex: &str,
    trusted_keys: &[String],
) -> ManifestVerification {
    use mission_crypto::signing::{verify, Signature, VerificationResult};

    // Decode the signature
    let sig_bytes = match hex_decode(signature_hex) {
        Some(bytes) if bytes.len() == 64 => bytes,
        _ => {
            return ManifestVerification::InvalidSignature(
                "signature is not valid hex or wrong length (expected 64 bytes)".into(),
            );
        }
    };

    let signature = Signature::new(sig_bytes);

    // Try each trusted key
    for key_hex in trusted_keys {
        let pub_key_bytes = match hex_decode(key_hex) {
            Some(bytes) if bytes.len() == 32 => bytes,
            _ => continue, // Skip malformed keys
        };

        match verify(&pub_key_bytes, manifest_json, &signature) {
            Ok(VerificationResult::Valid) => {
                return ManifestVerification::Verified {
                    key_id: key_hex.clone(),
                };
            }
            Ok(VerificationResult::Invalid) => {
                // Continue checking other keys
                continue;
            }
            Err(_) => {
                // Malformed key or signature, continue
                continue;
            }
        }
    }

    // If we have trusted keys but none matched, it's an invalid signature
    if trusted_keys.is_empty() {
        ManifestVerification::UnknownKey("no trusted keys configured".into())
    } else {
        ManifestVerification::InvalidSignature("signature does not match any trusted key".into())
    }
}

/// Verify a manifest's signature and audit the result.
pub fn verify_manifest_signature_audited(
    manifest_json: &[u8],
    signature_hex: &str,
    trusted_keys: &[String],
    audit: &dyn AuditBackend,
    subject: &str,
    repository_id: &str,
) -> ManifestVerification {
    let result = verify_manifest_signature(manifest_json, signature_hex, trusted_keys);

    let (severity, action, details) = match &result {
        ManifestVerification::Verified { key_id } => (
            EventSeverity::Info,
            "metadata_authentication_success",
            format!(
                "Repository '{}' metadata authenticated with key {}",
                repository_id,
                &key_id[..16.min(key_id.len())]
            ),
        ),
        ManifestVerification::InvalidSignature(msg) => (
            EventSeverity::Error,
            "metadata_authentication_failure",
            format!("Repository '{}': {msg}", repository_id),
        ),
        ManifestVerification::UnknownKey(msg) => (
            EventSeverity::Error,
            "metadata_unknown_key",
            format!("Repository '{}': {msg}", repository_id),
        ),
        ManifestVerification::Unverified => {
            // This shouldn't happen when called from this function
            return result;
        }
    };

    let event = AuditEvent::new(EventCategory::Integrity, severity, action, subject, details);
    audit.record(&event);

    result
}

// ── Repository Manifest Builder ───────────────────────────────────

/// Builder for constructing a signed repository manifest.
///
/// This is useful for testing and for the mission-driverd tooling
/// that generates repository metadata.
#[derive(Debug)]
pub struct ManifestBuilder {
    repository_id: String,
    manifest_version: u32,
    issued_at: u64,
    expires_at: u64,
    signing_key_id: String,
    packages: Vec<RepositoryPackageEntry>,
}

#[allow(dead_code)]
impl ManifestBuilder {
    /// Create a new manifest builder.
    pub fn new(repository_id: impl Into<String>) -> Self {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        Self {
            repository_id: repository_id.into(),
            manifest_version: 1,
            issued_at: now,
            expires_at: now + DEFAULT_FRESHNESS_SECS,
            signing_key_id: String::new(),
            packages: Vec::new(),
        }
    }

    /// Set the manifest version.
    pub fn version(mut self, version: u32) -> Self {
        self.manifest_version = version;
        self
    }

    /// Set the issued-at timestamp.
    pub fn issued_at(mut self, ts: u64) -> Self {
        self.issued_at = ts;
        self
    }

    /// Set the expires-at timestamp.
    pub fn expires_at(mut self, ts: u64) -> Self {
        self.expires_at = ts;
        self
    }

    /// Set the signing key identity.
    pub fn signing_key(mut self, key_id: impl Into<String>) -> Self {
        self.signing_key_id = key_id.into();
        self
    }

    /// Add a package entry.
    pub fn add_package(mut self, pkg: RepositoryPackageEntry) -> Self {
        self.packages.push(pkg);
        self
    }

    /// Build the manifest without verification (for testing).
    pub fn build(self) -> RepositoryManifest {
        RepositoryManifest {
            repository_id: self.repository_id,
            manifest_version: self.manifest_version,
            issued_at: self.issued_at,
            expires_at: self.expires_at,
            signing_key_id: self.signing_key_id,
            packages: self.packages,
            verification: ManifestVerification::Unverified,
        }
    }

    /// Build and sign the manifest, returning (manifest, json_bytes, signature_hex).
    #[cfg(test)]
    fn build_and_sign(
        self,
        signing_key: &mission_crypto::keygen::Ed25519KeyPair,
    ) -> (RepositoryManifest, Vec<u8>, String) {
        use mission_crypto::signing::sign;

        let manifest = self.build();
        let json = serde_json::to_vec(&manifest).expect("manifest serialization");
        let signature = sign(signing_key, &json);
        let sig_hex = signature.to_hex();
        (manifest, json, sig_hex)
    }
}

// ── Hex Encoding/Decoding Helpers ─────────────────────────────────

/// Decode a hex string to bytes. Returns None if the string is not
/// valid hex or has odd length.
fn hex_decode(hex: &str) -> Option<Vec<u8>> {
    let hex = hex.trim();
    if !hex.len().is_multiple_of(2) {
        return None;
    }
    (0..hex.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&hex[i..i + 2], 16).ok())
        .collect()
}

// ── Repository Metadata Manager ───────────────────────────────────

/// Manages repository metadata lifecycle: fetch, verify, cache, refresh.
///
/// Coordinates between SourceRegistry (which sources to query),
/// the fetch layer (HTTP downloads), and the verification layer
/// (signature + freshness).
pub struct RepositoryManager {
    /// Freshness policy for metadata validation.
    freshness_policy: FreshnessPolicy,
    /// Audit backend for emitting events.
    audit_backend: Box<dyn AuditBackend>,
}

impl RepositoryManager {
    /// Create a new repository metadata manager.
    pub fn new(freshness_policy: FreshnessPolicy, audit_backend: Box<dyn AuditBackend>) -> Self {
        Self {
            freshness_policy,
            audit_backend,
        }
    }

    /// Validate and verify a fetched manifest.
    ///
    /// This performs the full validation pipeline:
    /// 1. Structural validation (malformed data, duplicate packages)
    /// 2. Freshness check (not expired, not future)
    /// 3. Signature verification (trusted key, against **original** JSON bytes)
    ///
    /// The `manifest_json` parameter MUST be the exact bytes received from
    /// the server — the signature is verified against these raw bytes, NOT
    /// against a re-serialized version. This prevents JSON formatting
    /// differences (field ordering, whitespace) from causing spurious
    /// signature failures.
    ///
    /// Returns the verified manifest or an error.
    pub fn verify_manifest(
        &self,
        manifest_json: &[u8],
        manifest: &RepositoryManifest,
        signature_hex: &str,
        trusted_keys: &[String],
        subject: &str,
    ) -> ServiceResult<RepositoryManifest> {
        // 1. Structural validation
        manifest.validate().map_err(|e| {
            ServiceError::MetadataError(format!(
                "manifest validation failed for '{}': {e}",
                manifest.repository_id
            ))
        })?;

        // 2. Freshness check (with audit)
        manifest
            .check_freshness_audited(&self.freshness_policy, self.audit_backend.as_ref(), subject)
            .map_err(|e| {
                ServiceError::MetadataError(format!(
                    "manifest freshness check failed for '{}': {e}",
                    manifest.repository_id
                ))
            })?;

        // 3. Signature verification against **original** JSON bytes (with audit)
        let verification = verify_manifest_signature_audited(
            manifest_json,
            signature_hex,
            trusted_keys,
            self.audit_backend.as_ref(),
            subject,
            &manifest.repository_id,
        );

        let mut verified = manifest.clone();
        verified.verification = verification.clone();

        match verification {
            ManifestVerification::Verified { .. } => Ok(verified),
            ManifestVerification::InvalidSignature(msg) => {
                Err(ServiceError::VerificationFailed(format!(
                    "manifest signature verification failed for '{}': {msg}",
                    manifest.repository_id
                )))
            }
            ManifestVerification::UnknownKey(msg) => Err(ServiceError::SourceError(format!(
                "unknown signing key for repository '{}': {msg}",
                manifest.repository_id
            ))),
            ManifestVerification::Unverified => Err(ServiceError::Internal(
                "manifest not verified after verification call".into(),
            )),
        }
    }

    /// Validate a manifest without requiring a trusted key (for unsigned metadata).
    /// Only performs structural and freshness checks.
    pub fn validate_unsigned_manifest(
        &self,
        manifest: &RepositoryManifest,
        subject: &str,
    ) -> ServiceResult<RepositoryManifest> {
        manifest.validate().map_err(|e| {
            ServiceError::MetadataError(format!(
                "manifest validation failed for '{}': {e}",
                manifest.repository_id
            ))
        })?;

        manifest
            .check_freshness_audited(&self.freshness_policy, self.audit_backend.as_ref(), subject)
            .map_err(|e| {
                ServiceError::MetadataError(format!(
                    "manifest freshness check failed for '{}': {e}",
                    manifest.repository_id
                ))
            })?;

        let mut verified = manifest.clone();
        verified.verification = ManifestVerification::Unverified;
        Ok(verified)
    }

    /// Return the freshness policy reference.
    pub fn freshness_policy(&self) -> &FreshnessPolicy {
        &self.freshness_policy
    }
}

/// Encode bytes to hex string (test helper).
#[cfg(test)]
fn hex_encode(bytes: Vec<u8>) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

// ── Tests ─────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use crate::audit::LogAuditBackend;

    // ── RepositoryId ───────────────────────────────────────────

    #[test]
    fn repository_id_valid() {
        let id = RepositoryId::new("mission-official").unwrap();
        assert_eq!(id.as_str(), "mission-official");
    }

    #[test]
    fn repository_id_empty_rejected() {
        assert!(RepositoryId::new("").is_err());
    }

    #[test]
    fn repository_id_invalid_chars_rejected() {
        assert!(RepositoryId::new("mission/repo").is_err());
        assert!(RepositoryId::new("../repo").is_err());
        assert!(RepositoryId::new("repo;malicious").is_err());
    }

    #[test]
    fn repository_id_too_long_rejected() {
        let long = "a".repeat(129);
        assert!(RepositoryId::new(long).is_err());
    }

    // ── FreshnessPolicy ────────────────────────────────────────

    #[test]
    fn freshness_policy_default_valid() {
        let policy = FreshnessPolicy::default();
        assert!(policy.validate().is_ok());
    }

    #[test]
    fn freshness_policy_too_short_rejected() {
        let policy = FreshnessPolicy {
            clock_skew_secs: 0,
            max_age_secs: 100, // Below MIN_FRESHNESS_SECS
        };
        assert!(policy.validate().is_err());
    }

    #[test]
    fn freshness_policy_too_long_rejected() {
        let policy = FreshnessPolicy {
            clock_skew_secs: 0,
            max_age_secs: MAX_FRESHNESS_SECS + 1,
        };
        assert!(policy.validate().is_err());
    }

    // ── RepositoryPackageEntry ─────────────────────────────────

    fn valid_entry() -> RepositoryPackageEntry {
        RepositoryPackageEntry {
            name: "e1000e".into(),
            version: "1.2.3".into(),
            url: "https://repo.mission-os.org/drivers/e1000e-1.2.3.ko".into(),
            size: Some(1024),
            digest_algorithm: "sha256".into(),
            digest_value: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855".into(),
            architecture: Some("amd64".into()),
            kernel_compat: Some(">= 5.4.0".into()),
            modalias_patterns: vec!["pci:v00008086d*".into()],
            metadata_version: 1,
            channel: Some("stable".into()),
        }
    }

    #[test]
    fn package_entry_valid() {
        assert!(valid_entry().validate().is_ok());
    }

    #[test]
    fn package_entry_empty_name_rejected() {
        let mut entry = valid_entry();
        entry.name = "".into();
        assert!(entry.validate().is_err());
    }

    #[test]
    fn package_entry_invalid_version_rejected() {
        let mut entry = valid_entry();
        entry.version = "abc".into();
        assert!(entry.validate().is_err());
    }

    #[test]
    fn package_entry_path_traversal_rejected() {
        let mut entry = valid_entry();
        entry.url = "https://repo.org/../../etc/passwd".into();
        assert!(entry.validate().is_err());
    }

    #[test]
    fn package_entry_unsupported_digest_rejected() {
        let mut entry = valid_entry();
        entry.digest_algorithm = "md5".into();
        entry.digest_value = "deadbeef".into();
        assert!(entry.validate().is_err());
    }

    #[test]
    fn package_entry_wrong_digest_length_rejected() {
        let mut entry = valid_entry();
        entry.digest_value = "abcd".into(); // Too short for sha256
        assert!(entry.validate().is_err());
    }

    #[test]
    fn package_entry_invalid_digest_hex_rejected() {
        let mut entry = valid_entry();
        entry.digest_value =
            "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz".into();
        assert!(entry.validate().is_err());
    }

    #[test]
    fn package_entry_invalid_architecture_rejected() {
        let mut entry = valid_entry();
        entry.architecture = Some("mips".into());
        assert!(entry.validate().is_err());
    }

    #[test]
    fn package_entry_invalid_channel_rejected() {
        let mut entry = valid_entry();
        entry.channel = Some("rogue".into());
        assert!(entry.validate().is_err());
    }

    #[test]
    fn package_entry_zero_size_rejected() {
        let mut entry = valid_entry();
        entry.size = Some(0);
        assert!(entry.validate().is_err());
    }

    // ── RepositoryManifest ─────────────────────────────────────

    fn valid_manifest() -> RepositoryManifest {
        RepositoryManifest {
            repository_id: "test-repo".into(),
            manifest_version: 1,
            issued_at: SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs(),
            expires_at: SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs()
                + 86400,
            signing_key_id: "deadbeef".into(),
            packages: vec![valid_entry()],
            verification: ManifestVerification::Unverified,
        }
    }

    #[test]
    fn manifest_valid() {
        assert!(valid_manifest().validate().is_ok());
    }

    #[test]
    fn manifest_empty_repository_id_rejected() {
        let mut m = valid_manifest();
        m.repository_id = "".into();
        assert!(m.validate().is_err());
    }

    #[test]
    fn manifest_unsupported_version_rejected() {
        let mut m = valid_manifest();
        m.manifest_version = 99;
        assert!(m.validate().is_err());
    }

    #[test]
    fn manifest_expires_before_issued_rejected() {
        let mut m = valid_manifest();
        m.expires_at = m.issued_at - 1;
        assert!(m.validate().is_err());
    }

    #[test]
    fn manifest_duplicate_packages_rejected() {
        let mut m = valid_manifest();
        let dup = valid_entry();
        m.packages.push(dup);
        assert!(m.validate().is_err());
    }

    #[test]
    fn manifest_duplicate_different_versions_allowed() {
        let mut m = valid_manifest();
        let mut dup = valid_entry();
        dup.version = "2.0.0".into();
        m.packages.push(dup);
        // Different version, same name — this is allowed (multiple versions)
        assert!(m.validate().is_ok());
    }

    #[test]
    fn manifest_empty_packages_allowed() {
        let mut m = valid_manifest();
        m.packages.clear();
        assert!(m.validate().is_ok());
    }

    // ── Freshness ──────────────────────────────────────────────

    #[test]
    fn manifest_freshness_valid() {
        let policy = FreshnessPolicy::default();
        let manifest = valid_manifest();
        assert!(manifest.check_freshness(&policy).is_ok());
    }

    #[test]
    fn manifest_expired_rejected() {
        let policy = FreshnessPolicy::default();
        let mut manifest = valid_manifest();
        manifest.expires_at = 1; // Very old expiry
        assert!(manifest.check_freshness(&policy).is_err());
    }

    #[test]
    fn manifest_future_issued_rejected() {
        let policy = FreshnessPolicy {
            clock_skew_secs: 0,
            max_age_secs: 86400,
        };
        let mut manifest = valid_manifest();
        manifest.issued_at = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs()
            + 3600; // 1 hour in the future, beyond 0 skew tolerance
        assert!(manifest.check_freshness(&policy).is_err());
    }

    #[test]
    fn manifest_old_age_rejected() {
        let policy = FreshnessPolicy {
            clock_skew_secs: 0,
            max_age_secs: 3600,
        };
        let mut manifest = valid_manifest();
        manifest.issued_at = 1_000_000; // Very old
        manifest.expires_at = 9_999_999_999;
        assert!(manifest.check_freshness(&policy).is_err());
    }

    // ── Signature Verification ─────────────────────────────────

    #[test]
    fn verify_valid_signature() {
        let key_pair = mission_crypto::keygen::generate_ed25519().unwrap();
        let trusted_keys = vec![hex_encode(key_pair.verifying_key.as_bytes().to_vec())];

        let manifest = valid_manifest();
        let json = serde_json::to_vec(&manifest).unwrap();
        let sig = mission_crypto::signing::sign(&key_pair, &json);
        let sig_hex = sig.to_hex();

        let result = verify_manifest_signature(&json, &sig_hex, &trusted_keys);
        assert!(result.is_trusted());
    }

    #[test]
    fn verify_invalid_signature() {
        let key_pair = mission_crypto::keygen::generate_ed25519().unwrap();
        let trusted_keys = vec![hex_encode(key_pair.verifying_key.as_bytes().to_vec())];

        let manifest = valid_manifest();
        let json = serde_json::to_vec(&manifest).unwrap();

        // Tamper with the manifest data
        let mut tampered = json.clone();
        if let Some(last) = tampered.last_mut() {
            *last ^= 0x01;
        }

        let sig = mission_crypto::signing::sign(&key_pair, &json);
        let sig_hex = sig.to_hex();

        let result = verify_manifest_signature(&tampered, &sig_hex, &trusted_keys);
        assert!(!result.is_trusted());
    }

    #[test]
    fn verify_wrong_key() {
        let key_pair_a = mission_crypto::keygen::generate_ed25519().unwrap();
        let key_pair_b = mission_crypto::keygen::generate_ed25519().unwrap();
        let trusted_keys = vec![hex_encode(key_pair_b.verifying_key.as_bytes().to_vec())];

        let manifest = valid_manifest();
        let json = serde_json::to_vec(&manifest).unwrap();
        let sig = mission_crypto::signing::sign(&key_pair_a, &json);
        let sig_hex = sig.to_hex();

        let result = verify_manifest_signature(&json, &sig_hex, &trusted_keys);
        assert!(!result.is_trusted());
    }

    #[test]
    fn verify_no_trusted_keys() {
        let key_pair = mission_crypto::keygen::generate_ed25519().unwrap();
        let manifest = valid_manifest();
        let json = serde_json::to_vec(&manifest).unwrap();
        let sig = mission_crypto::signing::sign(&key_pair, &json);
        let sig_hex = sig.to_hex();

        let result = verify_manifest_signature(&json, &sig_hex, &[]);
        match result {
            ManifestVerification::UnknownKey(_) => {} // expected
            _ => panic!("expected UnknownKey for no trusted keys"),
        }
    }

    #[test]
    fn verify_malformed_signature_hex() {
        let result = verify_manifest_signature(b"{}", "not-hex", &["deadbeef".into()]);
        assert!(!result.is_trusted());
    }

    // ── ManifestBuilder ────────────────────────────────────────

    #[test]
    fn manifest_builder_creates_valid_manifest() {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        let manifest = ManifestBuilder::new("test-repo")
            .issued_at(now)
            .expires_at(now + 86400)
            .signing_key("test-key")
            .add_package(valid_entry())
            .build();

        assert_eq!(manifest.repository_id, "test-repo");
        assert_eq!(manifest.packages.len(), 1);
        assert!(manifest.validate().is_ok());
    }

    // ── RepositoryManager ──────────────────────────────────────

    #[test]
    fn repository_manager_verify_valid_manifest() {
        let audit = LogAuditBackend;
        let manager = RepositoryManager::new(FreshnessPolicy::default(), Box::new(audit));

        let key_pair = mission_crypto::keygen::generate_ed25519().unwrap();
        let trusted_keys = vec![hex_encode(key_pair.verifying_key.as_bytes().to_vec())];

        let manifest = valid_manifest();
        let json = serde_json::to_vec(&manifest).unwrap();
        let sig = mission_crypto::signing::sign(&key_pair, &json);

        let result =
            manager.verify_manifest(&json, &manifest, &sig.to_hex(), &trusted_keys, "test");
        assert!(result.is_ok());
        let verified = result.unwrap();
        assert!(verified.verification.is_trusted());
    }

    #[test]
    fn repository_manager_rejects_invalid_signature() {
        let audit = LogAuditBackend;
        let manager = RepositoryManager::new(FreshnessPolicy::default(), Box::new(audit));

        let key_pair_a = mission_crypto::keygen::generate_ed25519().unwrap();
        let key_pair_b = mission_crypto::keygen::generate_ed25519().unwrap();
        let trusted_keys = vec![hex_encode(key_pair_b.verifying_key.as_bytes().to_vec())];

        let manifest = valid_manifest();
        let json = serde_json::to_vec(&manifest).unwrap();
        let sig = mission_crypto::signing::sign(&key_pair_a, &json);

        let result =
            manager.verify_manifest(&json, &manifest, &sig.to_hex(), &trusted_keys, "test");
        assert!(result.is_err());
    }

    #[test]
    fn repository_manager_rejects_expired_manifest() {
        let audit = LogAuditBackend;
        let manager = RepositoryManager::new(FreshnessPolicy::default(), Box::new(audit));

        let key_pair = mission_crypto::keygen::generate_ed25519().unwrap();
        let trusted_keys = vec![hex_encode(key_pair.verifying_key.as_bytes().to_vec())];

        let mut manifest = valid_manifest();
        manifest.expires_at = 1; // Expired long ago
        let json = serde_json::to_vec(&manifest).unwrap();
        let sig = mission_crypto::signing::sign(&key_pair, &json);

        let result =
            manager.verify_manifest(&json, &manifest, &sig.to_hex(), &trusted_keys, "test");
        assert!(result.is_err());
    }

    // ── Hex Helpers ────────────────────────────────────────────

    #[test]
    fn hex_decode_valid() {
        let result = hex_decode("deadbeef");
        assert_eq!(result, Some(vec![0xde, 0xad, 0xbe, 0xef]));
    }

    #[test]
    fn hex_decode_odd_length() {
        // 5 hex chars = odd length, should be rejected
        assert_eq!(hex_decode("deadb"), None);
    }

    #[test]
    fn hex_decode_invalid_chars() {
        assert_eq!(hex_decode("zzz"), None);
    }

    #[test]
    fn hex_decode_empty() {
        assert_eq!(hex_decode(""), Some(vec![]));
    }
}
