//! M2-F: Driver package cache management.
//!
//! Provides a safe, bounded driver package cache with atomic writes,
//! digest-verified cache hits, and safe cleanup.
//!
//! ## Architecture
//!
//! Cache files are stored in deterministic paths based on the package
//! digest (not the untrusted filename). Cache entries are never trusted
//! without digest verification — a cache hit still requires verifying
//! the package digest against trusted metadata.
//!
//! ## Security
//!
//! - Cache path is based on digest, preventing filename-based attacks.
//! - Cache is NEVER a trust bypass — every cache hit is verified.
//! - Partial/temp files use `.part` extension and are never treated as valid.
//! - Atomic writes prevent partial-file corruptions.
//! - Path traversal is prevented via digest-based naming.
//! - Cache cleanup does not delete files outside the cache directory.

use std::path::PathBuf;

use serde::{Deserialize, Serialize};

use crate::error::{ServiceError, ServiceResult};
use crate::fetch::StreamingHasher;
use crate::metadata::PackageDigest;

// ── Constants ─────────────────────────────────────────────────────

/// Default maximum cache size (5 GB).
pub const DEFAULT_MAX_CACHE_SIZE: u64 = 5_000_000_000;

/// Default maximum number of cache entries.
pub const DEFAULT_MAX_CACHE_ENTRIES: usize = 50;

/// Extension for partial/temporary download files.
pub const PARTIAL_EXTENSION: &str = "part";

/// Extension for cache metadata files.
pub const META_EXTENSION: &str = "meta";

// ── Cache Configuration ───────────────────────────────────────────

/// Configuration for the driver package cache.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CacheConfig {
    /// Path to the cache directory.
    pub cache_path: PathBuf,
    /// Maximum cache size in bytes.
    pub max_size_bytes: u64,
    /// Maximum number of cache entries.
    pub max_entries: usize,
}

impl CacheConfig {
    /// Create a new cache configuration with defaults.
    pub fn new(cache_path: PathBuf) -> Self {
        Self {
            cache_path,
            max_size_bytes: DEFAULT_MAX_CACHE_SIZE,
            max_entries: DEFAULT_MAX_CACHE_ENTRIES,
        }
    }

    /// Create a test cache configuration with a unique temp directory.
    /// Uses the test function name (via a counter) to avoid parallel test conflicts.
    #[cfg(test)]
    fn test_config() -> Self {
        use std::sync::atomic::{AtomicU64, Ordering};
        static TEST_COUNTER: AtomicU64 = AtomicU64::new(0);
        let counter = TEST_COUNTER.fetch_add(1, Ordering::SeqCst);
        let tmp = std::env::temp_dir()
            .join("mission_driverd_cache_test")
            .join(format!("test_{counter}"));
        let _ = std::fs::create_dir_all(&tmp);
        Self {
            cache_path: tmp,
            max_size_bytes: 1_000_000_000,
            max_entries: 20,
        }
    }

    /// Validate the cache configuration.
    pub fn validate(&self) -> ServiceResult<()> {
        if self.cache_path.as_os_str().is_empty() {
            return Err(ServiceError::InvalidArgument(
                "cache path must not be empty".into(),
            ));
        }
        if self.max_size_bytes == 0 {
            return Err(ServiceError::InvalidArgument(
                "max cache size must be positive".into(),
            ));
        }
        if self.max_entries == 0 {
            return Err(ServiceError::InvalidArgument(
                "max cache entries must be positive".into(),
            ));
        }
        Ok(())
    }
}

// ── Cache Entry Metadata ──────────────────────────────────────────

/// Metadata for a cached driver package.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CacheEntryMeta {
    /// Package name.
    pub package_name: String,
    /// Package version string.
    pub package_version: String,
    /// Source/Repository ID this package was fetched from.
    pub source_id: String,
    /// Digest algorithm used for verification.
    pub digest_algorithm: String,
    /// Hex-encoded digest value.
    pub digest_value: String,
    /// Package size in bytes.
    pub size_bytes: u64,
    /// Unix timestamp when this entry was cached.
    pub cached_at: u64,
    /// Whether the digest has been verified since caching.
    pub digest_verified: bool,
}

// ── Cache Manager ─────────────────────────────────────────────────

/// Manages the driver package cache with bounded size and atomic writes.
pub struct CacheManager {
    /// Cache configuration.
    config: CacheConfig,
}

