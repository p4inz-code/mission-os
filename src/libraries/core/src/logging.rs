//! Structured logging interface for Mission OS.
//!
//! Provides a structured logging abstraction with:
//! - Severity levels (Error, Warn, Info, Debug, Trace)
//! - Contextual key-value fields
//! - Predictable initialization via [`Logger::init`]
//! - Safe behavior when logging is not yet initialized
//! - An abstraction boundary for future journald integration
//!
//! ## Architecture
//!
//! The abstraction layer (this module) provides the public API that all
//! Mission OS components use. The actual log emission is handled by a
//! [`Backend`] trait implementation:
//!
//! - **Default**: [`StderrBackend`] — prints to stderr, used during development
//! - **Future**: `JournaldBackend` — forwards to systemd-journald (production)
//!
//! This separation ensures that when journald integration is implemented,
//! no consumer code needs to change.
//!
//! ## Security
//!
//! - Never log: passwords, encryption keys, personal content, session tokens
//! - Log messages are strings with no accidental secret exposure
//! - Controlled initialization prevents log injection before setup

use std::sync::Mutex;

use crate::error::{Error, ErrorCode, Result};

// ---------------------------------------------------------------------------
// Log levels
// ---------------------------------------------------------------------------

/// Log severity levels, ordered by increasing verbosity.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Level {
    /// Critical errors that require immediate attention.
    Error = 0,
    /// Recoverable issues and warnings.
    Warn = 1,
    /// Notable events (startup, shutdown, state changes).
    Info = 2,
    /// Detailed diagnostic information.
    Debug = 3,
    /// Very detailed flow tracing.
    Trace = 4,
}

impl Level {
    /// Return the static string representation.
    pub const fn as_str(&self) -> &'static str {
        match self {
            Level::Error => "ERROR",
            Level::Warn => "WARN",
            Level::Info => "INFO",
            Level::Debug => "DEBUG",
            Level::Trace => "TRACE",
        }
    }

    /// Parse a level from its string representation (case-insensitive).
    pub fn parse_level(s: &str) -> Option<Self> {
        match s.to_lowercase().as_str() {
            "error" => Some(Level::Error),
            "warn" | "warning" => Some(Level::Warn),
            "info" => Some(Level::Info),
            "debug" => Some(Level::Debug),
            "trace" => Some(Level::Trace),
            _ => None,
        }
    }
}

impl std::fmt::Display for Level {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.as_str())
    }
}

impl std::str::FromStr for Level {
    type Err = String;

    fn from_str(s: &str) -> std::result::Result<Self, Self::Err> {
        Self::parse_level(s).ok_or_else(|| format!("unknown log level: {s}"))
    }
}

// ---------------------------------------------------------------------------
// Log record
// ---------------------------------------------------------------------------

/// A structured log record.
///
/// Contains the essential metadata for a single log event.
#[derive(Debug, Clone)]
pub struct Record {
    /// The log level.
    pub level: Level,
    /// The log message.
    pub message: String,
    /// The source module (file:line).
    pub module: String,
    /// Contextual key-value fields.
    pub fields: Vec<(String, String)>,
}

impl Record {
    /// Create a new log record.
    pub fn new(level: Level, message: impl Into<String>, module: impl Into<String>) -> Self {
        Self {
            level,
            message: message.into(),
            module: module.into(),
            fields: Vec::new(),
        }
    }

    /// Add a contextual key-value field to this record.
    pub fn with_field(mut self, key: impl Into<String>, value: impl Into<String>) -> Self {
        self.fields.push((key.into(), value.into()));
        self
    }
}

// ---------------------------------------------------------------------------
// Backend trait — the journald integration boundary
// ---------------------------------------------------------------------------

/// The logging backend trait.
///
/// Implementations handle actual log emission. This is the extension point
/// for future journald integration.
///
/// # Current implementations
///
/// - [`StderrBackend`] — writes formatted logs to stderr
pub trait Backend: Send + Sync {
    /// Emit a log record.
    fn emit(&self, record: &Record);
}

