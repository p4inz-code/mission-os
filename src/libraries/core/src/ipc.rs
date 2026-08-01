//! D-Bus connection management helpers.
//!
//! Provides generic IPC helper abstractions for Mission OS communication.
//!
//! ## Architecture
//!
//! The existing architecture (MOS-ENG-IPC-001) specifies D-Bus as the
//! primary IPC mechanism with PolKit authorization. This module provides
//! the generic mission-core helper abstractions that are already justified
//! by the architecture:
//!
//! - Connection lifecycle abstraction (bus type, state machine)
//! - Structured error mapping
//! - Timeout representation
//! - Safe lifecycle behavior
//!
//! ## What this module does NOT implement
//!
//! - Full D-Bus service APIs (belongs to individual services)
//! - PolKit authorization flows (belongs to mission-securityd/mission-privileged)
//! - Daemon processes (belongs to system services layer)
//! - Privileged operations (belongs to mission-privileged)
//!
//! The actual D-Bus wire protocol integration (via `zbus` crate) will be added
//! when the first system service is implemented. This module provides the
//! abstraction layer that those services will use.

use std::fmt;
use std::time::Duration;

use crate::error::{Error, ErrorCode, Result};

/// Which D-Bus bus to connect to.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum BusType {
    /// The system bus (privileged services).
    System,
    /// The session bus (user services and applications).
    Session,
}

impl BusType {
    /// Return the D-Bus bus address environment variable for this bus type.
    pub fn address_env_var(&self) -> &'static str {
        match self {
            BusType::System => "DBUS_SYSTEM_BUS_ADDRESS",
            BusType::Session => "DBUS_SESSION_BUS_ADDRESS",
        }
    }

    /// Return the default D-Bus bus address for this bus type.
    pub fn default_address(&self) -> &'static str {
        match self {
            BusType::System => "unix:path=/var/run/dbus/system_bus_socket",
            BusType::Session => "unix:path=/run/user/<uid>/bus",
        }
    }
}

impl fmt::Display for BusType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            BusType::System => write!(f, "system"),
            BusType::Session => write!(f, "session"),
        }
    }
}

/// Unique identifier for an IPC peer.
///
/// Follows the D-Bus naming convention: reverse domain name notation
/// (e.g., `org.mission.Security1`).
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct PeerId(String);

impl PeerId {
    /// Create a new `PeerId` from a string.
    ///
    /// # Panics
    ///
    /// In debug builds, panics if the name does not follow the
    /// reverse-domain convention (contains at least one dot).
    pub fn new(id: impl Into<String>) -> Self {
        let id = id.into();
        debug_assert!(
            id.contains('.'),
            "PeerId should follow reverse-domain convention: {id}"
        );
        Self(id)
    }

    /// Return the peer ID as a string.
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl fmt::Display for PeerId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

/// Connection state for an IPC channel.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ConnectionState {
    /// Not yet connected.
    Disconnected,
    /// Connecting in progress.
    Connecting,
    /// Connected and ready.
    Connected,
    /// Connection failed and is in a terminal error state.
    Failed,
    /// Connection lost, attempting reconnection.
    Reconnecting,
}

impl ConnectionState {
    /// Is this state connected/ready?
    pub fn is_ready(&self) -> bool {
        matches!(self, ConnectionState::Connected)
    }

    /// Is this state a failure state?
    pub fn is_failure(&self) -> bool {
        matches!(self, ConnectionState::Failed)
    }
}

impl fmt::Display for ConnectionState {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ConnectionState::Disconnected => write!(f, "disconnected"),
            ConnectionState::Connecting => write!(f, "connecting"),
            ConnectionState::Connected => write!(f, "connected"),
            ConnectionState::Failed => write!(f, "failed"),
            ConnectionState::Reconnecting => write!(f, "reconnecting"),
        }
    }
}

/// Timeout configuration for IPC operations.
///
/// Defaults to the Mission OS standard: 30 seconds for normal operations,
/// 5 seconds for health checks.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Timeout {
    /// The duration before the operation times out.
    duration: Duration,
}

impl Timeout {
    /// Create a new timeout with the given duration.
    pub const fn new(duration: Duration) -> Self {
        Self { duration }
    }

    /// Create a default timeout (30 seconds).
    pub const fn default_timeout() -> Self {
        Self {
            duration: Duration::from_secs(30),
        }
    }

    /// Create a health check timeout (5 seconds).
    pub const fn health_check() -> Self {
        Self {
            duration: Duration::from_secs(5),
        }
    }