impl CacheManager {
    /// Create a new cache manager.
    pub fn new(config: CacheConfig) -> Self {
        let _ = std::fs::create_dir_all(&config.cache_path);
        Self { config }
    }

    /// Compute the deterministic cache path for a package based on its digest.
    ///
    /// The filename is derived from the digest to prevent path traversal
    /// and ensure deterministic lookup.
    pub fn cache_path_for(&self, digest: &PackageDigest) -> PathBuf {
        let filename = format!("pkg-{}", digest.to_hex());
        self.config.cache_path.join(filename)
    }

    /// Compute the partial download path for a package.
    pub fn partial_path_for(&self, digest: &PackageDigest) -> PathBuf {
        let filename = format!("pkg-{}.{}", digest.to_hex(), PARTIAL_EXTENSION);
        self.config.cache_path.join(filename)
    }

    /// Compute the metadata path for a cache entry.
    pub fn meta_path_for(&self, digest: &PackageDigest) -> PathBuf {
        let filename = format!("pkg-{}.{}", digest.to_hex(), META_EXTENSION);
        self.config.cache_path.join(filename)
    }

    /// Check if a package is in the cache.
    pub fn contains(&self, digest: &PackageDigest) -> bool {
        self.cache_path_for(digest).exists()
    }

    /// Get the cache path for a verified package (returns None if not cached).
    pub fn get_cached_path(&self, digest: &PackageDigest) -> Option<PathBuf> {
        let path = self.cache_path_for(digest);
        if path.exists() {
            Some(path)
        } else {
            None
        }
    }

    /// Get cache entry metadata.
    pub fn get_metadata(&self, digest: &PackageDigest) -> ServiceResult<CacheEntryMeta> {
        let meta_path = self.meta_path_for(digest);
        let content = std::fs::read_to_string(&meta_path)
            .map_err(|e| ServiceError::NotFound(format!("cache metadata not found: {e}")))?;
        serde_json::from_str(&content)
            .map_err(|e| ServiceError::Internal(format!("invalid cache metadata: {e}")))
    }

    /// Stage a partial download file in the cache directory.
    ///
    /// Returns the path to write to. The caller should write the file,
    /// then call `finalize()` to atomically move it to the final location.
    pub fn stage_partial(&self, digest: &PackageDigest) -> ServiceResult<PathBuf> {
        let part_path = self.partial_path_for(digest);
        if let Some(parent) = part_path.parent() {
            std::fs::create_dir_all(parent).map_err(|e| {
                ServiceError::Internal(format!("cannot create cache directory: {e}"))
            })?;
        }
        Ok(part_path)
    }

    /// Atomically finalize a cached package from partial to final location.
    ///
    /// # Arguments
    ///
    /// * `digest` - The package digest.
    /// * `source_id` - The source/repository ID.
    /// * `package_name` - The package name.
    /// * `package_version` - The package version.
    /// * `size_bytes` - The final package size.
    /// * `digest_verified` - Whether the digest was verified during download.
    ///
    /// # Security
    ///
    /// The rename is atomic on the same filesystem. After this call,
    /// the `.part` extension is removed, making the file a valid
    /// cache entry. However, cache entries are still verified before
    /// reuse — see `verify_cache_entry()`.
    pub fn finalize(
        &self,
        digest: &PackageDigest,
        source_id: &str,
        package_name: &str,
        package_version: &str,
        size_bytes: u64,
        digest_verified: bool,
    ) -> ServiceResult<PathBuf> {
        let part_path = self.partial_path_for(digest);
        let final_path = self.cache_path_for(digest);

        // Ensure partial file exists
        if !part_path.exists() {
            return Err(ServiceError::NotFound(
                "partial file not found for finalization".into(),
            ));
        }

        // Atomic rename
        std::fs::rename(&part_path, &final_path)
            .map_err(|e| ServiceError::Internal(format!("cache finalization failed: {e}")))?;

        // Write metadata
        let meta = CacheEntryMeta {
            package_name: package_name.to_string(),
            package_version: package_version.to_string(),
            source_id: source_id.to_string(),
            digest_algorithm: digest.algorithm.clone(),
            digest_value: digest.to_hex(),
            size_bytes,
            cached_at: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs(),
            digest_verified,
        };

        let meta_path = self.meta_path_for(digest);
        let meta_json = serde_json::to_string(&meta).map_err(|e| {
            ServiceError::Internal(format!("cache metadata serialization failed: {e}"))
        })?;
        std::fs::write(&meta_path, meta_json)
            .map_err(|e| ServiceError::Internal(format!("cache metadata write failed: {e}")))?;

        Ok(final_path)
    }

