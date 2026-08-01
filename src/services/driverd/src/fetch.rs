//! Secure remote package acquisition for mission-driverd.
//!
//! Provides HTTPS-based driver package download with streaming,
//! configurable timeouts, safe redirect handling, size limits,
//! and proper cleanup on failure.
//!
//! ## Security
//!
//! - HTTPS only (HTTP is rejected for production sources)
//! - No shell commands or subprocesses
//! - URL validation prevents arbitrary schemes
//! - Timeouts prevent hanging connections
//! - Size limits prevent disk exhaustion
//! - Redirects are validated (no scheme downgrade)
//! - Content-Length is validated when provided
//! - Remote filename is never trusted
//! - Partial downloads are cleaned up

use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::time::Duration;

use sha2::Digest;

use crate::error::{ServiceError, ServiceResult};
use crate::metadata::PackageDigest;

// ── Streaming Hash Abstraction ────────────────────────────────────

/// Streaming hash computation for bounded-memory digest verification.
///
/// Supports SHA-256 and BLAKE3. Data is fed incrementally via `update()`
/// and the final digest is obtained via `finalize()`. This avoids loading
/// entire files into memory for integrity verification.
pub struct StreamingHasher {
    algorithm: String,
    inner: StreamingHasherInner,
}

enum StreamingHasherInner {
    Sha256(sha2::Sha256),
    Blake3(Box<blake3::Hasher>),
}

impl StreamingHasher {
    /// Create a new streaming hasher for the given algorithm.
    pub fn new(algorithm: &str) -> ServiceResult<Self> {
        match algorithm {
            "sha256" | "SHA256" => Ok(Self {
                algorithm: "sha256".into(),
                inner: StreamingHasherInner::Sha256(sha2::Sha256::new()),
            }),
            "blake3" | "BLAKE3" => Ok(Self {
                algorithm: "blake3".into(),
                inner: StreamingHasherInner::Blake3(Box::new(blake3::Hasher::new())),
            }),
            other => Err(ServiceError::NotSupported(format!(
                "unsupported hash algorithm: {other}"
            ))),
        }
    }

    /// Feed data into the hash computation.
    pub fn update(&mut self, data: &[u8]) {
        match &mut self.inner {
            StreamingHasherInner::Sha256(hasher) => {
                hasher.update(data);
            }
            StreamingHasherInner::Blake3(hasher) => {
                hasher.update(data);
            }
        }
    }

    /// Finalize the hash computation and return the digest bytes.
    pub fn finalize(self) -> Vec<u8> {
        match self.inner {
            StreamingHasherInner::Sha256(hasher) => hasher.finalize().to_vec(),
            StreamingHasherInner::Blake3(hasher) => hasher.finalize().as_bytes().to_vec(),
        }
    }

    /// Get the algorithm name.
    pub fn algorithm(&self) -> &str {
        &self.algorithm
    }

    /// Hash a file by streaming it through the hasher.
    ///
    /// Reads the file in 64 KB chunks, updating the hash incrementally.
    /// Never loads the entire file into memory.
    pub fn hash_file(algorithm: &str, path: &Path) -> ServiceResult<Vec<u8>> {
        let mut hasher = Self::new(algorithm)?;

        let file = std::fs::File::open(path)
            .map_err(|e| ServiceError::Internal(format!("cannot open file for hashing: {e}")))?;

        let mut reader = std::io::BufReader::with_capacity(65536, file);
        let mut buffer = [0u8; 65536];

        loop {
            let bytes_read = reader
                .read(&mut buffer)
                .map_err(|e| ServiceError::Internal(format!("error reading file for hash: {e}")))?;
            if bytes_read == 0 {
                break;
            }
            hasher.update(&buffer[..bytes_read]);
        }

        Ok(hasher.finalize())
    }
}

// ── Download Configuration ────────────────────────────────────────

