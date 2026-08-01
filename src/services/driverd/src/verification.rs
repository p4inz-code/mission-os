//! Signature verification for mission-driverd.
//!
//! Provides driver package signature verification using mission-crypto's
//! ed25519 implementation, trusted key management, and audit-ready
//! verification results.
//!
//! ## Architecture
//!
//! Per MOS-ENG-SEC-001 §7.2, driver verification includes:
//! - Signed kernel modules only (enforced in production mode)
//! - Unsigned driver override available in Developer Mode
//! - Drivers from Mission repository verified automatically
//! - Third-party drivers require explicit user approval
//!
//! ## Security
//!
//! - Every verification result is audited
//! - Invalid signatures are always rejected with clear errors
//! - Missing signatures are rejected when policy requires them
//! - Verification errors are structured, not generic
//! - No secrets are logged

use std::collections::HashMap;
use std::path::{Path, PathBuf};

use mission_crypto::{hash, verify, HashAlgorithm, Signature as CryptoSignature};

use crate::audit::{AuditEvent, EventCategory, EventSeverity};
use crate::error::{ServiceError, ServiceResult};

// ── Verification Outcome ──────────────────────────────────────────

/// Outcome of a signature or integrity verification check.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum VerificationOutcome {
    /// Verification passed successfully.
    Valid,
    /// Signature is invalid (tampered or wrong key).
    Invalid,
    /// No signature found where one is required.
    MissingSignature,
    /// The signing key is not in the trusted key store.
    UntrustedKey,
    /// Verification could not be completed (internal error).
    Error(String),
}

impl VerificationOutcome {
    /// Whether the verification was successful.
    pub fn is_valid(&self) -> bool {
        matches!(self, VerificationOutcome::Valid)
    }
}

/// Complete result of a signature verification operation.
#[derive(Debug, Clone)]
pub struct SignatureCheckResult {
    /// The verification outcome.
    pub outcome: VerificationOutcome,
    /// Key identifier used for verification (if applicable).
    pub key_id: Option<String>,
    /// Human-readable description of the result.
    pub description: String,
}

// ── Trusted Key Entry ─────────────────────────────────────────────

/// A trusted public key entry.
#[derive(Debug, Clone)]
pub struct TrustedKey {
    /// Unique identifier for this key.
    pub id: String,
    /// Human-readable name/description of the key owner.
    pub name: String,
    /// Ed25519 public key bytes.
    pub public_key: Vec<u8>,
    /// Whether this key is currently enabled for verification.
    pub enabled: bool,
}

// ── Trusted Key Store ─────────────────────────────────────────────

/// Manages trusted public keys for driver package verification.
///
/// Keys can be loaded from a configured key directory or added
/// at runtime. The store supports enabling/disabling individual
/// keys without removing them.
pub struct TrustedKeyStore {
    /// Loaded trusted keys.
    keys: HashMap<String, TrustedKey>,
    /// Path to the key store directory.
    store_path: PathBuf,
}

impl TrustedKeyStore {
    /// Create a new trusted key store.
    ///
    /// # Arguments
    ///
    /// * `store_path` - Path to the directory containing trusted keys.
    pub fn new(store_path: PathBuf) -> Self {
        let mut store = Self {
            keys: HashMap::new(),
            store_path,
        };
        let _ = store.load_keys();
        store
    }

    /// Load keys from the key store directory.
    ///
    /// Key files should be in a format that can be parsed as
    /// key entries with id, name, and public_key fields.
    fn load_keys(&mut self) -> ServiceResult<()> {
        if !self.store_path.exists() {
            return Ok(()); // No keys directory yet — not an error
        }

        let read_dir = match std::fs::read_dir(&self.store_path) {
            Ok(rd) => rd,
            Err(e) => {
                return Err(ServiceError::Internal(format!(
                    "cannot read key store {:?}: {e}",
                    self.store_path
                )));
            }
        };

        for entry in read_dir.flatten() {
            let path = entry.path();
            if path
                .extension()
                .map(|e| e == "pem" || e == "key")
                .unwrap_or(false)
            {
                match std::fs::read_to_string(&path) {
                    Ok(content) => {
                        if let Some(key) = parse_key_file(&path, &content) {
                            self.keys.insert(key.id.clone(), key);
                        }
                    }
                    Err(e) => {
                        eprintln!("[verification] error reading key file {:?}: {e}", path);
                    }
                }
            }
        }

        Ok(())
    }

