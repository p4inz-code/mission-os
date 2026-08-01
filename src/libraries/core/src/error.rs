//! Canonical error framework for Mission OS.
//!
//! Provides structured, categorized errors with stable identification,
//! meaningful Display/Debug output, and proper source propagation.
//! No secrets or sensitive system information are leaked in error messages.

use std::fmt;

/// Stable error codes for IPC-friendly error mapping.
///
/// These align with the standard Mission OS IPC error codes defined
/// in the IPC architecture (MOS-ENG-IPC-001 §8.2).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ErrorCode {
    /// The request failed authentication or authorization.
    PermissionDenied = 100,
    /// Malformed input was provided.
    InvalidArgument = 101,
    /// A resource was not found.
    NotFound = 102,
    /// A resource already exists.
    AlreadyExists = 103,
    /// The service or resource is busy.
    Busy = 104,
    /// An unexpected internal failure occurred.
    InternalError = 105,
    /// The operation timed out.
    Timeout = 106,
    /// The requested feature is not available.
    NotSupported = 107,
    /// Insufficient storage space.
    DiskFull = 108,
    /// Network is required but unavailable.
    NetworkRequired = 109,
    /// Configuration parsing or validation failed.
    ConfigError = 110,
    /// An I/O operation failed.
    IoError = 111,
    /// The operation was cancelled.
    Cancelled = 112,
}

impl ErrorCode {
    /// Return a human-readable description for this error code.
    pub fn description(&self) -> &'static str {
        match self {
            ErrorCode::PermissionDenied => "permission denied",
            ErrorCode::InvalidArgument => "invalid argument",
            ErrorCode::NotFound => "not found",
            ErrorCode::AlreadyExists => "already exists",
            ErrorCode::Busy => "busy",
            ErrorCode::InternalError => "internal error",
            ErrorCode::Timeout => "timeout",
            ErrorCode::NotSupported => "not supported",
            ErrorCode::DiskFull => "disk full",
            ErrorCode::NetworkRequired => "network required",
            ErrorCode::ConfigError => "configuration error",
            ErrorCode::IoError => "I/O error",
            ErrorCode::Cancelled => "cancelled",
        }
    }

    /// Return the numeric code for D-Bus / IPC error responses.
    pub const fn code(&self) -> u32 {
        *self as u32
    }
}

impl fmt::Display for ErrorCode {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{} ({})", self.description(), self.code())
    }
}

/// Unified error type for Mission OS components.
///
/// Every error carries a stable [`ErrorCode`], a human-readable message,
/// and optionally a source error for chaining.
#[derive(Debug)]
pub struct Error {
    /// The error code for IPC-friendly identification.
    code: ErrorCode,
    /// Human-readable error message.
    /// Never contains secrets or sensitive system information.
    message: String,
    /// The source error, if any, for diagnostic chaining.
    source: Option<Box<dyn std::error::Error + Send + Sync>>,
}

impl Error {
    /// Create a new error with the given code and message.
    pub fn new(code: ErrorCode, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
            source: None,
        }
    }

    /// Create a new error with a source cause.
    pub fn with_source(
        code: ErrorCode,
        message: impl Into<String>,
        source: impl Into<Box<dyn std::error::Error + Send + Sync>>,
    ) -> Self {
        Self {
            code,
            message: message.into(),
            source: Some(source.into()),
        }
    }

    /// Return the error code.
    pub const fn code(&self) -> ErrorCode {
        self.code
    }

    /// Return the human-readable message.
    pub fn message(&self) -> &str {
        &self.message
    }
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}: {}", self.code.description(), self.message)?;
        if let Some(ref src) = self.source {
            write!(f, " ({src})")?;
        }
        Ok(())
    }
}

impl std::error::Error for Error {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        self.source
            .as_deref()
            .map(|e| e as &(dyn std::error::Error + 'static))
    }
}

// Error is automatically Send + Sync because all its fields implement those traits.
fn _assert_send_sync() {
    fn assert_send<T: Send>() {}
    fn assert_sync<T: Sync>() {}
    assert_send::<Error>();
    assert_sync::<Error>();
}

// ---------------------------------------------------------------------------
// From impls — convert common error types into our Error
// ---------------------------------------------------------------------------

impl From<std::io::Error> for Error {
    fn from(e: std::io::Error) -> Self {
        let code = match e.kind() {
            std::io::ErrorKind::NotFound => ErrorCode::NotFound,
            std::io::ErrorKind::PermissionDenied => ErrorCode::PermissionDenied,
            std::io::ErrorKind::AlreadyExists => ErrorCode::AlreadyExists,
            std::io::ErrorKind::TimedOut => ErrorCode::Timeout,
            std::io::ErrorKind::StorageFull => ErrorCode::DiskFull,
            std::io::ErrorKind::Interrupted => ErrorCode::Cancelled,
            _ => ErrorCode::IoError,
        };
        Self::with_source(code, "I/O operation failed", e)
    }
}

impl From<serde_json::Error> for Error {
    fn from(e: serde_json::Error) -> Self {
        Self::with_source(ErrorCode::ConfigError, "JSON serialization error", e)
    }
}

impl From<Box<dyn std::error::Error + Send + Sync>> for Error {
    fn from(e: Box<dyn std::error::Error + Send + Sync>) -> Self {
        Self::with_source(ErrorCode::InternalError, "an unexpected error occurred", e)
    }
}

/// Convenience alias for `Result<T, mission_core::Error>`.
pub type Result<T> = std::result::Result<T, Error>;

#[cfg(test)]
mod tests {
    use super::*;
    use std::error::Error as StdError;

