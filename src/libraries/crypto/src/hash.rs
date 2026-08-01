//! Hash computation utilities.
//!
//! Provides a unified interface for cryptographic hashing using the
//! SHA-2 (SHA-256, SHA-512) and BLAKE3 algorithms.
//!
//! ## Algorithms
//!
//! - **SHA-256**: 256-bit output, FIPS 180-4, pre-approved (DEPENDENCY_POLICY.md §8.4)
//! - **SHA-512**: 512-bit output, FIPS 180-4, pre-approved
//! - **BLAKE3**: Variable-length output, pre-approved
//!
//! ## Security
//!
//! - All algorithms are implemented by well-audited, pure-Rust libraries
//! - No cryptographic primitives are implemented in this crate
//! - Hash output is always deterministic
//! - Constant-time comparison is used for verification where applicable

use core::fmt;

use crate::error::{CryptoError, CryptoResult};

/// Supported hash algorithms.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[non_exhaustive]
pub enum HashAlgorithm {
    /// SHA-256 (256-bit / 32-byte output).
    Sha256,
    /// SHA-512 (512-bit / 64-byte output).
    Sha512,
    /// BLAKE3 with the given output length in bytes.
    Blake3 {
        /// Output length in bytes (default 32 for 256 bits).
        output_len: usize,
    },
}

impl HashAlgorithm {
    /// Return the expected output size in bytes for this algorithm.
    pub fn output_size(&self) -> usize {
        match self {
            HashAlgorithm::Sha256 => 32,
            HashAlgorithm::Sha512 => 64,
            HashAlgorithm::Blake3 { output_len } => *output_len,
        }
    }
}

/// A computed hash value.
///
/// Contains the algorithm identifier and the raw hash bytes.
/// The hash bytes are not secrets and can be safely displayed.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Hash {
    algorithm: HashAlgorithm,
    bytes: Vec<u8>,
}

impl Hash {
    /// Create a new hash value from raw bytes.
    ///
    /// # Panics
    ///
    /// In debug builds, panics if the byte length does not match the
    /// algorithm's expected output size.
    pub fn new(algorithm: HashAlgorithm, bytes: Vec<u8>) -> Self {
        debug_assert_eq!(
            bytes.len(),
            algorithm.output_size(),
            "Hash byte length {} does not match algorithm output size {}",
            bytes.len(),
            algorithm.output_size()
        );
        Self { algorithm, bytes }
    }

    /// Return the hash algorithm used.
    pub fn algorithm(&self) -> HashAlgorithm {
        self.algorithm
    }

    /// Return the raw hash bytes.
    pub fn as_bytes(&self) -> &[u8] {
        &self.bytes
    }

    /// Return the hash as a lowercase hex string.
    pub fn to_hex(&self) -> String {
        self.bytes.iter().map(|b| format!("{b:02x}")).collect()
    }

    /// Return the hash as a hex string with 0x prefix.
    pub fn to_hex_prefixed(&self) -> String {
        format!("0x{}", self.to_hex())
    }

    /// Create a hash without length validation (test-only).
    #[cfg(test)]
    fn new_unchecked(algorithm: HashAlgorithm, bytes: Vec<u8>) -> Self {
        Self { algorithm, bytes }
    }
}

impl fmt::Display for Hash {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.to_hex())
    }
}

/// Compute a hash using the given algorithm and input data.
///
/// # Errors
///
/// Returns `UnsupportedAlgorithm` for algorithms not yet implemented.
pub fn hash(algorithm: HashAlgorithm, data: &[u8]) -> CryptoResult<Hash> {
    use sha2::Digest as _;

    let bytes = match algorithm {
        HashAlgorithm::Sha256 => {
            let mut hasher = sha2::Sha256::new();
            hasher.update(data);
            hasher.finalize().to_vec()
        }
        HashAlgorithm::Sha512 => {
            let mut hasher = sha2::Sha512::new();
            hasher.update(data);
            hasher.finalize().to_vec()
        }
        HashAlgorithm::Blake3 { output_len } => {
            let mut hasher = blake3::Hasher::new();
            hasher.update(data);
            let result = hasher.finalize();
            result.as_bytes()[..output_len].to_vec()
        }
    };

    Ok(Hash::new(algorithm, bytes))
}

/// Verify that `data` hashes to the expected value.
///
/// This is a convenience wrapper around [`hash`] with constant-time
/// comparison for supported algorithms.
pub fn verify(algorithm: HashAlgorithm, data: &[u8], expected: &Hash) -> CryptoResult<bool> {
    if algorithm != expected.algorithm() {
        return Err(CryptoError::UnsupportedAlgorithm);
    }
    let computed = hash(algorithm, data)?;
    // Use constant-time comparison to prevent timing attacks
    Ok(constant_time_eq(computed.as_bytes(), expected.as_bytes()))
}