    /// Create a short timeout for rapid operations (2 seconds).
    pub const fn short() -> Self {
        Self {
            duration: Duration::from_secs(2),
        }
    }

    /// Return the timeout duration.
    pub const fn duration(&self) -> Duration {
        self.duration
    }
}

impl Default for Timeout {
    fn default() -> Self {
        Self::default_timeout()
    }
}

impl From<Duration> for Timeout {
    fn from(duration: Duration) -> Self {
        Self { duration }
    }
}

/// Configuration for connecting to a D-Bus bus.
#[derive(Debug, Clone)]
pub struct ConnectionConfig {
    /// Which bus to connect to.
    pub bus_type: BusType,
    /// Optional well-known name to request on the bus.
    pub well_known_name: Option<PeerId>,
    /// Connection timeout.
    pub timeout: Timeout,
    /// Whether to automatically reconnect on disconnect.
    pub auto_reconnect: bool,
}

impl ConnectionConfig {
    /// Create a new connection configuration for the given bus type.
    pub fn new(bus_type: BusType) -> Self {
        Self {
            bus_type,
            well_known_name: None,
            timeout: Timeout::default_timeout(),
            auto_reconnect: true,
        }
    }

    /// Set the well-known name to request on the bus.
    pub fn with_name(mut self, name: PeerId) -> Self {
        self.well_known_name = Some(name);
        self
    }

    /// Set the connection timeout.
    pub fn with_timeout(mut self, timeout: Timeout) -> Self {
        self.timeout = timeout;
        self
    }

    /// Enable or disable automatic reconnection.
    pub fn with_auto_reconnect(mut self, auto_reconnect: bool) -> Self {
        self.auto_reconnect = auto_reconnect;
        self
    }
}

impl Default for ConnectionConfig {
    fn default() -> Self {
        Self::new(BusType::Session)
    }
}

/// An IPC connection handle.
///
/// This is a placeholder for the actual D-Bus connection that will be
/// established when the `zbus` crate is integrated. It currently provides
/// the lifecycle abstraction and state tracking.
///
/// # Future Integration
///
/// When system services are implemented (Milestone 2), this struct will
/// wrap a `zbus::Connection` and manage its lifecycle transparently.
#[derive(Debug)]
pub struct Connection {
    /// The connection configuration.
    config: ConnectionConfig,
    /// The current connection state.
    state: ConnectionState,
}

impl Connection {
    /// Create a new connection handle with the given configuration.
    ///
    /// This does not actually connect — it creates a handle in the
    /// `Disconnected` state. Call [`connect`](Self::connect) to establish
    /// the actual D-Bus connection.
    pub fn new(config: ConnectionConfig) -> Self {
        Self {
            config,
            state: ConnectionState::Disconnected,
        }
    }

    /// Create a new connection to the session bus with default settings.
    pub fn session() -> Self {
        Self::new(ConnectionConfig::new(BusType::Session))
    }

    /// Create a new connection to the system bus with default settings.
    pub fn system() -> Self {
        Self::new(ConnectionConfig::new(BusType::System))
    }

    /// Attempt to connect to the bus.
    ///
    /// This is a stub — when D-Bus integration is added, this will
    /// establish a real connection via `zbus`.
    ///
    /// Currently, this transitions the state from `Disconnected` to
    /// `Connected` without performing any actual I/O.
    pub fn connect(&mut self) -> Result<()> {
        match self.state {
            ConnectionState::Disconnected | ConnectionState::Failed => {
                // TODO: Actual D-Bus connection via zbus
                self.state = ConnectionState::Connecting;

                // Simulate connection success
                self.state = ConnectionState::Connected;
                Ok(())
            }
            ConnectionState::Connecting => Err(Error::new(
                ErrorCode::Busy,
                "connection is already in progress",
            )),
            ConnectionState::Connected => Err(Error::new(ErrorCode::Busy, "already connected")),
            ConnectionState::Reconnecting => {
                Err(Error::new(ErrorCode::Busy, "currently reconnecting"))
            }
        }
    }

    /// Disconnect from the bus.
    pub fn disconnect(&mut self) -> Result<()> {
        self.state = ConnectionState::Disconnected;
        Ok(())
    }

    /// Return the current connection state.
    pub fn state(&self) -> ConnectionState {
        self.state
    }

    /// Return a reference to the connection configuration.
    pub fn config(&self) -> &ConnectionConfig {
        &self.config
    }

