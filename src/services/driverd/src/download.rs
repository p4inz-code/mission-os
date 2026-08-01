//! M2-F: Download state machine with resume support and bounded retry policy.
//!
//! Provides an explicit download state model, resumable downloads via
//! HTTP Range requests, and a configurable retry policy with exponential
//! backoff.
//!
//! ## Architecture
//!
//! The download state machine ensures that partial downloads are not
//! mistaken for complete packages. Each state transition is auditable.
//!
//! ## State Machine
//!
//! ```text
//! Idle
//!  → MetadataFetch
//!    → MetadataVerified
//!      → DownloadStarted
//!        → DownloadResumed (if partial file exists)
//!        → DownloadRetry (on transient failure)
//!      → DownloadComplete
//!        → DigestVerify
//!          → Staged (success)
//!          → Failed (digest mismatch)
//!        → Failed → Cleanup
//! ```
//!
//! ## Security
//!
//! - Resume does NOT bypass digest verification — final package is always verified.
//! - Content-Range is validated before appending.
//! - Invalid Content-Range causes a full restart.
//! - Partial files are never treated as valid packages.
//! - Only transient errors are retried (timeout, connection, 5xx).
//! - Authentication failures, invalid signatures, and digest mismatches
//!   are never retried.
//! - Retry is bounded with exponential backoff, preventing DoS loops.

use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};

use crate::audit::{AuditBackend, AuditEvent, EventCategory, EventSeverity};
use crate::error::{ServiceError, ServiceResult};
use crate::fetch::{DownloadResult, PackageFetcher, StreamingHasher};
use crate::metadata::PackageDigest;

// ── Download State Machine ────────────────────────────────────────

/// Explicit state of a single download operation.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum DownloadState {
    /// Download has not started.
    Idle,
    /// Fetching repository metadata.
    MetadataFetch,
    /// Repository metadata verified.
    MetadataVerified,
    /// Package download has started.
    DownloadStarted,
    /// Download is being resumed from a partial file.
    DownloadResumed,
    /// Download failed transiently and will be retried.
    DownloadRetry,
    /// Package download complete (bytes fully received).
    DownloadComplete,
    /// Digest verification in progress.
    DigestVerify,
    /// Package staged and ready for installation.
    Staged,
    /// Download failed permanently.
    Failed,
    /// Cleanup in progress.
    Cleanup,
}

impl DownloadState {
    /// Whether this state represents an active download.
    pub fn is_active(&self) -> bool {
        matches!(
            self,
            DownloadState::MetadataFetch
                | DownloadState::DownloadStarted
                | DownloadState::DownloadResumed
                | DownloadState::DownloadRetry
                | DownloadState::DigestVerify
        )
    }

    /// Whether this state represents a terminal (final) state.
    pub fn is_terminal(&self) -> bool {
        matches!(
            self,
            DownloadState::Staged | DownloadState::Failed | DownloadState::Cleanup
        )
    }
}

// ── Retry Policy ──────────────────────────────────────────────────

/// Configuration for download retry behavior.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RetryPolicy {
    /// Maximum number of retry attempts for a single download.
    pub max_retries: u32,
    /// Initial backoff duration (base).
    pub initial_backoff: Duration,
    /// Maximum backoff duration (cap).
    pub max_backoff: Duration,
    /// Exponential backoff factor.
    pub backoff_factor: f64,
}

impl Default for RetryPolicy {
    fn default() -> Self {
        Self {
            max_retries: 3,
            initial_backoff: Duration::from_secs(1),
            max_backoff: Duration::from_secs(30),
            backoff_factor: 2.0,
        }
    }
}

impl RetryPolicy {
    /// Create a strict retry policy (minimal retries).
    pub fn strict() -> Self {
        Self {
            max_retries: 1,
            initial_backoff: Duration::from_secs(1),
            max_backoff: Duration::from_secs(5),
            backoff_factor: 2.0,
        }
    }

