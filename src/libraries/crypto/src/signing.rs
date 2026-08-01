//! Digital signature creation and verification.
//!
//! Provides Ed25519 signing and verification backed by the `ed25519-dalek`
//! library, a well-audited, pure-Rust implementation.
//!
//! ## Security
//!
//! - Verification distinguishes: valid, invalid, malformed input, unsupported algorithm
//! - Malformed cryptographic material is rejected with clear errors
//! - Key material is not exposed through error messages
//! - Constant-time signature verification

use core::fmt;

use ed25519_dalek::{Signature as DalekSignature, Signer, Verifier};

use crate::error::{CryptoError, CryptoResult};
use crate::keygen::{Ed25519KeyPair, SecretKey};

/// A digital signature (currently Ed25519 only).
///
/// Signatures are not secrets and can be safely cloned, displayed,
/// and shared.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Signature {
    bytes: Vec<u8>,
}

impl Signature {
    /// Create a new signature from raw bytes.
    ///
    /// # Panics
    ///
    /// In debug builds, panics if the byte length does not match the
    /// expected Ed25519 signature size (64 bytes).
    pub fn new(bytes: Vec<u8>) -> Self {
        debug_assert_eq!(
            bytes.len(),
            64,
            "Ed25519 signature must be 64 bytes, got {}",
            bytes.len()
        );
        Self { bytes }
    }

    /// Return the raw signature bytes.
    pub fn as_bytes(&self) -> &[u8] {
        &self.bytes
    }

    /// Convert to a hex string.
    pub fn to_hex(&self) -> String {
        self.bytes.iter().map(|b| format!("{b:02x}")).collect()
    }

    /// Create a signature without length validation (test-only).
    #[cfg(test)]
    #[allow(dead_code)]
    fn new_unchecked(bytes: Vec<u8>) -> Self {
        Self { bytes }
    }
}

impl fmt::Display for Signature {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.to_hex())
    }
}

/// Verification result for a digital signature.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VerificationResult {
    /// Signature is cryptographically valid.
    Valid,
    /// Signature is invalid (tampered or wrong key).
    Invalid,
}

/// Sign a message using an Ed25519 key pair.
///
/// # Arguments
///
/// * `keypair` - The Ed25519 key pair to sign with
/// * `message` - The message bytes to sign
///
/// # Returns
///
/// A `Signature` that can be verified with the corresponding public key.
pub fn sign(keypair: &Ed25519KeyPair, message: &[u8]) -> Signature {
    let dalek_sig: DalekSignature = keypair.signing_key.sign(message);
    Signature::new(dalek_sig.to_bytes().to_vec())
}

/// Sign a message using a raw secret key (Ed25519 seed).
///
/// # Errors
///
/// Returns `InvalidKey` if the key is not the correct length for Ed25519.
pub fn sign_with_secret_key(secret_key: &SecretKey, message: &[u8]) -> CryptoResult<Signature> {
    if secret_key.key_type() != crate::keygen::KeyType::Ed25519 {
        return Err(CryptoError::UnsupportedAlgorithm);
    }

    let bytes: [u8; 32] = secret_key
        .as_bytes()
        .try_into()
        .map_err(|_| CryptoError::InvalidKey)?;

    let signing_key = ed25519_dalek::SigningKey::from_bytes(&bytes);
    let dalek_sig: DalekSignature = signing_key.sign(message);
    Ok(Signature::new(dalek_sig.to_bytes().to_vec()))
}

