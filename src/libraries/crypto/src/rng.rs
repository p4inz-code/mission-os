//! Secure random number generation.
//!
//! Provides cryptographically secure random bytes sourced from the
//! operating system's CSPRNG via the `getrandom` syscall.
//!
//! ## Design
//!
//! - Uses `getrandom` (libc `getrandom()` / `getentropy()` or `BCryptGenRandom`)
//! - No custom PRNG
//! - No deterministic fallback for security-sensitive randomness
//! - Fails explicitly if secure randomness cannot be obtained
//!
//! ## Security
//!
//! - All randomness is sourced from the OS CSPRNG
//! - On Linux: `getrandom()` syscall (backed by kernel entropy pool)
//! - On Windows: `BCryptGenRandom` (CNG)
//! - On other Unix: `getentropy()` or `/dev/urandom`

use core::fmt;

use crate::error::{CryptoError, CryptoResult};

/// Secure random number generator backed by the operating system's CSPRNG.
///
/// This is a zero-sized type — all state is managed by the kernel.
///
/// # Examples
///
/// ```ignore
/// use mission_crypto::SecureRng;
///
/// let rng = SecureRng::new();
/// let mut buf = [0u8; 32];
/// rng.fill_bytes(&mut buf).expect("OS should provide randomness");
/// ```
#[derive(Clone, Copy)]
pub struct SecureRng;

impl SecureRng {
    /// Create a new secure RNG instance.
    ///
    /// This does not allocate or perform system calls.
    pub const fn new() -> Self {
        Self
    }

    /// Fill a buffer with cryptographically secure random bytes.
    ///
    /// # Errors
    ///
    /// Returns `RngFailure` if the operating system's CSPRNG fails.
    /// This is extremely rare and indicates a serious system issue
    /// (e.g., entropy pool not initialized in early boot).
    pub fn fill_bytes(&self, buf: &mut [u8]) -> CryptoResult<()> {
        getrandom::fill(buf).map_err(|e| CryptoError::Internal(format!("CSPRNG failure: {e}")))
    }

    /// Generate a random 64-bit unsigned integer.
    pub fn next_u64(&self) -> CryptoResult<u64> {
        let mut buf = [0u8; 8];
        self.fill_bytes(&mut buf)?;
        Ok(u64::from_ne_bytes(buf))
    }

    /// Generate a random 32-bit unsigned integer.
    pub fn next_u32(&self) -> CryptoResult<u32> {
        let mut buf = [0u8; 4];
        self.fill_bytes(&mut buf)?;
        Ok(u32::from_ne_bytes(buf))
    }

    /// Generate a random vector of the given length filled with secure bytes.
    pub fn random_vec(&self, len: usize) -> CryptoResult<Vec<u8>> {
        let mut buf = vec![0u8; len];
        self.fill_bytes(&mut buf)?;
        Ok(buf)
    }
}

impl Default for SecureRng {
    fn default() -> Self {
        Self::new()
    }
}

impl fmt::Debug for SecureRng {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("SecureRng").finish_non_exhaustive()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn secure_rng_creation() {
        let rng = SecureRng::new();
        let mut buf = [0u8; 16];
        assert!(rng.fill_bytes(&mut buf).is_ok());
    }

    #[test]
    fn secure_rng_fills_buffer() {
        let rng = SecureRng::new();
        let mut buf = [0u8; 32];
        rng.fill_bytes(&mut buf).unwrap();

        // Very unlikely that all bytes are zero
        assert!(buf.iter().any(|&b| b != 0));
    }

    #[test]
    fn secure_rng_different_outputs() {
        let rng = SecureRng::new();
        let mut buf1 = [0u8; 16];
        let mut buf2 = [0u8; 16];
        rng.fill_bytes(&mut buf1).unwrap();
        rng.fill_bytes(&mut buf2).unwrap();

        // Extremely unlikely to be equal
        assert_ne!(buf1, buf2);
    }

    #[test]
    fn secure_rng_next_u64() {
        let rng = SecureRng::new();
        let val = rng.next_u64().unwrap();
        // Any 64-bit value is valid
        let _ = val;
    }

    #[test]
    fn secure_rng_next_u32() {
        let rng = SecureRng::new();
        let val = rng.next_u32().unwrap();
        let _ = val;
    }

    #[test]
    fn secure_rng_different_u64s() {
        let rng = SecureRng::new();
        let a = rng.next_u64().unwrap();
        let b = rng.next_u64().unwrap();
        // Extremely unlikely to be equal (1/2^64)
        assert_ne!(a, b);
    }

    #[test]
    fn secure_rng_random_vec() {
        let rng = SecureRng::new();
        let vec = rng.random_vec(64).unwrap();
        assert_eq!(vec.len(), 64);
        assert!(vec.iter().any(|&b| b != 0));
    }

    #[test]
    fn secure_rng_construct() {
        let rng = SecureRng;
        let mut buf = [0u8; 8];
        assert!(rng.fill_bytes(&mut buf).is_ok());
    }

    #[test]
    fn secure_rng_large_buffer() {
        let rng = SecureRng::new();
        let mut buf = vec![0u8; 1_000_000];
        rng.fill_bytes(&mut buf).unwrap();
        assert!(buf.iter().any(|&b| b != 0));
    }

    #[test]
    fn secure_rng_zero_length() {
        let rng = SecureRng::new();
        let mut buf = [];
        assert!(rng.fill_bytes(&mut buf).is_ok());
    }

    #[test]
    fn debug_does_not_leak_state() {
        let rng = SecureRng::new();
        let debug = format!("{rng:?}");
        assert!(debug.contains("SecureRng"));
    }
}