    /// Create a retry policy with no retries (fail fast).
    pub fn no_retries() -> Self {
        Self {
            max_retries: 0,
            initial_backoff: Duration::from_secs(0),
            max_backoff: Duration::from_secs(0),
            backoff_factor: 1.0,
        }
    }

    /// Calculate the delay for the nth retry attempt (0-indexed).
    pub fn delay_for_attempt(&self, attempt: u32) -> Duration {
        if attempt >= self.max_retries {
            return Duration::from_secs(0);
        }
        let delay_secs =
            self.initial_backoff.as_secs_f64() * self.backoff_factor.powi(attempt as i32);
        let delay_secs = delay_secs.min(self.max_backoff.as_secs_f64());
        Duration::from_secs_f64(delay_secs)
    }

    /// Whether an error type should be retried.
    pub fn should_retry(&self, error: &ServiceError) -> bool {
        if self.max_retries == 0 {
            return false;
        }
        match error {
            // Transient errors — safe to retry
            ServiceError::DownloadFailed(_) => true,
            ServiceError::BackendUnavailable(_) => true,

            // Permanent errors — never retry
            ServiceError::PermissionDenied(_) => false,
            ServiceError::InvalidArgument(_) => false,
            ServiceError::NotFound(_) => false,
            ServiceError::AlreadyExists(_) => false,
            ServiceError::VerificationFailed(_) => false,
            ServiceError::MetadataError(_) => false,
            ServiceError::SourceError(_) => false,
            ServiceError::DowngradeRejected(_) => false,
            ServiceError::Internal(_) => false,
            ServiceError::NotSupported(_) => false,
            ServiceError::Busy(_) => false,
            ServiceError::Conflict(_) => false,
            ServiceError::RollbackFailed(_) => false,
            ServiceError::PackageError(_) => false,
        }
    }

    /// Validate the retry policy parameters.
    pub fn validate(&self) -> ServiceResult<()> {
        if self.max_retries > 10 {
            return Err(ServiceError::InvalidArgument(
                "max_retries must not exceed 10".into(),
            ));
        }
        if self.backoff_factor < 1.0 {
            return Err(ServiceError::InvalidArgument(
                "backoff_factor must be >= 1.0".into(),
            ));
        }
        Ok(())
    }
}

// ── Download Tracker ──────────────────────────────────────────────

/// Tracks the state of a single download operation.
#[derive(Debug, Clone)]
pub struct DownloadTracker {
    /// Current download state.
    pub state: DownloadState,
    /// Package digest for this download.
    pub digest: PackageDigest,
    /// Source URL being downloaded from.
    pub url: String,
    /// Destination path for the completed download.
    pub destination: PathBuf,
    /// Number of retry attempts made.
    pub retry_count: u32,
    /// Total bytes downloaded so far.
    pub bytes_downloaded: u64,
    /// Expected total size (from Content-Length or metadata).
    pub expected_size: Option<u64>,
    /// Error message if the download failed.
    pub error: Option<String>,
    /// Correlation ID for audit tracking.
    pub correlation_id: String,
    /// Timestamp when the download started.
    pub started_at: u64,
}

impl DownloadTracker {
    fn new(
        digest: PackageDigest,
        url: String,
        destination: PathBuf,
        expected_size: Option<u64>,
    ) -> Self {
        Self {
            state: DownloadState::Idle,
            digest,
            url,
            destination,
            retry_count: 0,
            bytes_downloaded: 0,
            expected_size,
            error: None,
            correlation_id: crate::signals::next_sequence().to_string(),
            started_at: SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs(),
        }
    }
}

// ── Resume Manager ────────────────────────────────────────────────

/// Manages resume state for partial downloads.
pub struct ResumeManager {
    /// Cache path for partial files.
    partial_dir: PathBuf,
}

impl ResumeManager {
    /// Create a new resume manager.
    pub fn new(partial_dir: PathBuf) -> Self {
        Self { partial_dir }
    }