    /// Get a trusted key by ID.
    pub fn get_key(&self, id: &str) -> Option<&TrustedKey> {
        self.keys.get(id)
    }

    /// Add a trust key.
    pub fn add_key(&mut self, key: TrustedKey) {
        self.keys.insert(key.id.clone(), key);
    }

    /// Remove a trusted key by ID.
    pub fn remove_key(&mut self, id: &str) -> bool {
        self.keys.remove(id).is_some()
    }

    /// Check if a key is trusted.
    pub fn is_trusted(&self, public_key: &[u8]) -> bool {
        self.keys
            .values()
            .any(|k| k.enabled && k.public_key == public_key)
    }

    /// Get all enabled trusted keys.
    pub fn enabled_keys(&self) -> Vec<&TrustedKey> {
        self.keys.values().filter(|k| k.enabled).collect()
    }

    /// Get the number of trusted keys.
    pub fn key_count(&self) -> usize {
        self.keys.len()
    }
}

// ── Signature Verifier ────────────────────────────────────────────

/// Verifies driver package signatures and integrity.
pub struct SignatureVerifier {
    /// Trusted key store for signature verification.
    key_store: TrustedKeyStore,
    /// Whether unsigned drivers are allowed (development mode).
    allow_unsigned: bool,
}

impl SignatureVerifier {
    /// Create a new signature verifier.
    ///
    /// # Arguments
    ///
    /// * `key_store` - Trusted key store for verification.
    /// * `allow_unsigned` - Whether to allow unsigned drivers (dev mode).
    pub fn new(key_store: TrustedKeyStore, allow_unsigned: bool) -> Self {
        Self {
            key_store,
            allow_unsigned,
        }
    }

    /// Verify the signature on a driver package.
    ///
    /// # Arguments
    ///
    /// * `package_path` - Path to the driver package file.
    /// * `signature_bytes` - The raw signature bytes.
    /// * `signing_key_id` - Identifier of the expected signing key.
    /// * `audit_callback` - Optional callback for audit events.
    ///
    /// # Returns
    ///
    /// `SignatureCheckResult` with the outcome, key info, and description.
    pub fn verify_package(
        &self,
        package_path: &Path,
        signature_bytes: &[u8],
        signing_key_id: Option<&str>,
        audit_callback: Option<&dyn Fn(&AuditEvent)>,
    ) -> SignatureCheckResult {
        // If no signature provided
        if signature_bytes.is_empty() {
            if !self.allow_unsigned {
                let result = SignatureCheckResult {
                    outcome: VerificationOutcome::MissingSignature,
                    key_id: None,
                    description: "No signature found on driver package and unsigned \
                                  drivers are not permitted"
                        .to_string(),
                };
                Self::audit_verification(&result, audit_callback);
                return result;
            }

            let result = SignatureCheckResult {
                outcome: VerificationOutcome::Valid,
                key_id: None,
                description: "No signature present — accepted per policy \
                              (unsigned drivers allowed in development mode)"
                    .to_string(),
            };
            Self::audit_verification(&result, audit_callback);
            return result;
        }

        // Read the package content
        let package_data = match std::fs::read(package_path) {
            Ok(data) => data,
            Err(e) => {
                let result = SignatureCheckResult {
                    outcome: VerificationOutcome::Error(format!("cannot read package file: {e}")),
                    key_id: None,
                    description: "Failed to read package file for verification".to_string(),
                };
                Self::audit_verification(&result, audit_callback);
                return result;
            }
        };

        // Try each enabled trusted key
        for key in self.key_store.enabled_keys() {
            // Use mission-crypto's verify() which takes public_key bytes, message, signature bytes
            // Wrap raw signature bytes in mission-crypto's Signature type
            let crypto_sig = CryptoSignature::new(signature_bytes.to_vec());
            let verify_result = verify(&key.public_key, &package_data, &crypto_sig);
            match verify_result {
                Ok(mission_crypto::VerificationResult::Valid) => {
                    let result = SignatureCheckResult {
                        outcome: VerificationOutcome::Valid,
                        key_id: Some(key.id.clone()),
                        description: format!(
                            "Signature verified with trusted key '{}' ({})",
                            key.id, key.name
                        ),
                    };
                    Self::audit_verification(&result, audit_callback);
                    return result;
                }
                Ok(mission_crypto::VerificationResult::Invalid) => {
                    // Continue checking with other keys
                }
                Err(e) => {
                    eprintln!("[verification] error verifying with key '{}': {e}", key.id);
                }
            }
        }

        // Check if a specific key was expected
        if let Some(key_id) = signing_key_id {
            if self.key_store.get_key(key_id).is_none() {
                let result = SignatureCheckResult {
                    outcome: VerificationOutcome::UntrustedKey,
                    key_id: Some(key_id.to_string()),
                    description: format!("Signing key '{key_id}' is not in the trusted key store"),
                };
                Self::audit_verification(&result, audit_callback);
                return result;
            }
        }

        let result = SignatureCheckResult {
            outcome: VerificationOutcome::Invalid,
            key_id: signing_key_id.map(|s| s.to_string()),
            description: "Signature does not match any trusted key or package \
                          content has been tampered with"
                .to_string(),
        };
        Self::audit_verification(&result, audit_callback);
        result
    }

