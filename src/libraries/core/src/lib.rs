//! # mission-core
//!
//! Foundational shared library for Mission OS.
//!
//! This crate provides the core types, error framework, configuration parsing,
//! logging interface, IPC helpers, and system information queries that
//! every Mission OS component depends on.
//!
//! ## Architecture
//!
//! - **Error types:** Unified error framework used across all services and apps.
//! - **Configuration:** TOML-based configuration file parsing.
//! - **Logging:** Structured logging interface backed by `systemd-journald`.
//! - **IPC:** D-Bus connection management utilities.
//! - **Versioning:** Semantic version types for Mission OS releases.
//! - **Path resolution:** Canonical paths for Mission OS directories.
//!
//! ## Safety
//!
//! This crate contains no `unsafe` code. FFI boundaries are wrapped
//! in safe abstractions in downstream crates.

#![deny(missing_docs)]
#![deny(unreachable_pub)]
#![forbid(unsafe_code)]

/// Version information for Mission OS releases.
pub mod version;

/// Error types and result aliases used across Mission OS.
pub mod error;

/// Configuration file parsing (TOML-based).
pub mod config;

/// Structured logging interface.
pub mod logging;

/// D-Bus connection management helpers.
pub mod ipc;

/// System information queries.
pub mod sysinfo;

/// Path resolution for Mission OS directories.
pub mod paths;

pub use error::{Error, ErrorCode, Result};
pub use version::Version;