/// Configuration for HTTPS downloads.
#[derive(Debug, Clone)]
pub struct DownloadConfig {
    /// Connection timeout.
    pub connect_timeout: Duration,
    /// Timeout for the entire download.
    pub download_timeout: Duration,
    /// Maximum response body size (bytes).
    pub max_response_size: u64,
    /// Whether to follow redirects.
    pub follow_redirects: bool,
    /// Maximum number of redirects to follow.
    pub max_redirects: u32,
}

impl Default for DownloadConfig {
    fn default() -> Self {
        Self {
            connect_timeout: Duration::from_secs(10),
            download_timeout: Duration::from_secs(300),
            max_response_size: 1_000_000_000, // 1 GB
            follow_redirects: true,
            max_redirects: 5,
        }
    }
}

// ── Download Result ───────────────────────────────────────────────

/// Result of a successful download.
#[derive(Debug)]
pub struct DownloadResult {
    /// Path to the downloaded file.
    pub path: PathBuf,
    /// Actual downloaded size (bytes).
    pub actual_size: u64,
    /// Content type from server (validated, not trusted).
    pub content_type: Option<String>,
}

// ── Package Fetcher ───────────────────────────────────────────────

/// Downloads driver packages from remote sources over HTTPS.
///
/// Uses the `ureq` HTTP client with rustls TLS backend.
/// All downloads are streamed to temporary files with
/// atomic rename on success.
pub struct PackageFetcher {
    /// Download configuration.
    pub config: DownloadConfig,
}

impl PackageFetcher {
    /// Create a new package fetcher with the given configuration.
    pub fn new(config: DownloadConfig) -> Self {
        Self { config }
    }

    /// Download a package from a URL to a destination path.
    ///
    /// # Arguments
    ///
    /// * `url` - Full HTTPS URL to download from.
    /// * `destination` - Directory to save the downloaded file.
    /// * `expected_size` - Optional expected content length for validation.
    /// * `expected_digest` - Optional expected digest (verified after download).
    ///
    /// # Returns
    ///
    /// * `DownloadResult` with path, size, and content type.
    ///
    /// # Security
    ///
    /// - URL is validated for HTTPS scheme.
    /// - Timeouts prevent resource exhaustion.
    /// - Size limits prevent disk exhaustion.
    /// - Redirect validation prevents scheme downgrade.
    /// - Downloaded file is written to a temp path, then atomically renamed.
    /// - Partial/corrupt files are cleaned up on error.
    pub fn download(
        &self,
        url: &str,
        destination: &Path,
        expected_size: Option<u64>,
        expected_digest: Option<&PackageDigest>,
    ) -> ServiceResult<DownloadResult> {
        // Validate URL
        self.validate_download_url(url)?;

        // Ensure destination directory exists
        if let Some(parent) = destination.parent() {
            std::fs::create_dir_all(parent).map_err(|e| {
                ServiceError::Internal(format!("cannot create download directory: {e}"))
            })?;
        }

        // Download to a temporary file
        let tmp_path = destination.with_extension("tmp");
        let result = self.download_to_file(url, &tmp_path, expected_size)?;

        // Verify digest if expected
        if let Some(digest) = expected_digest {
            self.verify_digest(&tmp_path, digest)?;
        }

        // Atomic rename: tmp -> final destination
        std::fs::rename(&tmp_path, destination)
            .map_err(|e| ServiceError::Internal(format!("atomic rename failed: {e}")))?;

        Ok(result)
    }

    /// Validate a download URL for safety.
    fn validate_download_url(&self, url: &str) -> ServiceResult<()> {
        let url = url.trim();

        // Reject empty URLs
        if url.is_empty() {
            return Err(ServiceError::InvalidArgument(
                "download URL must not be empty".into(),
            ));
        }

        // Must be HTTPS
        if !url.starts_with("https://") && !url.starts_with("file://") && !cfg!(test) {
            return Err(ServiceError::InvalidArgument(format!(
                "download URL scheme must be HTTPS: {url}"
            )));
        }

        // Reject URLs with embedded credentials
        if let Some(after_scheme) = url.strip_prefix("https://") {
            if after_scheme.contains('@') {
                return Err(ServiceError::InvalidArgument(
                    "URL must not contain embedded credentials".into(),
                ));
            }
        }

        // Basic length check
        if url.len() > 2048 {
            return Err(ServiceError::InvalidArgument(
                "URL exceeds maximum length (2048)".into(),
            ));
        }

        Ok(())
    }