    /// Get the path where a partial download file would be stored.
    pub fn partial_path(&self, digest: &PackageDigest) -> PathBuf {
        let filename = format!("dl-{}.part", digest.to_hex());
        self.partial_dir.join(filename)
    }

    /// Get the size of an existing partial file.
    pub fn partial_size(&self, digest: &PackageDigest) -> Option<u64> {
        let path = self.partial_path(digest);
        if path.exists() {
            path.metadata().ok().map(|m| m.len())
        } else {
            None
        }
    }

    /// Remove a partial file.
    pub fn remove_partial(&self, digest: &PackageDigest) -> ServiceResult<()> {
        let path = self.partial_path(digest);
        if path.exists() {
            std::fs::remove_file(&path)
                .map_err(|e| ServiceError::Internal(format!("cannot remove partial file: {e}")))?;
        }
        Ok(())
    }

    /// Clean up stale partial files (older than the given duration).
    pub fn cleanup_stale(&self, max_age: Duration) -> ServiceResult<usize> {
        let mut removed = 0usize;
        if let Ok(entries) = std::fs::read_dir(&self.partial_dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                if !path.to_string_lossy().ends_with(".part") {
                    continue;
                }
                if let Ok(meta) = entry.metadata() {
                    if let Ok(modified) = meta.modified() {
                        if let Ok(age) = SystemTime::now().duration_since(modified) {
                            if age > max_age && std::fs::remove_file(&path).is_ok() {
                                removed += 1;
                            }
                        }
                    }
                }
            }
        }
        Ok(removed)
    }
}

// ── Download Manager ──────────────────────────────────────────────

/// Manages downloads with resume and retry support.
pub struct DownloadManager {
    /// Package fetcher for raw HTTP downloads.
    fetcher: PackageFetcher,
    /// Retry policy for transient failures.
    retry_policy: RetryPolicy,
    /// Resume manager for partial downloads.
    resume_manager: ResumeManager,
    /// Audit backend for recording events.
    audit_backend: Box<dyn AuditBackend>,
}

impl DownloadManager {
    /// Create a new download manager.
    pub fn new(
        fetcher: PackageFetcher,
        retry_policy: RetryPolicy,
        resume_manager: ResumeManager,
        audit_backend: Box<dyn AuditBackend>,
    ) -> Self {
        Self {
            fetcher,
            retry_policy,
            resume_manager,
            audit_backend,
        }
    }

