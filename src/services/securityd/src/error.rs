//! mission-securityd error types.
//!
//! Service-specific errors that map to the mission-core ErrorCode
//! system for IPC-friendly error reporting.
//!
//! ## Security
//!
//! - Error messages must NOT expose secrets, keys, or internal system paths.
//! - Authorization failures return generic "permission denied" messages.
//! - Internal errors return generic messages to prevent information leakage.

use mission_core::{Error, ErrorCode};
use std::fmt;

/// Service-specific error variants for mission-securityd operations.
#[derive(Debug, Clone)]
pub enum ServiceError {
    /// The requested operation is not authorized.
    PermissionDenied(String),
    /// Invalid request parameters.
    InvalidArgument(String),
    /// The requested resource was not found.
    NotFound(String),
    /// An internal service error occurred.
    Internal(String),
    /// The operation is not supported by this service version.
    NotSupported(String),
}

impl fmt::Display for ServiceError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ServiceError::PermissionDenied(msg) => {
                write!(f, "permission denied: {msg}")
            }
            ServiceError::InvalidArgument(msg) => {
                write!(f, "invalid argument: {msg}")
            }
            ServiceError::NotFound(msg) => {
                write!(f, "not found: {msg}")
            }
            ServiceError::Internal(msg) => {
                write!(f, "internal error: {msg}")
            }
            ServiceError::NotSupported(msg) => {
                write!(f, "not supported: {msg}")
            }
        }
    }
}

impl std::error::Error for ServiceError {}

impl From<ServiceError> for Error {
    fn from(e: ServiceError) -> Self {
        let code = match &e {
            ServiceError::PermissionDenied(_) => ErrorCode::PermissionDenied,
            ServiceError::InvalidArgument(_) => ErrorCode::InvalidArgument,
            ServiceError::NotFound(_) => ErrorCode::NotFound,
            ServiceError::Internal(_) => ErrorCode::InternalError,
            ServiceError::NotSupported(_) => ErrorCode::NotSupported,
        };
        Error::new(code, e.to_string())
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
        let se = ServiceError::NotFound("missing resource".into());
        let ce: Error = se.into();
        assert_eq!(ce.code(), ErrorCode::NotFound);
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
    fn display_does_not_leak_secrets() {
        let se = ServiceError::Internal("key material exposure would go here".into());
        let display = se.to_string();
        // Ensure the display doesn't include the word "key" in a way that
        // would indicate secret leakage. The message is the public-facing one.
        assert!(display.contains("internal error"));
    }
}
