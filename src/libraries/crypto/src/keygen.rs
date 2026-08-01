//! Key generation (symmetric and asymmetric).
//!
//! Provides production-safe key generation using the operating system's
//! CSPRNG via `SecureRng`.
//!
//! ## Security
//!
//! - All key material is generated from the OS CSPRNG
//! - SecretKey's Debug intentionally omits key bytes
//! - SecretKey implements manual Drop for secure memory clearing
//! - Clone is intentionally not implemented to prevent accidental copies

use core::fmt;

use ed25519_dalek::{SigningKey, VerifyingKey};

use crate::error::{CryptoError, CryptoResult};
use crate::rng::SecureRng;

/// Type of key to generate.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[non_exhaustive]
pub enum KeyType {
    /// Symmetric key (e.g., AES-256).
    Symmetric,
    /// Ed25519 key pair.
    Ed25519,
}

impl KeyType {
    /// Return the expected key size in bytes for this key type.
    pub fn key_size(&self) -> usize {
        match self {
            KeyType::Symmetric => 32, // 256 bits
            KeyType::Ed25519 => 32,   // 256-bit seed
        }
    }
}

/// A secret/private cryptographic key.
///
/// The key bytes are zeroed on drop. Debug output shows only the
/// key type, not the key material.
///
/// # Security
///
/// - `Debug` does NOT expose key bytes
/// - `Drop` zeroes the key material
/// - `Clone` is intentionally not implemented to prevent accidental copies
#[must_use]
pub struct SecretKey {
    key_type: KeyType,
    bytes: Box<[u8]>,
}

impl SecretKey {
    /// Create a new secret key from raw bytes.
    ///
    /// The caller is responsible for ensuring:
    /// - `bytes` contains valid key material of the appropriate length
    /// - `bytes` is zeroed after use if the source is no longer needed
    ///
    /// # Panics
    ///
    /// In debug builds, panics if the byte length does not match the
    /// expected key size for the given key type.
    pub fn new(key_type: KeyType, bytes: Vec<u8>) -> Self {
        debug_assert_eq!(
            bytes.len(),
            key_type.key_size(),
            "Key byte length {} does not match expected size {} for {:?}",
            bytes.len(),
            key_type.key_size(),
            key_type
        );
        Self {
            key_type,
            bytes: bytes.into_boxed_slice(),
        }
    }

    /// Return the key type.
    pub fn key_type(&self) -> KeyType {
        self.key_type
    }

    /// Return the key material.
    ///
    /// # Security
    ///
    /// The returned slice references memory that will be zeroed on drop.
    /// Callers should not make persistent copies of this data.
    pub fn as_bytes(&self) -> &[u8] {
        &self.bytes
    }
}

impl Drop for SecretKey {
    fn drop(&mut self) {
        // Zeroize the key bytes before freeing
        use zeroize::Zeroize;
        self.bytes.zeroize();
    }
}

impl fmt::Debug for SecretKey {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("SecretKey")
            .field("key_type", &self.key_type)
            .field("bytes", &"[REDACTED]")
            .finish()
    }
}

/// A public key for signature verification.
///
/// Public keys are not secrets and can be safely displayed, cloned,
/// and shared.
#[derive(Debug, Clone)]
pub struct PublicKey {
    key_type: KeyType,
    bytes: Vec<u8>,
}

impl PublicKey {
    /// Create a new public key from raw bytes.
    ///
    /// # Panics
    ///
    /// In debug builds, panics if the byte length does not match the
    /// expected size for the given algorithm.
    pub fn new(key_type: KeyType, bytes: Vec<u8>) -> Self {
        let expected = match key_type {
            KeyType::Symmetric => 32,
            KeyType::Ed25519 => 32,
        };
        debug_assert_eq!(
            bytes.len(),
            expected,
            "public key length {} does not match expected {}",
            bytes.len(),
            expected
        );
        Self { key_type, bytes }
    }

    /// Return the key type.
    pub fn key_type(&self) -> KeyType {
        self.key_type
    }

    /// Return the key material.
    pub fn as_bytes(&self) -> &[u8] {
        &self.bytes
    }
}

/// An Ed25519 key pair containing both the secret signing key and
/// the public verifying key.
///
/// # Security
///
/// - `Debug` does NOT expose secret key bytes
/// - The signing key is zeroed on drop (ed25519-dalek implements Zeroize)
#[must_use]
pub struct Ed25519KeyPair {
    /// The secret signing key.
    pub signing_key: SigningKey,
    /// The public verifying key.
    pub verifying_key: VerifyingKey,
}

impl fmt::Debug for Ed25519KeyPair {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Ed25519KeyPair")
            .field("verifying_key", &self.verifying_key)
            .finish_non_exhaustive()
    }
}

// ---------------------------------------------------------------------------
// Key generation functions
// ---------------------------------------------------------------------------

