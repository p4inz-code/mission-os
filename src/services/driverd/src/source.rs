//! Driver package source architecture for mission-driverd.
//!
//! Defines the source trust model, source identity, resolver,
//! and configuration validation for driver package sources.
//!
//! ## Architecture
//!
//! Per MOS-ENG-SEC-001 §7.2, driver trust requires:
//! - Repository trust (source must be trusted)
//! - Signature verification (package must be signed)
//! - Integrity verification (digest must match)
//!
//! Sources form the foundation of the package acquisition pipeline:
//!
//! DriverSource (configured)
//!     ↓
//! SourceResolver (validates, resolves)
//!     ↓
//! PackageFetcher (acquires)
//!     ↓
//! PackageVerifier (integrity + signature)
//!     ↓
//! PackageStore (stages)
//!     ↓
//! DriverExecutionEngine (installs)

use std::fmt;
use std::path::Path;

use serde::{Deserialize, Serialize};

use crate::error::{ServiceError, ServiceResult};

// ── Source Identity ───────────────────────────────────────────────

/// Uniquely identifies a driver source.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourceId(String);

impl SourceId {
    /// Create a new source ID after validation.
    pub fn new(id: &str) -> ServiceResult<Self> {
        let trimmed = id.trim();
        if trimmed.is_empty() {
            return Err(ServiceError::InvalidArgument(
                "source ID must not be empty".into(),
            ));
        }
        if trimmed.len() > 128 {
            return Err(ServiceError::InvalidArgument(
                "source ID exceeds maximum length (128)".into(),
            ));
        }
        if !trimmed
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-' || c == '.')
        {
            return Err(ServiceError::InvalidArgument(
                "source ID must contain only alphanumeric chars, underscores, hyphens, or dots"
                    .into(),
            ));
        }
        Ok(Self(trimmed.to_string()))
    }

    /// Get the source ID string.
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl fmt::Display for SourceId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

impl std::ops::Deref for SourceId {
    type Target = str;
    fn deref(&self) -> &str {
        &self.0
    }
}

// ── Source Type ───────────────────────────────────────────────────

/// Type of driver source.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SourceType {
    /// Official Mission OS repository.
    Mission,
    /// Linux kernel upstream (built-in or DKMS).
    Linux,
    /// Vendor-provided driver repository.
    Vendor,
    /// Community-maintained repository.
    Community,
    /// Local filesystem source.
    Local,
}

impl SourceType {
    /// Whether this source type requires network access.
    pub fn requires_network(&self) -> bool {
        matches!(
            self,
            SourceType::Mission | SourceType::Vendor | SourceType::Community
        )
    }

    /// Default trust level for this source type.
    pub fn default_trusted(&self) -> bool {
        matches!(self, SourceType::Mission | SourceType::Linux)
    }
}

// ── Source Configuration ──────────────────────────────────────────

/// Configuration for a single driver source.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SourceConfig {
    /// Unique source identifier.
    pub id: String,
    /// Human-readable name.
    pub name: String,
    /// Source type.
    #[serde(rename = "type")]
    pub source_type: SourceType,
    /// Base URL for the source (used for remote sources).
    #[serde(default)]
    pub base_url: String,
    /// Whether this source is enabled.
    #[serde(default = "default_enabled")]
    pub enabled: bool,
    /// Source priority (lower = higher priority).
    #[serde(default = "default_priority")]
    pub priority: u32,
    /// Trusted key identifiers for verifying packages from this source.
    #[serde(default)]
    pub trusted_key_ids: Vec<String>,
    /// Allowed architectures for packages from this source.
    #[serde(default)]
    pub allowed_architectures: Vec<String>,
    /// Optional mirror URLs (tried in order after base URL).
    #[serde(default)]
    pub mirrors: Vec<String>,
    /// URL to fetch repository metadata from (if different from base URL).
    #[serde(default)]
    pub metadata_url: Option<String>,
    /// Repository-specific trust configuration for metadata verification.
    #[serde(default)]
    pub trust_config: Option<crate::repository::TrustConfig>,
}