    // -------------------------------------------------------------------
    // Construction
    // -------------------------------------------------------------------

    #[test]
    fn error_new() {
        let err = Error::new(ErrorCode::NotFound, "config file missing");
        assert_eq!(err.code(), ErrorCode::NotFound);
        assert_eq!(err.message(), "config file missing");
    }

    #[test]
    fn error_with_source() {
        let io_err = std::io::Error::new(std::io::ErrorKind::NotFound, "no such file");
        let err = Error::with_source(ErrorCode::IoError, "failed to read config", io_err);
        assert_eq!(err.code(), ErrorCode::IoError);
        assert!(err.source.is_some());
    }

    #[test]
    fn error_code_description() {
        assert_eq!(ErrorCode::NotFound.description(), "not found");
        assert_eq!(
            ErrorCode::PermissionDenied.description(),
            "permission denied"
        );
        assert_eq!(ErrorCode::Timeout.description(), "timeout");
    }

    #[test]
    fn error_code_numeric() {
        assert_eq!(ErrorCode::PermissionDenied.code(), 100);
        assert_eq!(ErrorCode::InvalidArgument.code(), 101);
        assert_eq!(ErrorCode::NotFound.code(), 102);
        assert_eq!(ErrorCode::Timeout.code(), 106);
    }

    // -------------------------------------------------------------------
    // Conversion
    // -------------------------------------------------------------------

    #[test]
    fn error_from_io_not_found() {
        let io_err = std::io::Error::new(std::io::ErrorKind::NotFound, "file missing");
        let err: Error = io_err.into();
        assert_eq!(err.code(), ErrorCode::NotFound);
        assert!(err.source.is_some());
    }

    #[test]
    fn error_from_io_permission_denied() {
        let io_err = std::io::Error::new(std::io::ErrorKind::PermissionDenied, "access denied");
        let err: Error = io_err.into();
        assert_eq!(err.code(), ErrorCode::PermissionDenied);
    }

    #[test]
    fn error_from_serde_json() {
        let json_err = serde_json::from_str::<String>("").unwrap_err();
        let err: Error = json_err.into();
        assert_eq!(err.code(), ErrorCode::ConfigError);
    }

    // -------------------------------------------------------------------
    // Display
    // -------------------------------------------------------------------

    #[test]
    fn error_display_simple() {
        let err = Error::new(ErrorCode::NotFound, "test");
        assert_eq!(err.to_string(), "not found: test");
    }

    #[test]
    fn error_display_with_source() {
        let io_err = std::io::Error::new(std::io::ErrorKind::NotFound, "no such file");
        let err = Error::with_source(ErrorCode::IoError, "failed to read", io_err);
        let msg = err.to_string();
        assert!(msg.contains("failed to read"));
        assert!(msg.contains("no such file"));
    }

    // -------------------------------------------------------------------
    // Propagation
    // -------------------------------------------------------------------

    #[test]
    fn error_source_chain() {
        let inner = std::io::Error::new(std::io::ErrorKind::NotFound, "inner cause");
        let err = Error::with_source(ErrorCode::NotFound, "outer message", inner);
        let source = StdError::source(&err).unwrap();
        assert_eq!(source.to_string(), "inner cause");
    }

    // -------------------------------------------------------------------
    // Error cases
    // -------------------------------------------------------------------

    #[test]
    fn error_empty_message() {
        let err = Error::new(ErrorCode::InternalError, "");
        assert_eq!(err.to_string(), "internal error: ");
    }

    #[test]
    fn error_code_consistency() {
        // All codes should be unique (checked manually via the discriminant)
        assert_ne!(
            ErrorCode::PermissionDenied as u32,
            ErrorCode::NotFound as u32
        );
        assert_ne!(ErrorCode::Busy as u32, ErrorCode::Timeout as u32);
    }

    #[test]
    fn error_is_send_sync() {
        fn assert_send<T: Send>() {}
        fn assert_sync<T: Sync>() {}
        assert_send::<Error>();
        assert_sync::<Error>();
    }
}