    /// Is the connection currently active and ready?
    pub fn is_connected(&self) -> bool {
        self.state.is_ready()
    }

    /// Generate a D-Bus error from a mission-core error.
    ///
    /// This maps [`ErrorCode`] values to their corresponding
    /// D-Bus error names for IPC responses.
    pub fn error_to_dbus_name(error: &Error) -> &'static str {
        match error.code() {
            ErrorCode::PermissionDenied => "org.mission.Error.PermissionDenied",
            ErrorCode::InvalidArgument => "org.mission.Error.InvalidArgument",
            ErrorCode::NotFound => "org.mission.Error.NotFound",
            ErrorCode::AlreadyExists => "org.mission.Error.AlreadyExists",
            ErrorCode::Busy => "org.mission.Error.Busy",
            ErrorCode::InternalError => "org.mission.Error.InternalError",
            ErrorCode::Timeout => "org.mission.Error.Timeout",
            ErrorCode::NotSupported => "org.mission.Error.NotSupported",
            ErrorCode::DiskFull => "org.mission.Error.DiskFull",
            ErrorCode::NetworkRequired => "org.mission.Error.NetworkRequired",
            ErrorCode::ConfigError => "org.mission.Error.ConfigError",
            ErrorCode::IoError => "org.mission.Error.IoError",
            ErrorCode::Cancelled => "org.mission.Error.Cancelled",
        }
    }
}