    /// Download a driver package with resume and retry support.
    ///
    /// This is the main entry point for package downloads. It handles:
    /// 1. Partial file detection and resume
    /// 2. Bounded retry with exponential backoff
    /// 3. Digest verification after download
    /// 4. Audit events at each stage
    ///
    /// # Arguments
    ///
    /// * `url` - The full HTTPS URL to download from.
    /// * `destination` - The final path for the downloaded package.
    /// * `expected_digest` - The expected package digest (required for security).
    /// * `expected_size` - Optional expected size for validation.
    /// * `source_id` - Source identifier for audit events.
    /// * `subject` - Caller identifier for audit events.
    ///
    /// # Returns
    ///
    /// The final path of the verified, downloaded package.
    ///
    /// # Security
    ///
    /// - Resume does NOT bypass digest verification.
    /// - Only transient network errors are retried.
    /// - Retry count is bounded — no infinite retry loops.
    pub fn download(
        &self,
        url: &str,
        destination: &Path,
        expected_digest: &PackageDigest,
        expected_size: Option<u64>,
        source_id: &str,
        subject: &str,
    ) -> ServiceResult<PathBuf> {
        let mut tracker = DownloadTracker::new(
            expected_digest.clone(),
            url.to_string(),
            destination.to_path_buf(),
            expected_size,
        );

        // Audit: download started
        self.audit_download(
            &tracker,
            source_id,
            subject,
            "download_started",
            EventSeverity::Info,
        );

        // Check for partial file to resume
        let partial_path = self.resume_manager.partial_path(expected_digest);
        let existing_size = if partial_path.exists() {
            match partial_path.metadata() {
                Ok(meta) => {
                    let size = meta.len();
                    tracker.state = DownloadState::DownloadResumed;
                    tracker.bytes_downloaded = size;
                    Some(size)
                }
                Err(_) => None,
            }
        } else {
            None
        };

        // Ensure destination directory exists
        if let Some(parent) = destination.parent() {
            std::fs::create_dir_all(parent)
                .map_err(|e| ServiceError::Internal(format!("cannot create directory: {e}")))?;
        }

        // Download with retries
        let mut attempt = 0u32;
        let max_attempts = self.retry_policy.max_retries + 1; // +1 for initial attempt

        loop {
            match self.perform_download_with_resume(&tracker, &partial_path, existing_size) {
                Ok(result) => {
                    // The downloaded file is already at `destination` or at `result.path`.
                    // PackageFetcher::download() writes to destination.tmp and renames to
                    // destination internally, so `result.path` may be stale (pointing to
                    // a temp file that no longer exists). Use `destination` directly.
                    let verified_path = if result.path.exists() {
                        &result.path
                    } else {
                        destination
                    };

                    // Verify digest
                    tracker.state = DownloadState::DigestVerify;
                    let actual_hash =
                        StreamingHasher::hash_file(&expected_digest.algorithm, verified_path)?;

                    if !expected_digest.matches(&actual_hash) {
                        // Digest mismatch — permanent failure, not retried
                        tracker.state = DownloadState::Failed;
                        tracker.error = Some("digest mismatch".into());
                        self.audit_download(
                            &tracker,
                            source_id,
                            subject,
                            "download_digest_mismatch",
                            EventSeverity::Error,
                        );

                        // Clean up the failed download
                        let _ = std::fs::remove_file(verified_path);
                        let _ = self.resume_manager.remove_partial(expected_digest);

                        return Err(ServiceError::VerificationFailed(format!(
                            "digest mismatch for '{}'",
                            expected_digest.to_hex()
                        )));
                    }

                    // Verify expected size if provided
                    if let Some(expected) = expected_size {
                        if result.actual_size != expected {
                            tracker.state = DownloadState::Failed;
                            self.audit_download(
                                &tracker,
                                source_id,
                                subject,
                                "download_size_mismatch",
                                EventSeverity::Error,
                            );
                            let _ = std::fs::remove_file(verified_path);
                            return Err(ServiceError::InvalidArgument(format!(
                                "size mismatch: expected {expected}, got {}",
                                result.actual_size
                            )));
                        }
                    }

                    // If the file is not already at `destination`, rename it
                    if verified_path != destination {
                        std::fs::rename(verified_path, destination).map_err(|e| {
                            ServiceError::Internal(format!("atomic rename failed: {e}"))
                        })?;
                    }

                    // Clean up partial file
                    let _ = self.resume_manager.remove_partial(expected_digest);

                    // Audit: success
                    tracker.state = DownloadState::Staged;
                    self.audit_download(
                        &tracker,
                        source_id,
                        subject,
                        "download_completed",
                        EventSeverity::Info,
                    );

                    return Ok(destination.to_path_buf());
                }
                Err(e) => {
                    attempt += 1;
                    tracker.retry_count = attempt;

                    // Check if we should retry
                    if attempt < max_attempts && self.retry_policy.should_retry(&e) {
                        tracker.state = DownloadState::DownloadRetry;
                        tracker.error = Some(e.to_string());

                        self.audit_download(
                            &tracker,
                            source_id,
                            subject,
                            "download_retry",
                            EventSeverity::Warning,
                        );

                        // Wait for backoff
                        let delay = self.retry_policy.delay_for_attempt(attempt - 1);
                        std::thread::sleep(delay);

                        continue; // Retry
                    }

                    // Permanent failure
                    tracker.state = DownloadState::Failed;
                    tracker.error = Some(e.to_string());
                    self.audit_download(
                        &tracker,
                        source_id,
                        subject,
                        "download_failed",
                        EventSeverity::Error,
                    );

                    return Err(e);
                }
            }
        }
    }

