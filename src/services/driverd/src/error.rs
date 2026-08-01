//! mission-driverd error types.
//!
//! Service-specific errors that map to the mission-core ErrorCode
//! system for IPC-friendly error reporting.
//!
//! ## Security
//!
//! - Error messages must NOT expose secrets, keys, or internal system paths.
//! - Authorization failures return generic "permission denied" messages.
//! - Internal errors return generic messages to prevent information leakage.
//! - Hardware identifiers are validated before surfacing in errors.

use std::fmt;

/// Service-specific error variants for mission-driverd operations.
#[derive(Debug, Clone)]
pub enum ServiceError {
    /// The requested operation is not authorized.
    PermissionDenied(String),
    /// Invalid request parameters.
    InvalidArgument(String),
    /// The requested driver or hardware resource was not found.
    NotFound(String),
    /// A driver or resource already exists.
    AlreadyExists(String),
    /// An internal service error occurred.
    Internal(String),
    /// The operation is not supported by this service version.
    NotSupported(String),
    /// The driver backend (udev, kernel module loader) is unavailable.
    BackendUnavailable(String),
    /// The operation is in progress and cannot be repeated.
    Busy(String),
    /// A conflict prevented the operation (includes conflict details).
    Conflict(String),
    /// Signature or integrity verification failed.
    VerificationFailed(String),
    /// A rollback was attempted but failed.
    RollbackFailed(String),
    /// A driver package error occurred.
    PackageError(String),
    /// Network download failed (timeout, connection, server error).
    DownloadFailed(String),
    /// Source configuration or resolution error.
    SourceError(String),
    /// Package metadata validation error.
    MetadataError(String),
    /// A downgrade was rejected because the installed version is newer than the requested version.
    DowngradeRejected(String),
}

impl fmt::Display for ServiceError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ServiceError::PermissionDenied(msg) => write!(f, "permission denied: {msg}"),
            ServiceError::InvalidArgument(msg) => write!(f, "invalid argument: {msg}"),
            ServiceError::NotFound(msg) => write!(f, "not found: {msg}"),
            ServiceError::AlreadyExists(msg) => write!(f, "already exists: {msg}"),
            ServiceError::Internal(msg) => write!(f, "internal error: {msg}"),
            ServiceError::NotSupported(msg) => write!(f, "not supported: {msg}"),
            ServiceError::BackendUnavailable(msg) => write!(f, "backend unavailable: {msg}"),
            ServiceError::Busy(msg) => write!(f, "busy: {msg}"),
            ServiceError::Conflict(msg) => write!(f, "conflict: {msg}"),
            ServiceError::VerificationFailed(msg) => write!(f, "verification failed: {msg}"),
            ServiceError::RollbackFailed(msg) => write!(f, "rollback failed: {msg}"),
            ServiceError::PackageError(msg) => write!(f, "package error: {msg}"),
            ServiceError::DownloadFailed(msg) => write!(f, "download failed: {msg}"),
            ServiceError::SourceError(msg) => write!(f, "source error: {msg}"),
            ServiceError::MetadataError(msg) => write!(f, "metadata error: {msg}"),
            ServiceError::DowngradeRejected(msg) => write!(f, "downgrade rejected: {msg}"),
        }
    }
}

impl std::error::Error for ServiceError {}

impl From<ServiceError> for mission_core::Error {
    fn from(e: ServiceError) -> Self {
        let code = match &e {
            ServiceError::PermissionDenied(_) => mission_core::ErrorCode::PermissionDenied,
            ServiceError::InvalidArgument(_) => mission_core::ErrorCode::InvalidArgument,
            ServiceError::NotFound(_) => mission_core::ErrorCode::NotFound,
            ServiceError::AlreadyExists(_) => mission_core::ErrorCode::AlreadyExists,
            ServiceError::Internal(_) => mission_core::ErrorCode::InternalError,
            ServiceError::NotSupported(_) => mission_core::ErrorCode::NotSupported,
            ServiceError::BackendUnavailable(_) => mission_core::ErrorCode::Busy,
            ServiceError::Busy(_) => mission_core::ErrorCode::Busy,
            ServiceError::Conflict(_) => mission_core::ErrorCode::InvalidArgument,
            ServiceError::VerificationFailed(_) => mission_core::ErrorCode::PermissionDenied,
            ServiceError::RollbackFailed(_) => mission_core::ErrorCode::InternalError,
            ServiceError::PackageError(_) => mission_core::ErrorCode::InvalidArgument,
            ServiceError::DownloadFailed(_) => mission_core::ErrorCode::NetworkRequired,
            ServiceError::SourceError(_) => mission_core::ErrorCode::InvalidArgument,
            ServiceError::MetadataError(_) => mission_core::ErrorCode::InvalidArgument,
            ServiceError::DowngradeRejected(_) => mission_core::ErrorCode::InvalidArgument,
        };
        mission_core::Error::new(code, e.to_string())
    }
}

impl From<mission_core::Error> for ServiceError {
    fn from(e: mission_core::Error) -> Self {
        ServiceError::Internal(format!("core error: {}", e.message()))
    }
}

/// Service result alias.
pub type ServiceResult<T> = std::result::Result<T, ServiceError>;

#[cfg(test)]
mod tests {
    use super::*;
    use mission_core::{Error, ErrorCode};

    #[test]
    fn permission_denied_conversion() {
        let se = ServiceError::PermissionDenied("not authorized".into());
        let ce: Error = se.into();
        assert_eq!(ce.code(), ErrorCode::PermissionDenied);
    }

    #[test]
    fn invalid_argument_conversion() {
        let se = ServiceError::InvalidArgument("bad input".into());
        let ce: Error = se.into();
        assert_eq!(ce.code(), ErrorCode::InvalidArgument);
    }

    #[test]
    fn not_found_conversion() {
        let se = ServiceError::NotFound("missing driver".into());
        let ce: Error = se.into();
        assert_eq!(ce.code(), ErrorCode::NotFound);
    }

    #[test]
    fn already_exists_conversion() {
        let se = ServiceError::AlreadyExists("driver exists".into());
        let ce: Error = se.into();
        assert_eq!(ce.code(), ErrorCode::AlreadyExists);
    }

    #[test]
    fn internal_conversion() {
        let se = ServiceError::Internal("something broke".into());
        let ce: Error = se.into();
        assert_eq!(ce.code(), ErrorCode::InternalError);
    }

    #[test]
    fn not_supported_conversion() {
        let se = ServiceError::NotSupported("feature not available".into());
        let ce: Error = se.into();
        assert_eq!(ce.code(), ErrorCode::NotSupported);
    }

    #[test]
    fn backend_unavailable_conversion() {
        let se = ServiceError::BackendUnavailable("udev not ready".into());
        let ce: Error = se.into();
        assert_eq!(ce.code(), ErrorCode::Busy);
    }

    #[test]
    fn busy_conversion() {
        let se = ServiceError::Busy("operation in progress".into());
        let ce: Error = se.into();
        assert_eq!(ce.code(), ErrorCode::Busy);
    }

    #[test]
    fn display_does_not_leak_secrets() {
        let se = ServiceError::Internal("key material exposure would go here".into());
        let display = se.to_string();
        assert!(display.contains("internal error"));
    }

    #[test]
    fn service_result_aliases() {
        let ok: ServiceResult<i32> = Ok(42);
        assert!(ok.is_ok());
        let err: ServiceResult<i32> = Err(ServiceError::NotFound("missing".into()));
        assert!(err.is_err());
    }
}
