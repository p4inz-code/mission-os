//! Cryptographic operation errors.
//!
//! Error types for all cryptographic operations in mission-crypto.
//!
//! ## Security
//!
//! Error messages must never:
//! - Expose secret key material or partial key data
//! - Expose private key bytes
//! - Leak unnecessary filesystem or system details
//! - Collapse meaningful cryptographic failures into ambiguous success

use core::fmt;

/// Cryptographic operation errors.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CryptoError {
    /// An invalid key was provided (wrong length, malformed format).
    InvalidKey,
    /// An invalid signature was provided (wrong length, malformed format).
    InvalidSignature,
    /// The requested algorithm is not supported.
    UnsupportedAlgorithm,
    /// Random number generation failed (OS CSPRNG unavailable).
    RngFailure,
    /// Memory operation failed (mlock, zeroize, allocation).
    MemoryError,
    /// An internal error in the cryptographic library.
    ///
    /// This variant intentionally takes only a generic message string
    /// to avoid leaking internal library details. The message should
    /// not contain secret material.
    Internal(String),
}

impl CryptoError {
    /// Return a human-readable description of the error.
    pub fn description(&self) -> &'static str {
        match self {
            CryptoError::InvalidKey => "invalid key",
            CryptoError::InvalidSignature => "invalid signature",
            CryptoError::UnsupportedAlgorithm => "unsupported algorithm",
            CryptoError::RngFailure => "random number generation failed",
            CryptoError::MemoryError => "memory operation failed",
            CryptoError::Internal(_) => "internal cryptographic error",
        }
    }
}

impl fmt::Display for CryptoError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            CryptoError::Internal(msg) => {
                write!(f, "internal error: {msg}")
            }
            other => write!(f, "{}", other.description()),
        }
    }
}

impl std::error::Error for CryptoError {}

/// Convenience alias for `Result<T, CryptoError>`.
pub type CryptoResult<T> = Result<T, CryptoError>;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn error_display_invalid_key() {
        assert_eq!(CryptoError::InvalidKey.to_string(), "invalid key");
    }

    #[test]
    fn error_display_invalid_signature() {
        assert_eq!(
            CryptoError::InvalidSignature.to_string(),
            "invalid signature"
        );
    }

    #[test]
    fn error_display_unsupported_algorithm() {
        assert_eq!(
            CryptoError::UnsupportedAlgorithm.to_string(),
            "unsupported algorithm"
        );
    }

    #[test]
    fn error_display_rng_failure() {
        assert_eq!(
            CryptoError::RngFailure.to_string(),
            "random number generation failed"
        );
    }

    #[test]
    fn error_display_internal() {
        let err = CryptoError::Internal("buffer overflow".into());
        assert_eq!(err.to_string(), "internal error: buffer overflow");
    }

    #[test]
    fn error_description() {
        assert_eq!(CryptoError::InvalidKey.description(), "invalid key");
        assert_eq!(
            CryptoError::RngFailure.description(),
            "random number generation failed"
        );
    }

    #[test]
    fn error_equality() {
        assert_eq!(CryptoError::InvalidKey, CryptoError::InvalidKey);
        assert_ne!(CryptoError::InvalidKey, CryptoError::InvalidSignature);
    }

    #[test]
    fn error_is_error_trait() {
        use std::error::Error;
        fn assert_error<E: Error>() {}
        assert_error::<CryptoError>();
    }

    #[test]
    fn internal_error_does_not_leak_secrets() {
        let err = CryptoError::Internal("something went wrong".into());
        let msg = err.to_string();
        assert!(!msg.contains("key"));
        assert!(!msg.contains("secret"));
    }
}