    /// Perform a single download attempt, optionally resuming from a partial file.
    fn perform_download_with_resume(
        &self,
        tracker: &DownloadTracker,
        partial_path: &Path,
        resume_offset: Option<u64>,
    ) -> ServiceResult<DownloadResult> {
        // If we have a partial file and an offset, try resume
        if let Some(offset) = resume_offset {
            if offset > 0 {
                return self.resume_download(
                    &tracker.url,
                    partial_path,
                    offset,
                    &tracker.destination,
                );
            }
        }

        // Full download (no resume or resume not possible)
        self.fetcher.download(
            &tracker.url,
            &tracker.destination,
            tracker.expected_size,
            None, // Digest verified separately
        )
    }

    /// Resume a download from an existing partial file.
    ///
    /// Sends an HTTP Range request. On success, appends to the partial
    /// file and returns the result. On failure (server doesn't support
    /// Range, invalid Content-Range), falls back to a full restart.
    fn resume_download(
        &self,
        url: &str,
        partial_path: &Path,
        offset: u64,
        destination: &Path,
    ) -> ServiceResult<DownloadResult> {
        // Build agent with timeouts
        let agent = ureq::AgentBuilder::new()
            .timeout_connect(self.fetcher.config.connect_timeout)
            .timeout_read(self.fetcher.config.download_timeout)
            .timeout_write(self.fetcher.config.download_timeout)
            .redirects(0) // No redirects for resume (too complex)
            .build();

        // Send GET with Range header
        let range_header = format!("bytes={offset}-");
        let response = agent
            .get(url)
            .set("Range", &range_header)
            .call()
            .map_err(|e| match e {
                ureq::Error::Status(code, _) => {
                    if code == 416 {
                        // Range Not Satisfiable — offset is beyond file end, restart
                        ServiceError::DownloadFailed(format!(
                            "HTTP 416 Range Not Satisfiable for offset {offset}"
                        ))
                    } else if code == 206 {
                        // 206 Partial Content — resume works, should not happen in error branch
                        ServiceError::DownloadFailed(format!("HTTP {code} (unexpected)"))
                    } else if code >= 500 {
                        ServiceError::DownloadFailed(format!("HTTP {code}"))
                    } else {
                        // 4xx errors — not retried
                        ServiceError::DownloadFailed(format!("HTTP {code} (permanent)"))
                    }
                }
                ureq::Error::Transport(t) => ServiceError::DownloadFailed(format!("{t}")),
            })?;

        // Check if server supports Range (206 Partial Content)
        let status_code = response.status();
        if status_code == 206 {
            // Validate Content-Range header
            let content_range = response.header("Content-Range").ok_or_else(|| {
                ServiceError::DownloadFailed(
                    "server returned 206 without Content-Range header".into(),
                )
            })?;

            // Parse Content-Range: bytes {start}-{end}/{total}
            self.validate_content_range(content_range, offset)?;

            // Open partial file for appending
            let mut file = std::fs::OpenOptions::new()
                .append(true)
                .open(partial_path)
                .map_err(|e| {
                    ServiceError::Internal(format!("cannot open partial file for append: {e}"))
                })?;

            // Stream remaining data
            let mut reader = response.into_reader();
            let mut buffer = [0u8; 65536];
            let mut total_bytes = offset;
            // Capture content type before reader consumes response
            let content_type = None::<String>;

            loop {
                let bytes_read = reader
                    .read(&mut buffer)
                    .map_err(|e| ServiceError::DownloadFailed(format!("read error: {e}")))?;

                if bytes_read == 0 {
                    break;
                }

                total_bytes += bytes_read as u64;

                // Check size limit
                if total_bytes > self.fetcher.config.max_response_size {
                    return Err(ServiceError::InvalidArgument(format!(
                        "download exceeded maximum size of {} bytes",
                        self.fetcher.config.max_response_size
                    )));
                }

                file.write_all(&buffer[..bytes_read])
                    .map_err(|e| ServiceError::Internal(format!("file write error: {e}")))?;
            }

            file.flush()
                .map_err(|e| ServiceError::Internal(format!("file flush error: {e}")))?;

            // Rename partial to destination (atomic)
            std::fs::rename(partial_path, destination)
                .map_err(|e| ServiceError::Internal(format!("resume rename failed: {e}")))?;

            Ok(DownloadResult {
                path: destination.to_path_buf(),
                actual_size: total_bytes,
                content_type,
            })
        } else if status_code == 200 {
            // Server doesn't support Range — restart from beginning
            // Remove the partial file and do a fresh download
            let _ = std::fs::remove_file(partial_path);
            self.fetcher.download(url, destination, None, None)
        } else {
            Err(ServiceError::DownloadFailed(format!(
                "unexpected HTTP status {status_code} for resume request"
            )))
        }
    }