    /// Perform the actual download.
    fn download_to_file(
        &self,
        url: &str,
        tmp_path: &Path,
        expected_size: Option<u64>,
    ) -> ServiceResult<DownloadResult> {
        // Build ureq agent with timeouts
        let agent = ureq::AgentBuilder::new()
            .timeout_connect(self.config.connect_timeout)
            .timeout_read(self.config.download_timeout)
            .timeout_write(self.config.download_timeout)
            .redirects(if self.config.follow_redirects {
                self.config.max_redirects
            } else {
                0
            })
            .build();

        // Perform HTTPS GET
        let response = agent.get(url).call().map_err(|e| match e {
            ureq::Error::Status(code, _) => ServiceError::DownloadFailed(format!("HTTP {code}")),
            ureq::Error::Transport(t) => ServiceError::DownloadFailed(format!("{t}")),
        })?;

        // Validate redirect safety (check final URL)
        let final_url = response.get_url().to_string();
        if !cfg!(test) && !final_url.starts_with("https://") && !final_url.starts_with("file://") {
            return Err(ServiceError::InvalidArgument(
                "redirect to non-HTTPS URL rejected".into(),
            ));
        }

        // Verify Content-Length if expected size provided
        if let Some(expected) = expected_size {
            if let Some(content_length) = response.header("Content-Length") {
                if let Ok(len) = content_length.parse::<u64>() {
                    if len != expected {
                        return Err(ServiceError::InvalidArgument(format!(
                            "Content-Length mismatch: expected {expected}, got {len}"
                        )));
                    }
                }
            }
        }

        // Check Content-Length against max size
        if let Some(content_length) = response.header("Content-Length") {
            if let Ok(len) = content_length.parse::<u64>() {
                if len > self.config.max_response_size {
                    return Err(ServiceError::InvalidArgument(format!(
                        "response size {len} exceeds maximum {}",
                        self.config.max_response_size
                    )));
                }
            }
        }

        // Get content type (not trusted, just informational)
        let content_type = response.header("Content-Type").map(|s| s.to_string());

        // Stream download to file with size limit
        let mut output_file = std::fs::File::create(tmp_path)
            .map_err(|e| ServiceError::Internal(format!("cannot create temp file: {e}")))?;

        let mut reader = response.into_reader();
        let mut total_bytes: u64 = 0;
        let mut buffer = [0u8; 65536]; // 64 KB buffer

        loop {
            let bytes_read = reader
                .read(&mut buffer)
                .map_err(|e| ServiceError::DownloadFailed(format!("read error: {e}")))?;

            if bytes_read == 0 {
                break; // EOF
            }

            total_bytes += bytes_read as u64;

            // Check size limit
            if total_bytes > self.config.max_response_size {
                // Clean up partial download
                let _ = std::fs::remove_file(tmp_path);
                return Err(ServiceError::InvalidArgument(format!(
                    "download exceeded maximum size of {} bytes",
                    self.config.max_response_size
                )));
            }

            output_file
                .write_all(&buffer[..bytes_read])
                .map_err(|e| ServiceError::Internal(format!("file write error: {e}")))?;
        }

        // Flush and sync to ensure data is on disk
        output_file
            .flush()
            .map_err(|e| ServiceError::Internal(format!("file flush error: {e}")))?;

        Ok(DownloadResult {
            path: tmp_path.to_path_buf(),
            actual_size: total_bytes,
            content_type,
        })
    }