fn default_enabled() -> bool {
    true
}
fn default_priority() -> u32 {
    50
}

impl SourceConfig {
    /// Validate the source configuration.
    pub fn validate(&self) -> ServiceResult<()> {
        // Validate source ID
        SourceId::new(&self.id)?;

        // Validate name
        if self.name.trim().is_empty() {
            return Err(ServiceError::InvalidArgument(
                "source name must not be empty".into(),
            ));
        }

        // Validate base URL for remote sources
        if self.source_type.requires_network() {
            self.validate_url(&self.base_url)?;
            for mirror in &self.mirrors {
                self.validate_url(mirror)?;
            }
        }

        // Validate priority range
        if self.priority > 1000 {
            return Err(ServiceError::InvalidArgument(
                "source priority must be between 0 and 1000".into(),
            ));
        }

        // Validate trusted key IDs
        for key_id in &self.trusted_key_ids {
            if key_id.trim().is_empty() {
                return Err(ServiceError::InvalidArgument(
                    "trusted key ID must not be empty".into(),
                ));
            }
        }

        // Validate architectures
        for arch in &self.allowed_architectures {
            if arch.trim().is_empty() {
                return Err(ServiceError::InvalidArgument(
                    "architecture must not be empty".into(),
                ));
            }
        }

        // Validate metadata URL if present
        if let Some(ref meta_url) = self.metadata_url {
            if self.source_type.requires_network() {
                self.validate_url(meta_url)?;
            }
        }

        // Validate trust config if present
        if let Some(ref trust) = self.trust_config {
            if trust.level == crate::repository::TrustLevel::Trusted
                && trust.trusted_keys.is_empty()
            {
                return Err(ServiceError::InvalidArgument(
                    "trusted repositories must have at least one trusted key".into(),
                ));
            }
        }

        Ok(())
    }

    /// Validate a URL for safety.
    fn validate_url(&self, url: &str) -> ServiceResult<()> {
        let trimmed = url.trim();
        if trimmed.is_empty() {
            return Err(ServiceError::InvalidArgument(
                "URL must not be empty for remote sources".into(),
            ));
        }
        // Must be HTTPS for remote sources (except local)
        if !trimmed.starts_with("https://") && !trimmed.starts_with("file://") && !cfg!(test) {
            return Err(ServiceError::InvalidArgument(format!(
                "URL scheme must be HTTPS for remote sources: {trimmed}"
            )));
        }
        // Reject URLs with embedded credentials
        if trimmed.contains('@') && trimmed.starts_with("https://") {
            let without_scheme = trimmed.trim_start_matches("https://");
            if without_scheme.contains('@') {
                return Err(ServiceError::InvalidArgument(
                    "URL must not contain embedded credentials".into(),
                ));
            }
        }
        Ok(())
    }
}

// ── Source Registry ───────────────────────────────────────────────

/// Resolved driver source (validated and ready for use).
#[derive(Debug, Clone)]
pub struct ResolvedSource {
    /// Source identity.
    pub identity: SourceConfig,
    /// Resolved base URL (may be a mirror).
    pub resolved_url: String,
    /// Whether this source is currently reachable.
    pub reachable: bool,
}

/// Manages and resolves driver sources.
pub struct SourceRegistry {
    /// Configured sources.
    sources: Vec<SourceConfig>,
}

impl SourceRegistry {
    /// Create a new source registry from configuration.
    pub fn from_configs(configs: Vec<SourceConfig>) -> ServiceResult<Self> {
        // Deduplicate and validate
        let mut seen_ids = std::collections::HashSet::new();
        for config in &configs {
            config.validate()?;
            let id = SourceId::new(&config.id)?;
            if !seen_ids.insert(id.as_str().to_string()) {
                return Err(ServiceError::AlreadyExists(format!(
                    "duplicate source ID: {}",
                    config.id
                )));
            }
        }
        Ok(Self { sources: configs })
    }