    /// Verify a cache entry's integrity by recomputing the digest.
    ///
    /// Returns `Ok(true)` if the digest matches, `Ok(false)` if corrupt,
    /// or an error if the file cannot be read.
    ///
    /// # Security
    ///
    /// Cache entries are NEVER trusted without verification. This method
    /// recomputes the full file digest and compares against the expected
    /// value. Corrupted cache entries are automatically removed.
    pub fn verify_cache_entry(&self, digest: &PackageDigest) -> ServiceResult<bool> {
        let path = self.cache_path_for(digest);
        if !path.exists() {
            return Ok(false);
        }

        let actual_hash = StreamingHasher::hash_file(&digest.algorithm, &path)
            .map_err(|e| ServiceError::Internal(format!("cache verification failed: {e}")))?;

        if digest.matches(&actual_hash) {
            Ok(true)
        } else {
            // Corrupted — remove the entry
            let _ = std::fs::remove_file(&path);
            let _ = std::fs::remove_file(self.meta_path_for(digest));
            Ok(false)
        }
    }

    /// Remove a specific cache entry.
    pub fn remove_entry(&self, digest: &PackageDigest) -> ServiceResult<()> {
        let path = self.cache_path_for(digest);
        if path.exists() {
            std::fs::remove_file(&path)
                .map_err(|e| ServiceError::Internal(format!("cache entry removal failed: {e}")))?;
        }
        let meta_path = self.meta_path_for(digest);
        if meta_path.exists() {
            let _ = std::fs::remove_file(&meta_path);
        }
        Ok(())
    }