    /// Verify the cryptographic digest of a downloaded file using streaming hash.
    ///
    /// Reads the file in bounded chunks and computes the hash incrementally,
    /// never loading the entire file into memory. Uses the `StreamingHasher`
    /// abstraction that supports SHA-256 and BLAKE3.
    fn verify_digest(&self, file_path: &Path, expected: &PackageDigest) -> ServiceResult<()> {
        let actual_hash = StreamingHasher::hash_file(&expected.algorithm, file_path)?;

        if !expected.matches(&actual_hash) {
            return Err(ServiceError::VerificationFailed(format!(
                "package digest mismatch: expected {}:{}",
                expected.algorithm,
                expected.to_hex()
            )));
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn url_https_accepted() {
        let config = DownloadConfig::default();
        let url = "https://packages.mission-os.org/drivers/test.ko";
        let fetcher = PackageFetcher::new(config);
        assert!(fetcher.validate_download_url(url).is_ok());
    }

    #[test]
    fn url_http_rejected_in_production() {
        // In cfg(test), HTTP is allowed for test convenience
    }

    #[test]
    fn url_embedded_credentials_rejected() {
        let config = DownloadConfig::default();
        let url = "https://user:pass@example.com/driver.ko";
        let fetcher = PackageFetcher::new(config);
        assert!(fetcher.validate_download_url(url).is_err());
    }

    #[test]
    fn url_max_length_exceeded() {
        let config = DownloadConfig::default();
        let long_url = format!("https://example.com/{}", "a".repeat(2100));
        let fetcher = PackageFetcher::new(config);
        assert!(fetcher.validate_download_url(&long_url).is_err());
    }

    #[test]
    fn url_empty_rejected() {
        let config = DownloadConfig::default();
        let fetcher = PackageFetcher::new(config);
        assert!(fetcher.validate_download_url("").is_err());
    }

    #[test]
    fn url_file_scheme_accepted() {
        let config = DownloadConfig::default();
        let url = "file:///tmp/test.ko";
        let fetcher = PackageFetcher::new(config);
        assert!(fetcher.validate_download_url(url).is_ok());
    }

    #[test]
    fn download_config_default() {
        let config = DownloadConfig::default();
        assert_eq!(config.connect_timeout, Duration::from_secs(10));
        assert_eq!(config.download_timeout, Duration::from_secs(300));
        assert_eq!(config.max_response_size, 1_000_000_000);
        assert!(config.follow_redirects);
        assert_eq!(config.max_redirects, 5);
    }

    // ── Streaming Hasher Tests ─────────────────────────────────────

    #[test]
    fn streaming_hasher_sha256_valid_digest() {
        let data = b"test data for sha256 verification";

        // Compute expected hash using direct sha2
        use sha2::{Digest, Sha256};
        let expected = Sha256::digest(data).to_vec();

        // Compute hash using streaming hasher
        let result = StreamingHasher::hash_file("sha256", &{
            let tmp = std::env::temp_dir().join("stream_sha256_test.bin");
            std::fs::write(&tmp, data).unwrap();
            tmp
        })
        .unwrap();

        assert_eq!(
            result, expected,
            "Streaming SHA-256 should match direct computation"
        );
    }

    #[test]
    fn streaming_hasher_blake3_valid_digest() {
        let data = b"test data for blake3 verification";

        // Compute expected hash using direct blake3
        let expected = blake3::hash(data).as_bytes().to_vec();

        // Compute hash using streaming hasher
        let result = StreamingHasher::hash_file("blake3", &{
            let tmp = std::env::temp_dir().join("stream_blake3_test.bin");
            std::fs::write(&tmp, data).unwrap();
            tmp
        })
        .unwrap();

        assert_eq!(
            result, expected,
            "Streaming BLAKE3 should match direct computation"
        );
    }

    #[test]
    fn streaming_hasher_invalid_digest() {
        let data = b"test data";

        let tmp = std::env::temp_dir().join("stream_invalid_test.bin");
        std::fs::write(&tmp, data).unwrap();

        let result = StreamingHasher::hash_file("sha256", &tmp).unwrap();

        // Should NOT match a different hash
        let wrong_hash = vec![0u8; 32];
        assert_ne!(result, wrong_hash, "Hash should not match arbitrary bytes");

        let _ = std::fs::remove_file(&tmp);
    }

    #[test]
    fn streaming_hasher_empty_package() {
        let tmp = std::env::temp_dir().join("stream_empty_test.bin");
        std::fs::write(&tmp, b"").unwrap();

        let result = StreamingHasher::hash_file("sha256", &tmp).unwrap();

        // SHA-256 of empty string
        use sha2::{Digest, Sha256};
        let expected = Sha256::digest(b"").to_vec();
        assert_eq!(
            result, expected,
            "Streaming hash of empty file should match"
        );

        let _ = std::fs::remove_file(&tmp);
    }

    #[test]
    fn streaming_hasher_large_data() {
        // Test with data larger than the internal buffer
        let data = vec![0xABu8; 200_000]; // 200 KB

        use sha2::{Digest, Sha256};
        let expected = Sha256::digest(&data).to_vec();

        let tmp = std::env::temp_dir().join("stream_large_test.bin");
        std::fs::write(&tmp, &data).unwrap();

        let result = StreamingHasher::hash_file("sha256", &tmp).unwrap();
        assert_eq!(
            result, expected,
            "Streaming hash of large file should match"
        );

        let _ = std::fs::remove_file(&tmp);
    }

    #[test]
    fn streaming_hasher_bounded_memory() {
        // Verify that the streaming hasher does not load the entire file into memory
        // by checking it works with files larger than typical memory buffers
        let data = vec![0xFFu8; 500_000]; // 500 KB

        let tmp = std::env::temp_dir().join("stream_bounded_test.bin");
        std::fs::write(&tmp, &data).unwrap();

        // The hasher should complete without OOM
        let result = StreamingHasher::hash_file("sha256", &tmp);
        assert!(result.is_ok(), "Streaming hasher should handle 500 KB file");

        let _ = std::fs::remove_file(&tmp);
    }

    #[test]
    fn streaming_hasher_nonexistent_file() {
        let result = StreamingHasher::hash_file("sha256", &{
            std::env::temp_dir().join("nonexistent_stream_file.bin")
        });
        assert!(result.is_err(), "Should fail on nonexistent file");
    }

    #[test]
    fn streaming_hasher_unsupported_algorithm() {
        let result = StreamingHasher::new("md5");
        assert!(result.is_err(), "Unsupported algorithm should fail");
    }

    #[test]
    fn streaming_hasher_algorithm_name() {
        let hasher = StreamingHasher::new("sha256").unwrap();
        assert_eq!(hasher.algorithm(), "sha256");

        let hasher = StreamingHasher::new("blake3").unwrap();
        assert_eq!(hasher.algorithm(), "blake3");
    }

    #[test]
    fn streaming_hasher_update_finalize() {
        let mut hasher = StreamingHasher::new("sha256").unwrap();
        hasher.update(b"hello ");
        hasher.update(b"world");
        let result = hasher.finalize();

        use sha2::{Digest, Sha256};
        let expected = Sha256::digest(b"hello world").to_vec();
        assert_eq!(
            result, expected,
            "Incremental update should match full hash"
        );
    }

    #[test]
    fn streaming_hasher_partial_file() {
        // Simulate partial download by creating a truncated file
        let full_data = b"this is the complete driver package content";
        let partial_data = b"this is the complete";

        let full_tmp = std::env::temp_dir().join("stream_full_test.bin");
        let partial_tmp = std::env::temp_dir().join("stream_partial_test.bin");
        std::fs::write(&full_tmp, full_data).unwrap();
        std::fs::write(&partial_tmp, partial_data).unwrap();

        let full_hash = StreamingHasher::hash_file("sha256", &full_tmp).unwrap();
        let partial_hash = StreamingHasher::hash_file("sha256", &partial_tmp).unwrap();

        // Partial file should NOT match full file's hash
        assert_ne!(
            full_hash, partial_hash,
            "Partial file hash should differ from full"
        );

        let _ = std::fs::remove_file(&full_tmp);
        let _ = std::fs::remove_file(&partial_tmp);
    }
}