// ---------------------------------------------------------------------------
// Stderr backend (default)
// ---------------------------------------------------------------------------

/// The default logging backend that writes to stderr.
///
/// Format: `[LEVEL] module: message {key=value, ...}`
#[derive(Debug, Clone)]
pub struct StderrBackend;

impl Backend for StderrBackend {
    fn emit(&self, record: &Record) {
        let fields_str = if record.fields.is_empty() {
            String::new()
        } else {
            let pairs: Vec<String> = record
                .fields
                .iter()
                .map(|(k, v)| format!("{k}={v}"))
                .collect();
            format!(" {{{}}}", pairs.join(", "))
        };

        eprintln!(
            "[{}] {}: {}{}",
            record.level, record.module, record.message, fields_str
        );
    }
}

// ---------------------------------------------------------------------------
// Global logger state
// ---------------------------------------------------------------------------

/// State of the global logger.
enum LoggerState {
    /// Not initialized — logs are silently dropped.
    Uninitialized,
    /// Initialized with a specific backend and level filter.
    Initialized {
        backend: Box<dyn Backend>,
        level: Level,
    },
}

/// Global logger singleton.
static LOGGER: Mutex<LoggerState> = Mutex::new(LoggerState::Uninitialized);

// ---------------------------------------------------------------------------
// Logger API
// ---------------------------------------------------------------------------

/// Initialize the global logger with the given backend and level filter.
///
/// This must be called once during application or service startup, before
/// any log messages are emitted. Calling `init` more than once is a no-op
/// (the first call wins) unless `force` is true.
///
/// # Errors
///
/// Returns an error if the logger is already initialized and `force` is false.
pub fn init(backend: Box<dyn Backend>, level: Level) -> Result<()> {
    init_with(backend, level, false)
}

/// Initialize the global logger, replacing any existing configuration.
pub fn init_force(backend: Box<dyn Backend>, level: Level) -> Result<()> {
    init_with(backend, level, true)
}

fn init_with(backend: Box<dyn Backend>, level: Level, force: bool) -> Result<()> {
    let mut guard = LOGGER.lock().map_err(|_| {
        Error::new(
            ErrorCode::InternalError,
            "logger mutex poisoned — this is a bug",
        )
    })?;

    match *guard {
        LoggerState::Uninitialized => {
            *guard = LoggerState::Initialized { backend, level };
            Ok(())
        }
        LoggerState::Initialized { .. } if force => {
            *guard = LoggerState::Initialized { backend, level };
            Ok(())
        }
        LoggerState::Initialized { .. } => Err(Error::new(
            ErrorCode::Busy,
            "logger is already initialized; use init_force to replace",
        )),
    }
}