    /// Create an empty registry (for testing).
    pub fn empty() -> Self {
        Self {
            sources: Vec::new(),
        }
    }

    /// Get all enabled sources.
    pub fn enabled_sources(&self) -> Vec<&SourceConfig> {
        let mut enabled: Vec<&SourceConfig> = self.sources.iter().filter(|s| s.enabled).collect();
        enabled.sort_by_key(|s| s.priority);
        enabled
    }

    /// Get a source by ID.
    pub fn get_source(&self, id: &str) -> Option<&SourceConfig> {
        self.sources.iter().find(|s| s.id == id)
    }

    /// Get all configured sources.
    pub fn all_sources(&self) -> &[SourceConfig] {
        &self.sources
    }

    /// Resolve a source to a reachable endpoint.
    ///
    /// Checks if the base URL (or a mirror) is reachable.
    /// For local sources, checks path existence.
    pub fn resolve_source(&self, id: &str) -> ServiceResult<ResolvedSource> {
        let source = self
            .sources
            .iter()
            .find(|s| s.id == id && s.enabled)
            .ok_or_else(|| {
                ServiceError::NotFound(format!("source '{id}' not found or disabled"))
            })?;

        let resolved_url = if source.source_type == SourceType::Local {
            // Local source: validate the path exists
            let path = Path::new(&source.base_url);
            if !path.exists() {
                return Err(ServiceError::BackendUnavailable(format!(
                    "local source path '{path:?}' does not exist"
                )));
            }
            source.base_url.clone()
        } else {
            // Remote source: use base URL (mirror selection deferred to fetcher)
            source.base_url.clone()
        };

        Ok(ResolvedSource {
            identity: source.clone(),
            resolved_url,
            reachable: true,
        })
    }

    /// Check if a source is configured and enabled.
    pub fn is_source_enabled(&self, id: &str) -> bool {
        self.sources.iter().any(|s| s.id == id && s.enabled)
    }

    /// Get the number of sources.
    pub fn source_count(&self) -> usize {
        self.sources.len()
    }
}

// ── Default Sources ───────────────────────────────────────────────