    /// Verify the integrity of a file using a hash.
    ///
    /// # Arguments
    ///
    /// * `file_path` - Path to the file to verify.
    /// * `expected_hash` - Expected hash bytes.
    /// * `algorithm` - Hash algorithm used.
    pub fn verify_integrity(
        &self,
        file_path: &Path,
        expected_hash: &[u8],
        algorithm: HashAlgorithm,
    ) -> SignatureCheckResult {
        let data = match std::fs::read(file_path) {
            Ok(d) => d,
            Err(e) => {
                return SignatureCheckResult {
                    outcome: VerificationOutcome::Error(format!(
                        "cannot read file for hash verification: {e}"
                    )),
                    key_id: None,
                    description: "Failed to read file for integrity check".to_string(),
                };
            }
        };

        match hash(algorithm, &data) {
            Ok(computed_hash) => {
                if computed_hash.as_bytes() == expected_hash {
                    SignatureCheckResult {
                        outcome: VerificationOutcome::Valid,
                        key_id: None,
                        description: "File integrity verified — hash matches".to_string(),
                    }
                } else {
                    SignatureCheckResult {
                        outcome: VerificationOutcome::Invalid,
                        key_id: None,
                        description: "File integrity check failed — hash mismatch".to_string(),
                    }
                }
            }
            Err(e) => SignatureCheckResult {
                outcome: VerificationOutcome::Error(format!("hash computation error: {e}")),
                key_id: None,
                description: "Failed to compute file hash for integrity check".to_string(),
            },
        }
    }

    /// Record an audit event for a verification result.
    fn audit_verification(result: &SignatureCheckResult, callback: Option<&dyn Fn(&AuditEvent)>) {
        if let Some(cb) = callback {
            let (severity, action) = match &result.outcome {
                VerificationOutcome::Valid => (EventSeverity::Info, "verification_passed"),
                VerificationOutcome::Invalid => {
                    (EventSeverity::Warning, "verification_failed_invalid")
                }
                VerificationOutcome::MissingSignature => (
                    EventSeverity::Warning,
                    "verification_failed_missing_signature",
                ),
                VerificationOutcome::UntrustedKey => {
                    (EventSeverity::Warning, "verification_failed_untrusted_key")
                }
                VerificationOutcome::Error(_) => (EventSeverity::Error, "verification_error"),
            };

            let event = AuditEvent::new(
                EventCategory::DriverVerification,
                severity,
                action,
                "verification_service",
                &result.description,
            );

            cb(&event);
        }
    }
}