/// A trait for IPC-capable components that can handle method calls.
///
/// This will be used by services to implement their D-Bus interfaces.
#[allow(unused_variables)]
pub trait IpcHandler {
    /// Handle a method call with the given interface, method, and arguments.
    fn handle_call(&self, interface: &str, method: &str, args: &[&str]) -> Result<Vec<u8>> {
        Err(Error::new(
            ErrorCode::NotSupported,
            format!("method {interface}.{method} is not implemented"),
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // -------------------------------------------------------------------
    // PeerId
    // -------------------------------------------------------------------

    #[test]
    fn peer_id_construction() {
        let id = PeerId::new("org.mission.Test");
        assert_eq!(id.as_str(), "org.mission.Test");
    }

    #[test]
    fn peer_id_display() {
        let id = PeerId::new("org.mission.Hub");
        assert_eq!(id.to_string(), "org.mission.Hub");
    }

    #[test]
    fn peer_id_equality() {
        let a = PeerId::new("org.mission.Test");
        let b = PeerId::new("org.mission.Test");
        let c = PeerId::new("org.mission.Other");
        assert_eq!(a, b);
        assert_ne!(a, c);
    }

    // -------------------------------------------------------------------
    // BusType
    // -------------------------------------------------------------------

    #[test]
    fn bustype_equality() {
        assert_eq!(BusType::System, BusType::System);
        assert_ne!(BusType::System, BusType::Session);
    }

    #[test]
    fn bustype_display() {
        assert_eq!(BusType::System.to_string(), "system");
        assert_eq!(BusType::Session.to_string(), "session");
    }

    #[test]
    fn bustype_env_var() {
        assert_eq!(BusType::System.address_env_var(), "DBUS_SYSTEM_BUS_ADDRESS");
        assert_eq!(
            BusType::Session.address_env_var(),
            "DBUS_SESSION_BUS_ADDRESS"
        );
    }

    // -------------------------------------------------------------------
    // ConnectionState
    // -------------------------------------------------------------------

    #[test]
    fn connection_state_transitions() {
        let state = ConnectionState::Disconnected;
        assert!(!state.is_ready());
        assert!(!state.is_failure());
        assert_ne!(state, ConnectionState::Connected);
    }

    #[test]
    fn connection_state_ready() {
        assert!(ConnectionState::Connected.is_ready());
        assert!(!ConnectionState::Failed.is_ready());
        assert!(!ConnectionState::Disconnected.is_ready());
    }

    #[test]
    fn connection_state_failure() {
        assert!(ConnectionState::Failed.is_failure());
        assert!(!ConnectionState::Connected.is_failure());
    }

    #[test]
    fn connection_state_display() {
        assert_eq!(ConnectionState::Disconnected.to_string(), "disconnected");
        assert_eq!(ConnectionState::Connected.to_string(), "connected");
        assert_eq!(ConnectionState::Failed.to_string(), "failed");
    }

    // -------------------------------------------------------------------
    // Timeout
    // -------------------------------------------------------------------

    #[test]
    fn timeout_default() {
        let timeout = Timeout::default();
        assert_eq!(timeout.duration(), Duration::from_secs(30));
    }

    #[test]
    fn timeout_health_check() {
        let timeout = Timeout::health_check();
        assert_eq!(timeout.duration(), Duration::from_secs(5));
    }

    #[test]
    fn timeout_short() {
        let timeout = Timeout::short();
        assert_eq!(timeout.duration(), Duration::from_secs(2));
    }

    #[test]
    fn timeout_from_duration() {
        let timeout: Timeout = Duration::from_secs(10).into();
        assert_eq!(timeout.duration(), Duration::from_secs(10));
    }

    // -------------------------------------------------------------------
    // ConnectionConfig
    // -------------------------------------------------------------------

    #[test]
    fn connection_config_default() {
        let config = ConnectionConfig::default();
        assert_eq!(config.bus_type, BusType::Session);
        assert!(config.well_known_name.is_none());
        assert!(config.auto_reconnect);
    }

    #[test]
    fn connection_config_system() {
        let config = ConnectionConfig::new(BusType::System);
        assert_eq!(config.bus_type, BusType::System);
    }

    #[test]
    fn connection_config_with_name() {
        let name = PeerId::new("org.mission.TestService");
        let config = ConnectionConfig::new(BusType::System)
            .with_name(name.clone())
            .with_timeout(Timeout::short())
            .with_auto_reconnect(false);

        assert_eq!(config.well_known_name, Some(name));
        assert_eq!(config.timeout.duration(), Duration::from_secs(2));
        assert!(!config.auto_reconnect);
    }

    // -------------------------------------------------------------------
    // Connection
    // -------------------------------------------------------------------

    #[test]
    fn connection_new() {
        let conn = Connection::session();
        assert_eq!(conn.state(), ConnectionState::Disconnected);
        assert!(!conn.is_connected());
    }

    #[test]
    fn connection_connect() {
        let mut conn = Connection::session();
        assert!(conn.connect().is_ok());
        assert_eq!(conn.state(), ConnectionState::Connected);
        assert!(conn.is_connected());
    }

    #[test]
    fn connection_disconnect() {
        let mut conn = Connection::session();
        conn.connect().unwrap();
        conn.disconnect().unwrap();
        assert_eq!(conn.state(), ConnectionState::Disconnected);
        assert!(!conn.is_connected());
    }

    #[test]
    fn connection_double_connect_fails() {
        let mut conn = Connection::session();
        conn.connect().unwrap();
        let result = conn.connect();
        assert!(result.is_err());
        assert_eq!(result.unwrap_err().code(), ErrorCode::Busy);
    }

    #[test]
    fn connection_system() {
        let mut conn = Connection::system();
        assert_eq!(conn.config().bus_type, BusType::System);
        conn.connect().unwrap();
        assert!(conn.is_connected());
    }

    // -------------------------------------------------------------------
    // Error mapping
    // -------------------------------------------------------------------

    #[test]
    fn error_to_dbus_name_permission() {
        let err = Error::new(ErrorCode::PermissionDenied, "access denied");
        assert_eq!(
            Connection::error_to_dbus_name(&err),
            "org.mission.Error.PermissionDenied"
        );
    }

    #[test]
    fn error_to_dbus_name_not_found() {
        let err = Error::new(ErrorCode::NotFound, "missing");
        assert_eq!(
            Connection::error_to_dbus_name(&err),
            "org.mission.Error.NotFound"
        );
    }

    // -------------------------------------------------------------------
    // IpcHandler trait
    // -------------------------------------------------------------------

    #[test]
    fn ipc_handler_default_returns_error() {
        struct TestHandler;
        impl IpcHandler for TestHandler {}

        let handler = TestHandler;
        let result = handler.handle_call("test", "method", &[]);
        assert!(result.is_err());
        assert_eq!(result.unwrap_err().code(), ErrorCode::NotSupported);
    }

    // -------------------------------------------------------------------
    // Edge cases
    // -------------------------------------------------------------------

    #[test]
    fn timeout_const_fns() {
        const DEFAULT: Timeout = Timeout::default_timeout();
        const HEALTH: Timeout = Timeout::health_check();
        const SHORT: Timeout = Timeout::short();
        assert_eq!(DEFAULT.duration().as_secs(), 30);
        assert_eq!(HEALTH.duration().as_secs(), 5);
        assert_eq!(SHORT.duration().as_secs(), 2);
    }
}
