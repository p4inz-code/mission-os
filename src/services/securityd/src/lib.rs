//! # mission-securityd
//!
//! Mission OS system security policy daemon.
//!
//! This service manages:
//! - Firewall configuration (nftables backend)
//! - Security event auditing
//! - PolKit authorization for security operations
//! - Certificate trust store management (future)
//! - Secure Boot status (future)
//! - Sandbox/MAC policy (future)
//!
//! ## Architecture
//!
//! Per MOS-ENG-ARCH-001, mission-securityd is a **System Service** running
//! as the `mission-security` system user. It communicates via D-Bus on the
//! system bus with the well-known name `org.mission.Security1`.
//!
//! ## D-Bus Interface
//!
//! - Service: `org.mission.Security1`
//! - Object: `/org/mission/Security1`
//! - Interfaces: `org.mission.Security1`, `org.mission.Security1.Firewall`,
//!   `org.mission.Security1.Audit`
//!
//! ## Security
//!
//! - All privileged operations require PolKit authorization.
//! - All security-relevant events are logged to the audit trail.
//! - The service fails closed: if authorization state is unknown, deny.
//! - No secrets or sensitive data appear in logs, errors, or IPC messages.
//!
//! ## Safety
//!
//! This crate contains no `unsafe` code.

#![deny(missing_docs)]
#![deny(unreachable_pub)]
#![forbid(unsafe_code)]

/// Service-specific error types.
pub mod error;

/// Service configuration.
pub mod config;

/// Audit event types and logging infrastructure.
pub mod audit;

/// PolKit authorization boundary.
pub mod authz;

/// Firewall management API types.
pub mod firewall;

/// D-Bus service interface (zbus integration).
pub mod dbus;

/// D-Bus signal definitions and emission helpers.
pub mod signals;

/// nftables-compatible rule generation.
pub mod nftables;