    /// Remove all partial download files (stale cleanup).
    pub fn cleanup_partials(&self) -> ServiceResult<usize> {
        let mut removed = 0usize;
        if let Ok(entries) = std::fs::read_dir(&self.config.cache_path) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.extension().is_some_and(|ext| ext == PARTIAL_EXTENSION)
                    && std::fs::remove_file(&path).is_ok()
                {
                    removed += 1;
                }
            }
        }
        Ok(removed)
    }

    /// Get the current cache size in bytes.
    pub fn current_cache_size(&self) -> u64 {
        let mut total = 0u64;
        if let Ok(entries) = std::fs::read_dir(&self.config.cache_path) {
            for entry in entries.flatten() {
                let path = entry.path();
                // Only count non-partial, non-meta files
                if path
                    .extension()
                    .is_some_and(|ext| ext == PARTIAL_EXTENSION || ext == META_EXTENSION)
                {
                    continue;
                }
                if let Ok(meta) = entry.metadata() {
                    total += meta.len();
                }
            }
        }
        total
    }

    /// Get the number of valid cache entries.
    pub fn cache_entry_count(&self) -> usize {
        let mut count = 0usize;
        if let Ok(entries) = std::fs::read_dir(&self.config.cache_path) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path
                    .extension()
                    .is_some_and(|ext| ext == PARTIAL_EXTENSION || ext == META_EXTENSION)
                {
                    continue;
                }
                if path
                    .file_name()
                    .is_some_and(|n| n.to_string_lossy().starts_with("pkg-"))
                {
                    count += 1;
                }
            }
        }
        count
    }

    /// Enforce cache size limits by removing least-recently-used entries.
    ///
    /// Uses file modification time as a proxy for last access.
    pub fn enforce_limits(&self) -> ServiceResult<()> {
        let current_size = self.current_cache_size();
        if current_size <= self.config.max_size_bytes
            && self.cache_entry_count() <= self.config.max_entries
        {
            return Ok(()); // No action needed
        }

        // Collect all cache entries with their modification times
        let mut entries: Vec<(PathBuf, std::time::SystemTime)> = Vec::new();
        if let Ok(read_dir) = std::fs::read_dir(&self.config.cache_path) {
            for entry in read_dir.flatten() {
                let path = entry.path();
                if path
                    .extension()
                    .is_some_and(|ext| ext == PARTIAL_EXTENSION || ext == META_EXTENSION)
                {
                    continue;
                }
                if let Ok(meta) = entry.metadata() {
                    if let Ok(modified) = meta.modified() {
                        entries.push((path, modified));
                    }
                }
            }
        }

        // Sort by modification time (oldest first)
        entries.sort_by_key(|a| a.1);

        // Remove oldest entries until within limits
        let mut size = current_size;
        let mut count = entries.len();
        for (path, _) in &entries {
            if size <= self.config.max_size_bytes && count <= self.config.max_entries {
                break;
            }
            if let Ok(meta) = path.metadata() {
                size = size.saturating_sub(meta.len());
            }
            let _ = std::fs::remove_file(path);
            // Also remove metadata file
            let meta_path = path.with_extension(META_EXTENSION);
            let _ = std::fs::remove_file(meta_path);
            count = count.saturating_sub(1);
        }

        Ok(())
    }

    /// Clear the entire cache.
    pub fn clear(&self) -> ServiceResult<usize> {
        let mut removed = 0usize;
        if let Ok(entries) = std::fs::read_dir(&self.config.cache_path) {
            for entry in entries.flatten() {
                let path = entry.path();
                let filename = path.file_name().map(|n| n.to_string_lossy().to_string());
                if let Some(ref name) = filename {
                    if (name.starts_with("pkg-")
                        || name.ends_with(".part")
                        || name.ends_with(".meta"))
                        && std::fs::remove_file(&path).is_ok()
                    {
                        removed += 1;
                    }
                }
            }
        }
        Ok(removed)
    }

    /// Get a reference to the cache configuration.
    pub fn config(&self) -> &CacheConfig {
        &self.config
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_manager() -> CacheManager {
        let config = CacheConfig::test_config();
        CacheManager::new(config)
    }

    fn test_digest() -> PackageDigest {
        PackageDigest::sha256(vec![0u8; 32]).unwrap()
    }

    // ── Cache Paths ────────────────────────────────────────────

    #[test]
    fn cache_path_deterministic() {
        let manager = test_manager();
        let digest = test_digest();
        let path1 = manager.cache_path_for(&digest);
        let path2 = manager.cache_path_for(&digest);
        assert_eq!(path1, path2, "Cache path must be deterministic");
    }

    #[test]
    fn partial_path_differs_from_final() {
        let manager = test_manager();
        let digest = test_digest();
        let final_path = manager.cache_path_for(&digest);
        let partial_path = manager.partial_path_for(&digest);
        assert_ne!(
            final_path, partial_path,
            "Partial path must differ from final"
        );
        assert!(
            partial_path.to_string_lossy().ends_with(".part"),
            "Partial path must end with .part"
        );
    }

    // ── Cache Operations ───────────────────────────────────────

    #[test]
    fn cache_contains_after_finalize() {
        let manager = test_manager();
        let digest = test_digest();

        // Stage partial
        let part_path = manager.stage_partial(&digest).unwrap();
        std::fs::write(&part_path, b"test package data").unwrap();

        // Finalize
        manager
            .finalize(&digest, "test-source", "test-pkg", "1.0.0", 17, true)
            .unwrap();

        assert!(manager.contains(&digest));
        assert!(manager.get_cached_path(&digest).is_some());

        // Cleanup
        let _ = manager.remove_entry(&digest);
    }

    #[test]
    fn cache_not_contains_before_finalize() {
        let manager = test_manager();
        let digest = test_digest();
        assert!(!manager.contains(&digest));
    }

    #[test]
    fn cache_verify_valid_entry() {
        let manager = test_manager();
        let data = b"verify me";
        use sha2::{Digest, Sha256};
        let hash = Sha256::digest(data);
        let digest = PackageDigest::sha256(hash.to_vec()).unwrap();

        let part_path = manager.stage_partial(&digest).unwrap();
        std::fs::write(&part_path, data).unwrap();
        manager
            .finalize(
                &digest,
                "test",
                "verify-pkg",
                "1.0.0",
                data.len() as u64,
                true,
            )
            .unwrap();

        let result = manager.verify_cache_entry(&digest).unwrap();
        assert!(result, "Cache entry should verify successfully");

        let _ = manager.remove_entry(&digest);
    }

    #[test]
    fn cache_verify_corrupted_entry() {
        let manager = test_manager();
        let digest = test_digest();

        // Write corrupted data (doesn't match the expected digest)
        let part_path = manager.stage_partial(&digest).unwrap();
        std::fs::write(&part_path, b"corrupted data").unwrap();
        manager
            .finalize(&digest, "test", "corrupt-pkg", "1.0.0", 14, true)
            .unwrap();

        let result = manager.verify_cache_entry(&digest).unwrap();
        assert!(!result, "Corrupted entry should fail verification");

        // Entry should be removed
        assert!(!manager.contains(&digest));
    }

    // ── Partial Cleanup ────────────────────────────────────────

    #[test]
    fn cleanup_partials_removes_stale() {
        let manager = test_manager();

        // Create a partial file
        let digest = test_digest();
        let part_path = manager.stage_partial(&digest).unwrap();
        std::fs::write(&part_path, b"partial data").unwrap();

        let removed = manager.cleanup_partials().unwrap();
        assert!(removed >= 1, "Should remove at least one partial file");
        assert!(!part_path.exists(), "Partial file should be removed");
    }

    // ── Cache Limits ───────────────────────────────────────────

    #[test]
    fn cache_size_tracking() {
        let manager = test_manager();
        let initial_size = manager.current_cache_size();
        assert_eq!(initial_size, 0, "Cache should start empty");

        let digest = test_digest();
        let data = b"data for size tracking";
        let data_len = data.len() as u64;
        let part_path = manager.stage_partial(&digest).unwrap();
        std::fs::write(&part_path, data).unwrap();
        manager
            .finalize(&digest, "test", "size-pkg", "1.0.0", data_len, true)
            .unwrap();

        let size = manager.current_cache_size();
        assert!(
            size >= data_len,
            "Cache size {} should include the new entry ({} bytes)",
            size,
            data_len
        );

        let _ = manager.remove_entry(&digest);
    }

    #[test]
    fn cache_entry_count() {
        let manager = test_manager();
        assert_eq!(manager.cache_entry_count(), 0);

        let digest = test_digest();
        let part_path = manager.stage_partial(&digest).unwrap();
        std::fs::write(&part_path, b"entry count test").unwrap();
        manager
            .finalize(&digest, "test", "count-pkg", "1.0.0", 16, true)
            .unwrap();

        assert_eq!(manager.cache_entry_count(), 1);

        let _ = manager.remove_entry(&digest);
    }

    #[test]
    fn clear_cache() {
        let manager = test_manager();

        let digest = test_digest();
        let part_path = manager.stage_partial(&digest).unwrap();
        std::fs::write(&part_path, b"clear test").unwrap();
        manager
            .finalize(&digest, "test", "clear-pkg", "1.0.0", 10, true)
            .unwrap();

        let removed = manager.clear().unwrap();
        assert!(removed >= 1, "Clear should remove entries");
        assert_eq!(manager.cache_entry_count(), 0);
    }

    // ── Configuration ──────────────────────────────────────────

    #[test]
    fn cache_config_validation() {
        let mut config = CacheConfig::test_config();
        assert!(config.validate().is_ok());

        config.max_size_bytes = 0;
        assert!(config.validate().is_err());

        config.max_size_bytes = 1000;
        config.max_entries = 0;
        assert!(config.validate().is_err());
    }

    #[test]
    fn cache_config_new() {
        let config = CacheConfig::new(PathBuf::from("/var/cache/mission/drivers"));
        assert_eq!(config.max_size_bytes, DEFAULT_MAX_CACHE_SIZE);
        assert_eq!(config.max_entries, DEFAULT_MAX_CACHE_ENTRIES);
    }

    // ── Cache Entry Metadata ───────────────────────────────────

    #[test]
    fn cache_metadata_roundtrip() {
        let manager = test_manager();
        let digest = test_digest();

        let part_path = manager.stage_partial(&digest).unwrap();
        std::fs::write(&part_path, b"meta test").unwrap();
        manager
            .finalize(&digest, "meta-source", "meta-pkg", "2.0.0", 9, true)
            .unwrap();

        let meta = manager.get_metadata(&digest).unwrap();
        assert_eq!(meta.package_name, "meta-pkg");
        assert_eq!(meta.package_version, "2.0.0");
        assert_eq!(meta.source_id, "meta-source");
        assert!(meta.digest_verified);

        let _ = manager.remove_entry(&digest);
    }

    #[test]
    fn cache_metadata_not_found() {
        let manager = test_manager();
        let digest = test_digest();
        let result = manager.get_metadata(&digest);
        assert!(
            result.is_err(),
            "expected Err for non-existent metadata; meta_path: {:?}",
            manager.meta_path_for(&digest),
        );
    }
}
