//! # mission-driverd
//!
//! Mission OS hardware driver management daemon.
//!
//! This service manages:
//! - Hardware detection (udev integration boundary)
//! - Driver discovery and inventory
//! - Driver matching and compatibility checking
//! - Driver install/update/remove request pipeline
//! - Driver signature verification (future)
//! - Hardware compatibility database
//!
//! ## Architecture
//!
//! Per MOS-ENG-MOD-001, mission-driverd is a **System Service** running
//! as root. It communicates via D-Bus on the system bus with the
//! well-known name `org.mission.Driver1`.
//!
//! ## D-Bus Interface
//!
//! - Service: `org.mission.Driver1`
//! - Object: `/org/mission/Driver1`
//! - Interfaces:
//!   - `org.mission.Driver1` — Core service interface
//!   - `org.mission.Driver1.Inventory` — Driver inventory and discovery
//!   - `org.mission.Driver1.Management` — Driver install/update/remove
//!
//! ## Security
//!
//! - All privileged operations require PolKit authorization (org.mission.driver.*).
//! - All security-relevant events are logged to the audit trail.
//! - The service fails closed: if authorization state is unknown, deny.
//! - No secrets or sensitive data appear in logs, errors, or IPC messages.
//! - No unsafe code.
//!
//! ## M2-D: Driver Execution Engine
//!
//! M2-D adds the real backend for:
//! - Real udev-based hardware enumeration (hwdetect)
//! - Kernel module management (kmod)
//! - Driver package management (package)
//! - Signature verification (verification)
//! - Hardware↔driver matching (matching)
//! - Conflict detection (conflict)
//! - Install/Update/Remove execution with rollback (execution)
//! - Real PolKit authorization (polkit)
//!
//! ## Safety
//!
//! This crate contains minimal `unsafe` code, isolated to the `kmod`
//! module for kernel module load/unload syscalls. All other modules
//! are fully safe Rust.
//!
//! `kmod` uses `forbid(unsafe_code)` lifted with `#[allow(unsafe_code)]`
//! only for the specific libc syscall wrappers.

#![deny(missing_docs)]
#![deny(unreachable_pub)]
// Note: unsafe code is isolated to the kmod module for kernel module
// load/unload via libc syscalls. All other modules are fully safe Rust.
// forbid is NOT used because kmod requires #[allow(unsafe_code)] on
// specific Linux-only syscall wrappers.
#![deny(unsafe_code)]

/// Service-specific error types.
pub mod error;

/// Service configuration.
pub mod config;

/// Driver inventory models and discovery.
pub mod inventory;

/// Audit event types and logging infrastructure.
pub mod audit;

/// PolKit authorization boundary.
pub mod authz;

/// D-Bus service interface (zbus integration).
pub mod dbus;

/// D-Bus signal definitions and emission helpers.
pub mod signals;

/// Hardware detection via sysfs (real udev enumeration).
pub mod hwdetect;

/// Kernel module management (safe libc syscall wrappers).
pub mod kmod;

/// Driver signature verification (mission-crypto integration).
pub mod verification;

/// Hardware ↔ driver matching.
pub mod matching;

/// Conflict detection for driver operations.
pub mod conflict;

/// Driver package management.
pub mod package;

/// Driver execution engine (install/update/remove with rollback).
pub mod execution;

/// Real PolKit D-Bus integration.
pub mod polkit;

/// Driver source architecture and trust model (M2-E).
pub mod source;

/// Package metadata with strict validation (M2-E).
pub mod metadata;

/// HTTPS package acquisition (M2-E).
pub mod fetch;

/// Driver selection pipeline (M2-E).
pub mod selector;

/// Repository metadata model with authenticated verification (M2-F).
pub mod repository;

/// Driver package cache management (M2-F).
pub mod cache;

/// Download state machine with resume and retry (M2-F).
pub mod download;
