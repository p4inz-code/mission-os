//! # mission-crypto
//!
//! Cryptographic operations shared across Mission OS.
//!
//! Provides key generation, hashing, signing/verification, secure memory
//! handling, and random number generation for all privileged services.
//!
//! ## Safety
//!
//! This crate wraps cryptographically sensitive operations.
//! All unsafe code is confined to implementation modules and
//! reviewed separately. Public API surface is safe.
//!
//! ## Security
//!
//! - Key material is zeroed on drop.
//! - Memory is locked to prevent swapping.
//! - All operations are constant-time where applicable.

#![deny(missing_docs)]
#![deny(unreachable_pub)]
#![deny(unsafe_code)]
// Note: secure_memory module uses `#[allow(unsafe_code)]` for platform-level
// mlock/munlock FFI. Each unsafe block has a SAFETY justification.

/// Hash computation utilities.
pub mod hash;

/// Secure random number generation.
pub mod rng;

/// Key generation (symmetric and asymmetric).
pub mod keygen;

/// Digital signature creation and verification.
pub mod signing;

/// Secure memory handling (mlock, zeroize).
pub mod secure_memory;

/// Error types for cryptographic operations.
pub mod error;

pub use error::{CryptoError, CryptoResult};
pub use hash::{hash, verify as hash_verify, Hash, HashAlgorithm, Hasher};
pub use keygen::{
    generate_ed25519, generate_key, generate_symmetric, Ed25519KeyPair, KeyType, PublicKey,
    SecretKey,
};
pub use rng::SecureRng;
pub use secure_memory::SecureBuffer;
pub use signing::{
    sign, sign_with_secret_key, verify, verify_with_public_key, Signature, VerificationResult,
};