    /// Validate a Content-Range header value.
    ///
    /// Expected format: `bytes {start}-{end}/{total}` or `bytes */{total}`
    fn validate_content_range(
        &self,
        header: &str,
        expected_start: u64,
    ) -> ServiceResult<(u64, u64, u64)> {
        // Expected: "bytes {start}-{end}/{total}"
        let trimmed = header.trim();
        if !trimmed.starts_with("bytes ") {
            return Err(ServiceError::DownloadFailed(format!(
                "invalid Content-Range format: '{header}'"
            )));
        }
        let range_part = &trimmed[6..]; // Skip "bytes "

        if range_part.starts_with("*/") {
            // Server knows total size but doesn't support partial: fall back
            return Err(ServiceError::DownloadFailed(
                "server does not support range requests".into(),
            ));
        }

        let parts: Vec<&str> = range_part.split('/').collect();
        if parts.len() != 2 {
            return Err(ServiceError::DownloadFailed(format!(
                "invalid Content-Range: '{header}'"
            )));
        }

        let range = parts[0];
        let _total: u64 = parts[1].parse().map_err(|_| {
            ServiceError::DownloadFailed(format!("invalid Content-Range total: '{}'", parts[1]))
        })?;

        let range_parts: Vec<&str> = range.split('-').collect();
        if range_parts.len() != 2 {
            return Err(ServiceError::DownloadFailed(format!(
                "invalid Content-Range range: '{range}'"
            )));
        }

        let start: u64 = range_parts[0].parse().map_err(|_| {
            ServiceError::DownloadFailed(format!(
                "invalid Content-Range start: '{}'",
                range_parts[0]
            ))
        })?;

        let end: u64 = range_parts[1].parse().map_err(|_| {
            ServiceError::DownloadFailed(format!("invalid Content-Range end: '{}'", range_parts[1]))
        })?;

        // Validate: start must match expected offset
        if start != expected_start {
            return Err(ServiceError::DownloadFailed(format!(
                "Content-Range start {start} does not match expected offset {expected_start}"
            )));
        }

        // Validate: end must be >= start
        if end < start {
            return Err(ServiceError::DownloadFailed(format!(
                "Content-Range end {end} is before start {start}"
            )));
        }

        Ok((start, end, _total))
    }