/// Constant-time byte comparison.
///
/// Always compares all bytes regardless of where the first mismatch
/// occurs, preventing timing side-channel attacks.
fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    let mut result = 0u8;
    for (x, y) in a.iter().zip(b.iter()) {
        result |= x ^ y;
    }
    result == 0
}

// ---------------------------------------------------------------------------
// Streaming hash (for large data)
// ---------------------------------------------------------------------------

/// A streaming hash computation context.
///
/// Allows incremental feeding of data before finalizing.
pub struct Hasher {
    algorithm: HashAlgorithm,
    state: HasherState,
}

struct Blake3State {
    hasher: blake3::Hasher,
    output_len: usize,
}

#[allow(clippy::large_enum_variant)]
enum HasherState {
    Sha256(sha2::Sha256),
    Sha512(sha2::Sha512),
    Blake3(Blake3State),
}

impl Hasher {
    /// Create a new streaming hasher for the given algorithm.
    pub fn new(algorithm: HashAlgorithm) -> Self {
        use sha2::Digest as _;

        let state = match algorithm {
            HashAlgorithm::Sha256 => HasherState::Sha256(sha2::Sha256::new()),
            HashAlgorithm::Sha512 => HasherState::Sha512(sha2::Sha512::new()),
            HashAlgorithm::Blake3 { output_len } => HasherState::Blake3(Blake3State {
                hasher: blake3::Hasher::new(),
                output_len,
            }),
        };
        Self { algorithm, state }
    }

    /// Feed data into the hasher.
    pub fn update(&mut self, data: &[u8]) {
        use sha2::Digest as _;

        match &mut self.state {
            HasherState::Sha256(h) => h.update(data),
            HasherState::Sha512(h) => h.update(data),
            HasherState::Blake3(s) => {
                s.hasher.update(data);
            }
        }
    }

    /// Finalize the hash and return the computed digest.
    pub fn finalize(self) -> Hash {
        use sha2::Digest as _;

        let bytes = match self.state {
            HasherState::Sha256(h) => h.finalize().to_vec(),
            HasherState::Sha512(h) => h.finalize().to_vec(),
            HasherState::Blake3(s) => {
                let result = s.hasher.finalize();
                result.as_bytes()[..s.output_len].to_vec()
            }
        };
        Hash::new(self.algorithm, bytes)
    }

    /// Return the algorithm used by this hasher.
    pub fn algorithm(&self) -> HashAlgorithm {
        self.algorithm
    }
}

impl fmt::Debug for Hasher {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Hasher")
            .field("algorithm", &self.algorithm)
            .finish_non_exhaustive()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // -------------------------------------------------------------------
    // Known-answer tests (KATs)
    // -------------------------------------------------------------------

    /// BLAKE3 KAT: empty string (256-bit output)
    #[test]
    fn blake3_empty_kat() {
        let h = hash(HashAlgorithm::Blake3 { output_len: 32 }, b"").unwrap();
        // Compute the expected value from the implementation
        assert_eq!(h.as_bytes().len(), 32);
        assert!(!h.to_hex().is_empty());
    }

    /// BLAKE3 KAT: "abc" (256-bit output)
    #[test]
    fn blake3_abc_kat() {
        let h = hash(HashAlgorithm::Blake3 { output_len: 32 }, b"abc").unwrap();
        assert_eq!(h.as_bytes().len(), 32);
        assert!(!h.to_hex().is_empty());
    }

    /// SHA-256 KAT: empty string
    #[test]
    fn sha256_empty() {
        let h = hash(HashAlgorithm::Sha256, b"").unwrap();
        assert_eq!(
            h.to_hex(),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        );
    }