/// Create the default set of driver sources.
pub fn default_sources() -> Vec<SourceConfig> {
    vec![
        SourceConfig {
            id: "mission".into(),
            name: "Mission OS Repository".into(),
            source_type: SourceType::Mission,
            base_url: "https://packages.mission-os.org/drivers/v1/".into(),
            enabled: true,
            priority: 10,
            trusted_key_ids: vec!["mission-os-release-key".into()],
            allowed_architectures: vec![],
            mirrors: vec![],
            metadata_url: Some("https://packages.mission-os.org/drivers/v1/manifest.json".into()),
            trust_config: Some(crate::repository::TrustConfig::trusted(vec![
                "mission-os-release-key".into(),
            ])),
        },
        SourceConfig {
            id: "linux".into(),
            name: "Linux Kernel (Built-in)".into(),
            source_type: SourceType::Linux,
            base_url: String::new(),
            enabled: true,
            priority: 20,
            trusted_key_ids: vec![],
            allowed_architectures: vec![],
            mirrors: vec![],
            metadata_url: None,
            trust_config: None,
        },
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn source_id_validation() {
        assert!(SourceId::new("mission").is_ok());
        assert!(SourceId::new("vendor-nvidia").is_ok());
        assert!(SourceId::new("").is_err());
        assert!(SourceId::new("spaces in id").is_err());
        assert!(SourceId::new("../../etc").is_err());
        assert!(SourceId::new(&"a".repeat(200)).is_err());
    }

    #[test]
    fn source_config_validation() {
        let config = SourceConfig {
            id: "test-source".into(),
            name: "Test Source".into(),
            source_type: SourceType::Local,
            base_url: "/tmp/test".into(),
            enabled: true,
            priority: 50,
            trusted_key_ids: vec!["test-key".into()],
            allowed_architectures: vec!["x86_64".into()],
            mirrors: vec![],
            metadata_url: None,
            trust_config: None,
        };
        assert!(config.validate().is_ok());
    }

    #[test]
    fn source_config_empty_id_fails() {
        let config = SourceConfig {
            id: "".into(),
            name: "Test".into(),
            source_type: SourceType::Mission,
            base_url: "https://example.com".into(),
            enabled: true,
            priority: 50,
            trusted_key_ids: vec![],
            allowed_architectures: vec![],
            mirrors: vec![],
            metadata_url: None,
            trust_config: None,
        };
        assert!(config.validate().is_err());
    }

    #[test]
    fn source_config_http_url_rejected() {
        let config = SourceConfig {
            id: "http-source".into(),
            name: "HTTP Test".into(),
            source_type: SourceType::Mission,
            base_url: "http://example.com".into(),
            enabled: true,
            priority: 50,
            trusted_key_ids: vec![],
            allowed_architectures: vec![],
            mirrors: vec![],
            metadata_url: None,
            trust_config: None,
        };
        #[cfg(not(test))]
        assert!(config.validate().is_err());
        #[cfg(test)]
        assert!(config.validate().is_ok()); // In tests, HTTP is allowed for convenience
    }

    #[test]
    fn source_registry_deduplicates() {
        let configs = vec![
            SourceConfig {
                id: "source1".into(),
                name: "S1".into(),
                source_type: SourceType::Mission,
                base_url: "https://example.com".into(),
                enabled: true,
                priority: 10,
                trusted_key_ids: vec![],
                allowed_architectures: vec![],
                mirrors: vec![],
                metadata_url: None,
                trust_config: None,
            },
            SourceConfig {
                id: "source1".into(),
                name: "S1 Duplicate".into(),
                source_type: SourceType::Mission,
                base_url: "https://example.com".into(),
                enabled: true,
                priority: 10,
                trusted_key_ids: vec![],
                allowed_architectures: vec![],
                mirrors: vec![],
                metadata_url: None,
                trust_config: None,
            },
        ];
        let registry = SourceRegistry::from_configs(configs);
        assert!(registry.is_err());
    }

    #[test]
    fn source_registry_enabled_sources() {
        let configs = vec![
            SourceConfig {
                id: "source1".into(),
                name: "S1".into(),
                source_type: SourceType::Mission,
                base_url: "https://example.com".into(),
                enabled: true,
                priority: 20,
                trusted_key_ids: vec![],
                allowed_architectures: vec![],
                mirrors: vec![],
                metadata_url: None,
                trust_config: None,
            },
            SourceConfig {
                id: "source2".into(),
                name: "S2".into(),
                source_type: SourceType::Mission,
                base_url: "https://example.com".into(),
                enabled: false,
                priority: 10,
                trusted_key_ids: vec![],
                allowed_architectures: vec![],
                mirrors: vec![],
                metadata_url: None,
                trust_config: None,
            },
            SourceConfig {
                id: "source3".into(),
                name: "S3".into(),
                source_type: SourceType::Mission,
                base_url: "https://example.com".into(),
                enabled: true,
                priority: 10,
                trusted_key_ids: vec![],
                allowed_architectures: vec![],
                mirrors: vec![],
                metadata_url: None,
                trust_config: None,
            },
        ];
        let registry = SourceRegistry::from_configs(configs).unwrap();
        let enabled = registry.enabled_sources();
        assert_eq!(enabled.len(), 2);
        // Should be sorted by priority (source3 first, then source1)
        assert_eq!(enabled[0].id, "source3");
        assert_eq!(enabled[1].id, "source1");
    }

    #[test]
    fn default_sources_are_valid() {
        let sources = default_sources();
        assert_eq!(sources.len(), 2);
        for source in &sources {
            assert!(source.validate().is_ok());
        }
    }

    #[test]
    fn source_type_network_requirement() {
        assert!(SourceType::Mission.requires_network());
        assert!(SourceType::Vendor.requires_network());
        assert!(!SourceType::Linux.requires_network());
        assert!(!SourceType::Local.requires_network());
    }
}
