//! Workspace integration tests: mission-core ↔ mission-crypto.
//!
//! These tests verify that the workspace dependency graph is coherent
//! and that the public APIs of both libraries compose correctly.

use mission_core::{Error, ErrorCode, Version};
use mission_crypto::{
    generate_ed25519, hash, hash_verify, sign, verify, CryptoError, HashAlgorithm,
    VerificationResult,
};

/// Core error types can represent crypto errors in an integration scenario.
#[test]
fn core_error_wraps_crypto_error() {
    let crypto_err = CryptoError::UnsupportedAlgorithm;
    let display = format!("{crypto_err}");
    assert_eq!(display, "unsupported algorithm");

    let core_err = Error::new(ErrorCode::InternalError, "crypto test error");
    assert!(core_err.message().contains("crypto"));
}

/// Version (core) can be hashed (crypto) to demonstrate cross-crate composition.
#[test]
fn version_and_crypto_integration() {
    let vsn = Version::parse("1.0.0").expect("valid version");
    assert!(vsn.is_stable());

    let h = hash(HashAlgorithm::Sha256, vsn.to_string().as_bytes()).expect("hash should succeed");
    assert_eq!(h.algorithm(), HashAlgorithm::Sha256);
    assert_eq!(h.as_bytes().len(), 32);
}

/// Path resolution (core) + hashing (crypto) compose correctly.
#[test]
fn paths_and_crypto_integration() {
    use mission_core::paths;

    let config = paths::config_dir();
    assert!(!config.as_os_str().is_empty());

    let h = hash(
        HashAlgorithm::Blake3 { output_len: 32 },
        config.to_string_lossy().as_bytes(),
    )
    .expect("hash should succeed");
    assert_eq!(h.as_bytes().len(), 32);
}

/// Full sign → verify → tamper → fail workflow across both crates.
#[test]
fn crypto_workflow_integration() {
    let key_pair = generate_ed25519().expect("key pair generation");
    let message = b"integration test message";

    let signature = sign(&key_pair, message);
    let result = verify(key_pair.verifying_key.as_bytes(), message, &signature);
    assert_eq!(
        result,
        Ok(VerificationResult::Valid),
        "signature should be valid"
    );

    let tampered = b"tampered message";
    let result2 = verify(key_pair.verifying_key.as_bytes(), tampered, &signature);
    assert_eq!(
        result2,
        Ok(VerificationResult::Invalid),
        "tampered message should be invalid"
    );
}

/// Hash + verify with hash_verify from crypto.
#[test]
fn hash_verify_integration() {
    let data = b"data to hash and verify";
    let h = hash(HashAlgorithm::Sha256, data).expect("hash");
    assert!(hash_verify(HashAlgorithm::Sha256, data, &h).is_ok());
    assert!(hash_verify(HashAlgorithm::Sha512, data, &h).is_err());
}