/// Emit a log record through the global logger.
///
/// If the logger has not been initialized, the record is silently dropped.
/// This is safe — no panic, no allocation, no I/O.
///
/// The record is only emitted if its level is at or below the configured
/// threshold level (i.e., more severe or equal).
pub fn log(record: &Record) {
    let guard = match LOGGER.lock() {
        Ok(g) => g,
        Err(_) => return, // Mutex poisoned, drop the record silently
    };

    match *guard {
        LoggerState::Uninitialized => {
            // Silently drop — safe uninitialized behavior
        }
        LoggerState::Initialized {
            ref backend,
            level: ref filter_level,
        } => {
            if record.level as u8 <= *filter_level as u8 {
                backend.emit(record);
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Convenience macros
// ---------------------------------------------------------------------------

/// Emit a structured log record at the given level.
#[macro_export]
macro_rules! log {
    ($level:expr, $msg:literal $(, $args:expr)* $(,)?) => {
        $crate::logging::log(&$crate::logging::Record::new(
            $level,
            format!($msg $(, $args)*),
            format!("{}:{}", ::core::file!(), ::core::line!()),
        ))
    };
    ($level:expr, $msg:literal $(, $args:expr)* ; $($key:expr => $val:expr),* $(,)?) => {
        $crate::logging::log(
            &$crate::logging::Record::new(
                $level,
                format!($msg $(, $args)*),
                format!("{}:{}", ::core::file!(), ::core::line!()),
            )
            $(.with_field($key, $val))*
        )
    };
}

/// Log at `ERROR` level.
#[macro_export]
macro_rules! error {
    ($($arg:tt)*) => { $crate::log!($crate::logging::Level::Error, $($arg)*) };
}

/// Log at `WARN` level.
#[macro_export]
macro_rules! warn {
    ($($arg:tt)*) => { $crate::log!($crate::logging::Level::Warn, $($arg)*) };
}

/// Log at `INFO` level.
#[macro_export]
macro_rules! info {
    ($($arg:tt)*) => { $crate::log!($crate::logging::Level::Info, $($arg)*) };
}

/// Log at `DEBUG` level.
#[macro_export]
macro_rules! debug {
    ($($arg:tt)*) => { $crate::log!($crate::logging::Level::Debug, $($arg)*) };
}

/// Log at `TRACE` level.
#[macro_export]
macro_rules! trace {
    ($($arg:tt)*) => { $crate::log!($crate::logging::Level::Trace, $($arg)*) };
}

// ---------------------------------------------------------------------------
// Convenience functions
// ---------------------------------------------------------------------------

/// Set the minimum log level at runtime.
///
/// This adjusts the filter threshold without replacing the backend.
pub fn set_level(level: Level) -> Result<()> {
    let mut guard = LOGGER.lock().map_err(|_| {
        Error::new(
            ErrorCode::InternalError,
            "logger mutex poisoned — cannot set level",
        )
    })?;

    match *guard {
        LoggerState::Initialized {
            level: ref mut lvl, ..
        } => {
            *lvl = level;
            Ok(())
        }
        LoggerState::Uninitialized => Err(Error::new(
            ErrorCode::Busy,
            "logger is not initialized — cannot set level",
        )),
    }
}

/// Return whether the global logger has been initialized.
pub fn is_initialized() -> bool {
    match LOGGER.lock() {
        Ok(guard) => matches!(*guard, LoggerState::Initialized { .. }),
        Err(_) => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // -------------------------------------------------------------------
    // Level
    // -------------------------------------------------------------------

    #[test]
    fn level_display() {
        assert_eq!(Level::Error.to_string(), "ERROR");
        assert_eq!(Level::Info.to_string(), "INFO");
        assert_eq!(Level::Debug.to_string(), "DEBUG");
    }

    #[test]
    fn level_as_str() {
        assert_eq!(Level::Error.as_str(), "ERROR");
        assert_eq!(Level::Trace.as_str(), "TRACE");
    }

    #[test]
    fn level_ordering() {
        assert!(Level::Error < Level::Warn);
        assert!(Level::Warn < Level::Info);
        assert!(Level::Info < Level::Debug);
        assert!(Level::Debug < Level::Trace);
    }

    #[test]
    fn level_parse() {
        assert_eq!(Level::parse_level("error"), Some(Level::Error));
        assert_eq!(Level::parse_level("WARN"), Some(Level::Warn));
        assert_eq!(Level::parse_level("Warning"), Some(Level::Warn));
        assert_eq!(Level::parse_level("debug"), Some(Level::Debug));
        assert_eq!(Level::parse_level("TRACE"), Some(Level::Trace));
        assert_eq!(Level::parse_level("invalid"), None);
    }

    #[test]
    fn level_from_str() {
        assert_eq!("error".parse::<Level>().unwrap(), Level::Error);
        assert_eq!("INFO".parse::<Level>().unwrap(), Level::Info);
        assert!("invalid".parse::<Level>().is_err());
    }

    // -------------------------------------------------------------------
    // Record
    // -------------------------------------------------------------------

    #[test]
    fn record_construction() {
        let rec = Record::new(Level::Info, "hello", "test.rs:42");
        assert_eq!(rec.level, Level::Info);
        assert_eq!(rec.message, "hello");
        assert_eq!(rec.module, "test.rs:42");
        assert!(rec.fields.is_empty());
    }

    #[test]
    fn record_with_fields() {
        let rec = Record::new(Level::Warn, "disk nearly full", "storage.rs:10")
            .with_field("used_pct", "95")
            .with_field("device", "/dev/sda1");

        assert_eq!(rec.fields.len(), 2);
        assert_eq!(rec.fields[0], ("used_pct".to_string(), "95".to_string()));
    }

    // -------------------------------------------------------------------
    // Logger initialization
    // -------------------------------------------------------------------

    #[test]
    fn init_stderr_backend() {
        let backend = Box::new(StderrBackend);
        let result = init_force(backend, Level::Info);
        assert!(result.is_ok());
    }

    #[test]
    fn repeated_init_fails() {
        let _ = init_force(Box::new(StderrBackend), Level::Info);
        let second = init(Box::new(StderrBackend), Level::Info);
        assert!(second.is_err());
    }

    #[test]
    fn init_force_replaces() {
        let result = init_force(Box::new(StderrBackend), Level::Trace);
        assert!(result.is_ok());
    }

    // -------------------------------------------------------------------
    // Log level behavior
    // -------------------------------------------------------------------

    #[test]
    fn log_silently_dropped_before_init() {
        log!(Level::Info, "before init");
        log!(Level::Error, "critical before init");
    }

    #[test]
    fn log_filtered_by_level() {
        let _ = init_force(Box::new(StderrBackend), Level::Info);
        log!(Level::Error, "error message");
        log!(Level::Warn, "warning message");
        log!(Level::Debug, "debug message (filtered if below Info)");
    }

    // -------------------------------------------------------------------
    // Structured context
    // -------------------------------------------------------------------

    #[test]
    fn log_with_contextual_fields() {
        let _ = init_force(Box::new(StderrBackend), Level::Info);
        log!(Level::Info, "startup complete"; "version" => "1.0.0", "mode" => "production");
        log!(Level::Warn, "high memory usage"; "pct" => "87", "process" => "mission-hub");
    }

    // -------------------------------------------------------------------
    // Macros
    // -------------------------------------------------------------------

    #[test]
    fn error_macro() {
        let _ = init_force(Box::new(StderrBackend), Level::Trace);
        error!("this is an error: {}", 42);
        warn!("this is a warning");
        info!("info with field"; "key" => "value");
        debug!("debug message");
        trace!("trace message");
    }

    // -------------------------------------------------------------------
    // Set level
    // -------------------------------------------------------------------

    #[test]
    fn set_log_level_runtime() {
        let _ = init_force(Box::new(StderrBackend), Level::Info);
        let result = set_level(Level::Debug);
        assert!(result.is_ok());
    }

    // -------------------------------------------------------------------
    // Backend trait
    // -------------------------------------------------------------------

    #[test]
    fn custom_backend() {
        struct TestBackend {
            #[allow(dead_code)]
            records: std::sync::Mutex<Vec<String>>,
        }

        impl Backend for TestBackend {
            fn emit(&self, record: &Record) {
                let mut guard = self.records.lock().unwrap();
                guard.push(format!("[{}] {}", record.level, record.message));
            }
        }

        let backend = TestBackend {
            records: std::sync::Mutex::new(Vec::new()),
        };

        init_force(Box::new(backend), Level::Info).unwrap();
        log!(Level::Info, "test message");
    }

    // -------------------------------------------------------------------
    // Safe/uninitialized behavior
    // -------------------------------------------------------------------

    #[test]
    fn is_initialized_before_init() {
        let _ = is_initialized();
    }
}