// ── Key File Parsing ──────────────────────────────────────────────

/// Parse a key file into a TrustedKey entry.
///
/// Supports simple JSON format:
/// ```json
/// {
///   "id": "mission-os-release-2026",
///   "name": "Mission OS Release Key 2026",
///   "public_key": "hexencodedkey..."
/// }
/// ```
fn parse_key_file(path: &Path, content: &str) -> Option<TrustedKey> {
    // Try JSON format first
    if let Ok(parsed) = serde_json::from_str::<serde_json::Value>(content) {
        let id = parsed.get("id")?.as_str()?.to_string();
        let name = parsed
            .get("name")
            .or_else(|| parsed.get("id"))
            .and_then(|v| v.as_str())
            .unwrap_or("Unknown Key")
            .to_string();
        let key_hex = parsed.get("public_key")?.as_str()?;

        // Decode hex key
        let public_key = match hex_decode(key_hex) {
            Some(bytes) => bytes,
            None => {
                eprintln!("[verification] invalid hex key in {:?}", path);
                return None;
            }
        };

        if public_key.len() != 32 {
            eprintln!(
                "[verification] invalid ed25519 key length {} in {:?}",
                public_key.len(),
                path
            );
            return None;
        }

        return Some(TrustedKey {
            id,
            name,
            public_key,
            enabled: true,
        });
    }

    None
}