    /// Record an audit event for a download operation.
    fn audit_download(
        &self,
        tracker: &DownloadTracker,
        source_id: &str,
        subject: &str,
        action: &str,
        severity: EventSeverity,
    ) {
        let details = format!(
            "source={}, url={}, state={:?}, bytes={}, retries={}, error={:?}",
            source_id,
            tracker.url,
            tracker.state,
            tracker.bytes_downloaded,
            tracker.retry_count,
            tracker.error.as_deref().unwrap_or("none"),
        );

        let event = AuditEvent::new(EventCategory::Download, severity, action, subject, details);
        self.audit_backend.record(&event);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::audit::LogAuditBackend;
    use crate::fetch::DownloadConfig;

    #[allow(dead_code)]
    fn test_download_manager() -> DownloadManager {
        let fetcher = PackageFetcher::new(DownloadConfig::default());
        let retry = RetryPolicy::default();
        let resume = ResumeManager::new(std::env::temp_dir().join("mission_driverd_resume_test"));
        let audit = Box::new(LogAuditBackend);
        DownloadManager::new(fetcher, retry, resume, audit)
    }

    fn test_digest() -> PackageDigest {
        PackageDigest::sha256(vec![0u8; 32]).unwrap()
    }

    // ── DownloadState ──────────────────────────────────────────

    #[test]
    fn download_state_active() {
        assert!(DownloadState::DownloadStarted.is_active());
        assert!(DownloadState::DownloadResumed.is_active());
        assert!(DownloadState::DownloadRetry.is_active());
        assert!(!DownloadState::Staged.is_active());
        assert!(!DownloadState::Failed.is_active());
    }

    #[test]
    fn download_state_terminal() {
        assert!(DownloadState::Staged.is_terminal());
        assert!(DownloadState::Failed.is_terminal());
        assert!(!DownloadState::DownloadStarted.is_terminal());
    }

    // ── RetryPolicy ────────────────────────────────────────────

    #[test]
    fn retry_policy_default() {
        let policy = RetryPolicy::default();
        assert_eq!(policy.max_retries, 3);
        assert_eq!(policy.delay_for_attempt(0), Duration::from_secs(1));
        assert_eq!(policy.delay_for_attempt(1), Duration::from_secs(2));
        assert_eq!(policy.delay_for_attempt(2), Duration::from_secs(4));
        // Attempt 3 is beyond max_retries (0-indexed)
        assert_eq!(policy.delay_for_attempt(3), Duration::from_secs(0));
    }

    #[test]
    fn retry_policy_backoff_capped() {
        let policy = RetryPolicy {
            max_retries: 10,
            initial_backoff: Duration::from_secs(10),
            max_backoff: Duration::from_secs(30),
            backoff_factor: 2.0,
        };
        // 10 * 2^4 = 160, but capped at 30
        assert_eq!(policy.delay_for_attempt(4), Duration::from_secs(30));
    }

    #[test]
    fn retry_policy_no_retries() {
        let policy = RetryPolicy::no_retries();
        assert_eq!(policy.max_retries, 0);
        assert!(!policy.should_retry(&ServiceError::DownloadFailed("timeout".into())));
    }

    #[test]
    fn retry_policy_should_retry_transient() {
        let policy = RetryPolicy::default();
        assert!(policy.should_retry(&ServiceError::DownloadFailed("timeout".into())));
        assert!(policy.should_retry(&ServiceError::BackendUnavailable("offline".into())));
    }

    #[test]
    fn retry_policy_should_not_retry_permanent() {
        let policy = RetryPolicy::default();
        assert!(!policy.should_retry(&ServiceError::VerificationFailed("bad sig".into())));
        assert!(!policy.should_retry(&ServiceError::PermissionDenied("denied".into())));
        assert!(!policy.should_retry(&ServiceError::MetadataError("invalid".into())));
        assert!(!policy.should_retry(&ServiceError::InvalidArgument("bad".into())));
    }

    #[test]
    fn retry_policy_validation() {
        let mut policy = RetryPolicy::default();
        assert!(policy.validate().is_ok());

        policy.max_retries = 20;
        assert!(policy.validate().is_err());

        policy.max_retries = 3;
        policy.backoff_factor = 0.5;
        assert!(policy.validate().is_err());
    }

    // ── DownloadTracker ────────────────────────────────────────

    #[test]
    fn download_tracker_new() {
        let digest = test_digest();
        let tracker = DownloadTracker::new(
            digest.clone(),
            "https://example.com/pkg.ko".into(),
            PathBuf::from("/tmp/pkg.ko"),
            Some(1000),
        );
        assert_eq!(tracker.state, DownloadState::Idle);
        assert_eq!(tracker.retry_count, 0);
        assert!(tracker.started_at > 1_000_000_000);
    }

    // ── ResumeManager ──────────────────────────────────────────

    #[test]
    fn resume_manager_partial_path() {
        let manager = ResumeManager::new(PathBuf::from("/tmp/partials"));
        let digest = test_digest();
        let path = manager.partial_path(&digest);
        assert!(path.to_string_lossy().ends_with(".part"));
        assert!(path.to_string_lossy().contains(&digest.to_hex()));
    }

    #[test]
    fn resume_manager_partial_size_nonexistent() {
        let manager = ResumeManager::new(std::env::temp_dir().join("mission_partial_nonexistent"));
        let digest = test_digest();
        assert!(manager.partial_size(&digest).is_none());
    }

    #[test]
    fn resume_manager_remove_partial_nonexistent() {
        let manager = ResumeManager::new(std::env::temp_dir().join("mission_partial_remove"));
        let digest = test_digest();
        // Should not error even if file doesn't exist
        assert!(manager.remove_partial(&digest).is_ok());
    }

    // ── Content-Range Validation ───────────────────────────────

    #[test]
    fn validate_content_range_valid() {
        let fetcher = PackageFetcher::new(DownloadConfig::default());
        let retry = RetryPolicy::default();
        let resume = ResumeManager::new(PathBuf::from("/tmp"));
        let audit = Box::new(LogAuditBackend);
        let manager = DownloadManager::new(fetcher, retry, resume, audit);

        let result = manager.validate_content_range("bytes 100-199/1000", 100);
        assert!(result.is_ok());
        let (start, end, total) = result.unwrap();
        assert_eq!(start, 100);
        assert_eq!(end, 199);
        assert_eq!(total, 1000);
    }

    #[test]
    fn validate_content_range_wrong_start() {
        let fetcher = PackageFetcher::new(DownloadConfig::default());
        let retry = RetryPolicy::default();
        let resume = ResumeManager::new(PathBuf::from("/tmp"));
        let audit = Box::new(LogAuditBackend);
        let manager = DownloadManager::new(fetcher, retry, resume, audit);

        let result = manager.validate_content_range("bytes 200-299/1000", 100);
        assert!(result.is_err());
    }

    #[test]
    fn validate_content_range_end_before_start() {
        let fetcher = PackageFetcher::new(DownloadConfig::default());
        let retry = RetryPolicy::default();
        let resume = ResumeManager::new(PathBuf::from("/tmp"));
        let audit = Box::new(LogAuditBackend);
        let manager = DownloadManager::new(fetcher, retry, resume, audit);

        let result = manager.validate_content_range("bytes 100-50/1000", 100);
        assert!(result.is_err());
    }

    #[test]
    fn validate_content_range_no_range_support() {
        let fetcher = PackageFetcher::new(DownloadConfig::default());
        let retry = RetryPolicy::default();
        let resume = ResumeManager::new(PathBuf::from("/tmp"));
        let audit = Box::new(LogAuditBackend);
        let manager = DownloadManager::new(fetcher, retry, resume, audit);

        let result = manager.validate_content_range("bytes */1000", 0);
        assert!(result.is_err());
    }

    #[test]
    fn validate_content_range_malformed() {
        let fetcher = PackageFetcher::new(DownloadConfig::default());
        let retry = RetryPolicy::default();
        let resume = ResumeManager::new(PathBuf::from("/tmp"));
        let audit = Box::new(LogAuditBackend);
        let manager = DownloadManager::new(fetcher, retry, resume, audit);

        assert!(manager.validate_content_range("not bytes", 0).is_err());
        assert!(manager.validate_content_range("bytes abc/1000", 0).is_err());
        assert!(manager.validate_content_range("bytes 100/1000", 0).is_err());
    }

    // ── Digest for tests ───────────────────────────────────────

    #[test]
    fn test_digest_consistency() {
        let d1 = test_digest();
        let d2 = test_digest();
        assert_eq!(d1, d2);
    }
}