/// Verify a signature against a message and public key.
///
/// # Arguments
///
/// * `public_key` - The Ed25519 public key bytes (32 bytes)
/// * `message` - The message that was signed
/// * `signature` - The signature to verify
///
/// # Returns
///
/// - `Ok(Valid)` if the signature is cryptographically valid
/// - `Ok(Invalid)` if the signature is invalid (wrong key or tampered message)
/// - `Err(...)` if the input is malformed or an unsupported algorithm is used
pub fn verify(
    public_key: &[u8],
    message: &[u8],
    signature: &Signature,
) -> CryptoResult<VerificationResult> {
    // Validate key length
    if public_key.len() != 32 {
        return Err(CryptoError::InvalidKey);
    }

    // Validate signature length
    if signature.bytes.len() != 64 {
        return Err(CryptoError::InvalidSignature);
    }

    // Parse the verifying key
    let verifying_key = ed25519_dalek::VerifyingKey::from_bytes(
        &public_key.try_into().map_err(|_| CryptoError::InvalidKey)?,
    )
    .map_err(|_| CryptoError::InvalidKey)?;

    // Parse the signature
    let dalek_sig = DalekSignature::from_bytes(
        &signature
            .bytes
            .as_slice()
            .try_into()
            .map_err(|_| CryptoError::InvalidSignature)?,
    );

    // Verify
    match verifying_key.verify(message, &dalek_sig) {
        Ok(()) => Ok(VerificationResult::Valid),
        Err(_) => Ok(VerificationResult::Invalid),
    }
}

/// Verify a signature using a `PublicKey` struct.
pub fn verify_with_public_key(
    public_key: &crate::keygen::PublicKey,
    message: &[u8],
    signature: &Signature,
) -> CryptoResult<VerificationResult> {
    verify(public_key.as_bytes(), message, signature)
}