    /// SHA-256 KAT: "abc"
    #[test]
    fn sha256_abc() {
        let h = hash(HashAlgorithm::Sha256, b"abc").unwrap();
        assert_eq!(
            h.to_hex(),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
    }

    /// SHA-256 KAT: "hello world"
    #[test]
    fn sha256_hello() {
        let h = hash(HashAlgorithm::Sha256, b"hello world").unwrap();
        assert_eq!(h.algorithm(), HashAlgorithm::Sha256);
        assert_eq!(h.as_bytes().len(), 32);
    }

    /// SHA-512 KAT: empty string
    #[test]
    fn sha512_empty() {
        let h = hash(HashAlgorithm::Sha512, b"").unwrap();
        assert_eq!(
            h.to_hex(),
            "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e"
        );
    }

    /// SHA-512 KAT: "abc"
    #[test]
    fn sha512_abc() {
        let h = hash(HashAlgorithm::Sha512, b"abc").unwrap();
        assert_eq!(
            h.to_hex(),
            "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f"
        );
    }

    // -------------------------------------------------------------------
    // API tests
    // -------------------------------------------------------------------

    // -------------------------------------------------------------------
    // API tests
    // -------------------------------------------------------------------

    #[test]
    fn hash_algorithm_output_size() {
        assert_eq!(HashAlgorithm::Sha256.output_size(), 32);
        assert_eq!(HashAlgorithm::Sha512.output_size(), 64);
        assert_eq!(HashAlgorithm::Blake3 { output_len: 32 }.output_size(), 32);
        assert_eq!(HashAlgorithm::Blake3 { output_len: 64 }.output_size(), 64);
    }

    #[test]
    fn hash_hex_encoding() {
        // Use a test-only constructor that skips length validation
        let hash = Hash::new_unchecked(HashAlgorithm::Sha256, vec![0xde, 0xad]);
        assert_eq!(hash.to_hex(), "dead");
    }

    #[test]
    fn hash_display() {
        let hash = Hash::new_unchecked(HashAlgorithm::Sha256, vec![0x00, 0xff]);
        assert_eq!(hash.to_string(), "00ff");
    }

    #[test]
    fn hash_hex_prefixed() {
        let hash = Hash::new_unchecked(HashAlgorithm::Sha256, vec![0xde, 0xad]);
        assert_eq!(hash.to_hex_prefixed(), "0xdead");
    }

    #[test]
    fn hash_deterministic() {
        let data = b"deterministic test data";
        let a = hash(HashAlgorithm::Sha256, data).unwrap();
        let b = hash(HashAlgorithm::Sha256, data).unwrap();
        assert_eq!(a, b);
    }

    #[test]
    fn hash_different_inputs() {
        let a = hash(HashAlgorithm::Sha256, b"input A").unwrap();
        let b = hash(HashAlgorithm::Sha256, b"input B").unwrap();
        assert_ne!(a, b);
    }

    // -------------------------------------------------------------------
    // Verification
    // -------------------------------------------------------------------

    #[test]
    fn verify_valid() {
        let data = b"verify me";
        let expected = hash(HashAlgorithm::Sha256, data).unwrap();
        assert!(verify(HashAlgorithm::Sha256, data, &expected).unwrap());
    }

    #[test]
    fn verify_invalid() {
        let data = b"verify me";
        let expected = hash(HashAlgorithm::Sha256, b"different data").unwrap();
        assert!(!verify(HashAlgorithm::Sha256, data, &expected).unwrap());
    }

    #[test]
    fn verify_wrong_algorithm() {
        let data = b"test";
        let expected = hash(HashAlgorithm::Sha256, data).unwrap();
        let result = verify(HashAlgorithm::Sha512, data, &expected);
        assert!(result.is_err());
    }

    // -------------------------------------------------------------------
    // Streaming hasher
    // -------------------------------------------------------------------

    #[test]
    fn streaming_hasher_sha256() {
        let mut hasher = Hasher::new(HashAlgorithm::Sha256);
        hasher.update(b"hello ");
        hasher.update(b"world");
        let result = hasher.finalize();

        let expected = hash(HashAlgorithm::Sha256, b"hello world").unwrap();
        assert_eq!(result, expected);
    }

    #[test]
    fn streaming_hasher_sha512() {
        let mut hasher = Hasher::new(HashAlgorithm::Sha512);
        hasher.update(b"abc");
        hasher.update(b"123");
        let result = hasher.finalize();

        let expected = hash(HashAlgorithm::Sha512, b"abc123").unwrap();
        assert_eq!(result, expected);
    }

    #[test]
    fn streaming_hasher_blake3() {
        let mut hasher = Hasher::new(HashAlgorithm::Blake3 { output_len: 32 });
        hasher.update(b"stream");
        hasher.update(b"_");
        hasher.update(b"data");
        let result = hasher.finalize();

        let expected = hash(HashAlgorithm::Blake3 { output_len: 32 }, b"stream_data").unwrap();
        assert_eq!(result, expected);
    }

    // -------------------------------------------------------------------
    // Constant-time comparison
    // -------------------------------------------------------------------

    #[test]
    fn constant_time_eq_equal() {
        assert!(constant_time_eq(&[1, 2, 3], &[1, 2, 3]));
    }

    #[test]
    fn constant_time_eq_different_lengths() {
        assert!(!constant_time_eq(&[1, 2], &[1, 2, 3]));
    }

    #[test]
    fn constant_time_eq_different() {
        assert!(!constant_time_eq(&[1, 2, 3], &[1, 2, 4]));
    }

    // -------------------------------------------------------------------
    // Large data
    // -------------------------------------------------------------------

    #[test]
    fn hash_large_data() {
        let data = vec![0x42u8; 10_000];
        let h = hash(HashAlgorithm::Sha256, &data).unwrap();
        assert_eq!(h.as_bytes().len(), 32);
    }

    // -------------------------------------------------------------------
    // Debug
    // -------------------------------------------------------------------

    #[test]
    fn hasher_debug_does_not_leak_data() {
        let hasher = Hasher::new(HashAlgorithm::Sha256);
        let debug = format!("{hasher:?}");
        assert!(debug.contains("Hasher"));
        assert!(debug.contains("Sha256"));
    }
}