/// Generate a symmetric key of the given type.
///
/// The key is generated from the OS CSPRNG and zeroed on drop.
pub fn generate_symmetric(key_type: KeyType) -> CryptoResult<SecretKey> {
    let rng = SecureRng::new();
    let size = key_type.key_size();
    let bytes = rng.random_vec(size)?;
    Ok(SecretKey::new(key_type, bytes))
}

/// Generate an Ed25519 key pair.
///
/// The signing key is generated from the OS CSPRNG and zeroed on drop.
/// The verifying key is derived from the signing key.
pub fn generate_ed25519() -> CryptoResult<Ed25519KeyPair> {
    let rng = SecureRng::new();
    let seed = rng.random_vec(32)?;

    let seed_array: [u8; 32] = seed
        .as_slice()
        .try_into()
        .map_err(|_| CryptoError::Internal("unexpected seed length for Ed25519".into()))?;

    let signing_key = SigningKey::from_bytes(&seed_array);

    // Zero the seed bytes since we no longer need them
    use zeroize::Zeroize;
    let mut seed_mut = seed;
    seed_mut.zeroize();

    let verifying_key = signing_key.verifying_key();

    Ok(Ed25519KeyPair {
        signing_key,
        verifying_key,
    })
}

/// Generate a key of the given type.
///
/// This is a convenience function that dispatches to the appropriate
/// key generation function based on the key type.
pub fn generate_key(key_type: KeyType) -> CryptoResult<SecretKey> {
    match key_type {
        KeyType::Symmetric => generate_symmetric(key_type),
        KeyType::Ed25519 => {
            let pair = generate_ed25519()?;
            let seed_bytes = pair.signing_key.to_bytes();
            Ok(SecretKey::new(KeyType::Ed25519, seed_bytes.to_vec()))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // -------------------------------------------------------------------
    // Symmetric key generation
    // -------------------------------------------------------------------

    #[test]
    fn generate_symmetric_key() {
        let key = generate_symmetric(KeyType::Symmetric).unwrap();
        assert_eq!(key.key_type(), KeyType::Symmetric);
        assert_eq!(key.as_bytes().len(), 32);
    }

    #[test]
    fn generate_symmetric_unique() {
        let a = generate_symmetric(KeyType::Symmetric).unwrap();
        let b = generate_symmetric(KeyType::Symmetric).unwrap();
        assert_ne!(a.as_bytes(), b.as_bytes());
    }

    // -------------------------------------------------------------------
    // Ed25519 key pair generation
    // -------------------------------------------------------------------

    #[test]
    fn generate_ed25519_pair() {
        let pair = generate_ed25519().unwrap();
        assert_eq!(pair.verifying_key.as_bytes().len(), 32);
    }

    #[test]
    fn generate_ed25519_unique() {
        let a = generate_ed25519().unwrap();
        let b = generate_ed25519().unwrap();
        assert_ne!(a.verifying_key.as_bytes(), b.verifying_key.as_bytes());
    }

    #[test]
    fn ed25519_keypair_sign_verify() {
        use ed25519_dalek::Signer;
        use ed25519_dalek::Verifier;

        let pair = generate_ed25519().unwrap();
        let msg = b"test message for key pair";
        let signature = pair.signing_key.sign(msg);
        assert!(pair.verifying_key.verify(msg, &signature).is_ok());
    }

    // -------------------------------------------------------------------
    // SecretKey Debug (no leakage)
    // -------------------------------------------------------------------

    #[test]
    fn secret_key_debug_redacts() {
        let key = generate_symmetric(KeyType::Symmetric).unwrap();
        let debug = format!("{key:?}");
        assert!(debug.contains("REDACTED"));
    }

    #[test]
    fn public_key_debug() {
        let pair = generate_ed25519().unwrap();
        let pub_key = PublicKey::new(KeyType::Ed25519, pair.verifying_key.as_bytes().to_vec());
        let debug = format!("{pub_key:?}");
        assert!(debug.contains("PublicKey"));
    }

    // -------------------------------------------------------------------
    // Key size validation
    // -------------------------------------------------------------------

    #[test]
    fn key_type_sizes() {
        assert_eq!(KeyType::Symmetric.key_size(), 32);
        assert_eq!(KeyType::Ed25519.key_size(), 32);
    }

    // -------------------------------------------------------------------
    // Ed25519KeyPair Debug (no leakage)
    // -------------------------------------------------------------------

    #[test]
    fn ed25519_keypair_debug_redacts() {
        let pair = generate_ed25519().unwrap();
        let debug = format!("{pair:?}");
        assert!(debug.contains("Ed25519KeyPair"));
        assert!(debug.contains("verifying_key"));
    }

    // -------------------------------------------------------------------
    // generate_key wrapper
    // -------------------------------------------------------------------

    #[test]
    fn generate_key_symmetric() {
        let key = generate_key(KeyType::Symmetric).unwrap();
        assert_eq!(key.as_bytes().len(), 32);
    }

    #[test]
    fn generate_key_ed25519() {
        let key = generate_key(KeyType::Ed25519).unwrap();
        assert_eq!(key.as_bytes().len(), 32);
        assert_eq!(key.key_type(), KeyType::Ed25519);
    }
}