/// Generate a signature of all zeros (testing purposes only).
///
/// This is NOT a valid signature and will fail verification.
#[cfg(test)]
#[allow(dead_code)]
fn _zero_signature() -> Signature {
    Signature::new(vec![0u8; 64])
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::keygen;

    // -------------------------------------------------------------------
    // Signing and verification roundtrip
    // -------------------------------------------------------------------

    #[test]
    fn sign_and_verify() {
        let pair = keygen::generate_ed25519().unwrap();
        let message = b"hello, mission OS";
        let signature = sign(&pair, message);
        let result = verify(pair.verifying_key.as_bytes(), message, &signature).unwrap();
        assert_eq!(result, VerificationResult::Valid);
    }

    #[test]
    fn sign_and_verify_empty_message() {
        let pair = keygen::generate_ed25519().unwrap();
        let message = b"";
        let signature = sign(&pair, message);
        let result = verify(pair.verifying_key.as_bytes(), message, &signature).unwrap();
        assert_eq!(result, VerificationResult::Valid);
    }

    #[test]
    fn sign_and_verify_large_message() {
        let pair = keygen::generate_ed25519().unwrap();
        let message = vec![0xABu8; 10_000];
        let signature = sign(&pair, &message);
        let result = verify(pair.verifying_key.as_bytes(), &message, &signature).unwrap();
        assert_eq!(result, VerificationResult::Valid);
    }

    // -------------------------------------------------------------------
    // Tampered data
    // -------------------------------------------------------------------

    #[test]
    fn verify_tampered_message() {
        let pair = keygen::generate_ed25519().unwrap();
        let signature = sign(&pair, b"original message");
        let result = verify(
            pair.verifying_key.as_bytes(),
            b"tampered message",
            &signature,
        )
        .unwrap();
        assert_eq!(result, VerificationResult::Invalid);
    }

    #[test]
    fn verify_tampered_signature() {
        let pair = keygen::generate_ed25519().unwrap();
        let mut signature = sign(&pair, b"test message");
        signature.bytes[0] ^= 0x01;
        let result = verify(pair.verifying_key.as_bytes(), b"test message", &signature).unwrap();
        assert_eq!(result, VerificationResult::Invalid);
    }

    // -------------------------------------------------------------------
    // Wrong key
    // -------------------------------------------------------------------

    #[test]
    fn verify_wrong_key() {
        let pair_a = keygen::generate_ed25519().unwrap();
        let pair_b = keygen::generate_ed25519().unwrap();
        let message = b"secret message";
        let signature = sign(&pair_a, message);
        let result = verify(pair_b.verifying_key.as_bytes(), message, &signature).unwrap();
        assert_eq!(result, VerificationResult::Invalid);
    }

    // -------------------------------------------------------------------
    // Malformed input
    // -------------------------------------------------------------------

    #[test]
    fn verify_short_public_key() {
        let pair = keygen::generate_ed25519().unwrap();
        let signature = sign(&pair, b"test");
        let result = verify(&[0u8; 16], b"test", &signature);
        assert!(result.is_err());
        assert_eq!(result.unwrap_err(), CryptoError::InvalidKey);
    }

    #[test]
    fn verify_long_public_key() {
        let pair = keygen::generate_ed25519().unwrap();
        let signature = sign(&pair, b"test");
        let result = verify(&[0u8; 64], b"test", &signature);
        assert!(result.is_err());
    }

    #[test]
    fn verify_short_signature() {
        let pair = keygen::generate_ed25519().unwrap();
        let sig = sign(&pair, b"test");
        let short_bytes = sig.bytes[..32].to_vec();
        // Directly create a Signature struct without validation for testing
        let result = verify(
            pair.verifying_key.as_bytes(),
            b"test",
            &Signature { bytes: short_bytes },
        );
        assert!(result.is_err());
        assert_eq!(result.unwrap_err(), CryptoError::InvalidSignature);
    }

    #[test]
    fn verify_zero_signature() {
        let pair = keygen::generate_ed25519().unwrap();
        let zero_sig = Signature::new(vec![0u8; 64]);
        let result = verify(pair.verifying_key.as_bytes(), b"test", &zero_sig).unwrap();
        assert_eq!(result, VerificationResult::Invalid);
    }

    // -------------------------------------------------------------------
    // Sign with secret key
    // -------------------------------------------------------------------

    #[test]
    fn sign_with_secret_key_and_verify() {
        let pair = keygen::generate_ed25519().unwrap();
        let seed_bytes = pair.signing_key.to_bytes();
        let secret_key = SecretKey::new(keygen::KeyType::Ed25519, seed_bytes.to_vec());
        let message = b"signed with secret key";
        let signature = sign_with_secret_key(&secret_key, message).unwrap();
        let result = verify(pair.verifying_key.as_bytes(), message, &signature).unwrap();
        assert_eq!(result, VerificationResult::Valid);
    }

    #[test]
    fn sign_with_wrong_key_type() {
        let secret_key = keygen::generate_symmetric(keygen::KeyType::Symmetric).unwrap();
        let result = sign_with_secret_key(&secret_key, b"test");
        assert!(result.is_err());
        assert_eq!(result.unwrap_err(), CryptoError::UnsupportedAlgorithm);
    }

    // -------------------------------------------------------------------
    // Signature display/formatting (using full 64-byte buffers)
    // -------------------------------------------------------------------

    #[test]
    fn signature_display_with_real_sig() {
        let pair = keygen::generate_ed25519().unwrap();
        let sig = sign(&pair, b"display test");
        let hex = sig.to_hex();
        assert_eq!(hex.len(), 128); // 64 bytes * 2 hex chars
        assert_eq!(sig.to_string(), hex);
    }

    #[test]
    fn signature_from_real_bytes() {
        // Generate a real 64-byte signature, then test hex conversion
        let pair = keygen::generate_ed25519().unwrap();
        let sig = sign(&pair, b"test");
        let full_hex = sig.to_hex();
        assert_eq!(full_hex.len(), 128);
    }

    // -------------------------------------------------------------------
    // PublicKey verify wrapper
    // -------------------------------------------------------------------

    #[test]
    fn verify_with_public_key_struct() {
        let pair = keygen::generate_ed25519().unwrap();
        let pub_key = keygen::PublicKey::new(
            keygen::KeyType::Ed25519,
            pair.verifying_key.as_bytes().to_vec(),
        );
        let message = b"test via struct";
        let signature = sign(&pair, message);
        let result = verify_with_public_key(&pub_key, message, &signature).unwrap();
        assert_eq!(result, VerificationResult::Valid);
    }
}