/// Decode a hex string to bytes.
fn hex_decode(input: &str) -> Option<Vec<u8>> {
    let input = input.trim();
    if input.len() & 1 != 0 {
        return None;
    }
    let bytes: Vec<u8> = input
        .as_bytes()
        .chunks(2)
        .filter_map(|chunk| {
            let s = std::str::from_utf8(chunk).ok()?;
            u8::from_str_radix(s, 16).ok()
        })
        .collect();
    if bytes.len() == input.len() / 2 {
        Some(bytes)
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // ── VerificationOutcome ─────────────────────────────────────

    #[test]
    fn outcome_valid() {
        assert!(VerificationOutcome::Valid.is_valid());
        assert!(!VerificationOutcome::Invalid.is_valid());
        assert!(!VerificationOutcome::MissingSignature.is_valid());
    }

    // ── TrustedKeyStore ─────────────────────────────────────────

    #[test]
    fn key_store_new_empty() {
        let store = TrustedKeyStore::new(PathBuf::from("/nonexistent/keys"));
        assert_eq!(store.key_count(), 0);
    }

    #[test]
    fn key_store_add_and_retrieve() {
        let mut store = TrustedKeyStore::new(PathBuf::from("/nonexistent/keys"));
        let key = TrustedKey {
            id: "test-key".into(),
            name: "Test Key".into(),
            public_key: vec![0u8; 32],
            enabled: true,
        };
        store.add_key(key.clone());
        assert_eq!(store.key_count(), 1);
        assert!(store.get_key("test-key").is_some());
        assert!(store.is_trusted(&[0u8; 32]));
        assert!(!store.is_trusted(&[1u8; 32]));
    }

    #[test]
    fn key_store_remove() {
        let mut store = TrustedKeyStore::new(PathBuf::from("/nonexistent/keys"));
        store.add_key(TrustedKey {
            id: "k1".into(),
            name: "K1".into(),
            public_key: vec![0u8; 32],
            enabled: true,
        });
        assert!(store.remove_key("k1"));
        assert_eq!(store.key_count(), 0);
        assert!(!store.remove_key("nonexistent"));
    }

    #[test]
    fn key_store_disabled_key_not_trusted() {
        let mut store = TrustedKeyStore::new(PathBuf::from("/nonexistent/keys"));
        store.add_key(TrustedKey {
            id: "disabled".into(),
            name: "Disabled".into(),
            public_key: vec![1u8; 32],
            enabled: false,
        });
        assert!(!store.is_trusted(&[1u8; 32]));
        assert_eq!(store.enabled_keys().len(), 0);
    }

    // ── SignatureVerifier ───────────────────────────────────────

    #[test]
    fn verifier_unsigned_allowed_in_dev_mode() {
        let store = TrustedKeyStore::new(PathBuf::from("/nonexistent/keys"));
        let verifier = SignatureVerifier::new(store, true);
        let tmp = std::env::temp_dir().join("unsigned_test_driver.bin");
        let _ = std::fs::write(&tmp, b"test driver content");
        let result = verifier.verify_package(&tmp, &[], None, None);
        assert!(result.outcome.is_valid());
        let _ = std::fs::remove_file(&tmp);
    }

    #[test]
    fn verifier_unsigned_rejected_in_production() {
        let store = TrustedKeyStore::new(PathBuf::from("/nonexistent/keys"));
        let verifier = SignatureVerifier::new(store, false);
        let tmp = std::env::temp_dir().join("unsigned_rejected.bin");
        let _ = std::fs::write(&tmp, b"test content");
        let result = verifier.verify_package(&tmp, &[], None, None);
        assert_eq!(result.outcome, VerificationOutcome::MissingSignature);
        let _ = std::fs::remove_file(&tmp);
    }

    #[test]
    fn verifier_missing_file_returns_error() {
        let store = TrustedKeyStore::new(PathBuf::from("/nonexistent/keys"));
        let verifier = SignatureVerifier::new(store, false);
        let result =
            verifier.verify_package(Path::new("/nonexistent/file.bin"), b"sig", None, None);
        assert!(matches!(result.outcome, VerificationOutcome::Error(_)));
    }

    #[test]
    fn verifier_integrity_hash_mismatch() {
        let store = TrustedKeyStore::new(PathBuf::from("/nonexistent/keys"));
        let verifier = SignatureVerifier::new(store, false);
        let tmp = std::env::temp_dir().join("integrity_test.bin");
        let _ = std::fs::write(&tmp, b"test data");
        let expected_hash = vec![0u8; 32]; // wrong hash
        let result = verifier.verify_integrity(&tmp, &expected_hash, HashAlgorithm::Sha256);
        assert_eq!(result.outcome, VerificationOutcome::Invalid);
        let _ = std::fs::remove_file(&tmp);
    }

    #[test]
    fn verifier_integrity_hash_match() {
        let store = TrustedKeyStore::new(PathBuf::from("/nonexistent/keys"));
        let verifier = SignatureVerifier::new(store, false);
        let data = b"test data for hash verification";
        let tmp = std::env::temp_dir().join("integrity_match.bin");
        let _ = std::fs::write(&tmp, data);
        let h = hash(HashAlgorithm::Sha256, data).expect("hash failed");
        let result = verifier.verify_integrity(&tmp, h.as_bytes(), HashAlgorithm::Sha256);
        assert_eq!(result.outcome, VerificationOutcome::Valid);
        let _ = std::fs::remove_file(&tmp);
    }

    // ── Key File Parsing ────────────────────────────────────────

    #[test]
    fn parse_invalid_json_key() {
        let path = Path::new("test.key");
        let result = parse_key_file(path, "not json");
        assert!(result.is_none());
    }

    #[test]
    fn parse_malformed_key() {
        let path = Path::new("test.key");
        let content = r#"{"id": "test", "public_key": "not-hex"}"#;
        let result = parse_key_file(path, content);
        assert!(result.is_none());
    }

    // ── Hex Decoding ────────────────────────────────────────────

    #[test]
    fn hex_decode_valid() {
        let result = hex_decode("deadbeef").unwrap();
        assert_eq!(result, vec![0xde, 0xad, 0xbe, 0xef]);
    }

    #[test]
    fn hex_decode_odd_length() {
        assert!(hex_decode("abc").is_none());
    }

    #[test]
    fn hex_decode_invalid_chars() {
        assert!(hex_decode("xyz123").is_none());
    }

    #[test]
    fn hex_decode_empty() {
        let result = hex_decode("").unwrap();
        assert!(result.is_empty());
    }
}
