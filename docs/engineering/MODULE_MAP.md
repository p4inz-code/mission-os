# Mission OS Module Map

**Document ID:** MOS-ENG-MOD-001
**Version:** 1.0
**Status:** Draft
**Last Updated:** July 2026

---

## 1. Purpose

This document defines every modular component of Mission OS, its responsibilities, dependencies, consumers, privilege level, security boundary, and interfaces.

Modules are the canonical building blocks. No implementation may introduce a module not listed here without explicit architectural review.

---

## 2. Module Index

| ID | Module | Type | Privilege |
|----|--------|------|-----------|
| MOS-MOD-001 | mission-core | Shared Library | None |
| MOS-MOD-002 | mission-crypto | Shared Library | None |
| MOS-MOD-003 | mission-ui | Shared Library | None |
| MOS-MOD-004 | mission-securityd | System Service | System (root) |
| MOS-MOD-005 | mission-updated | System Service | System (root) |
| MOS-MOD-006 | mission-driverd | System Service | System (root) |
| MOS-MOD-007 | mission-privileged | System Service | System (root) |
| MOS-MOD-008 | mission-settingsd | User Service | User |
| MOS-MOD-009 | mission-privacyd | User Service | User |
| MOS-MOD-010 | mission-sessiond | User Service | User |
| MOS-MOD-011 | mission-store | Application | User |
| MOS-MOD-012 | mission-hub | Application | User |
| MOS-MOD-013 | mission-settings | Application | User |
| MOS-MOD-014 | mission-privacy-center | Application | User |
| MOS-MOD-015 | mission-security-center | Application | User |
| MOS-MOD-016 | mission-recovery-center | Application | User |
| MOS-MOD-017 | mission-diagnostics | Application | User |
| MOS-MOD-018 | mission-file-manager | Application | User |
| MOS-MOD-019 | mission-update-manager | Application | User |
| MOS-MOD-020 | mission-driver-manager | Application | User |
| MOS-MOD-021 | mission-installer | Application | System (temporary) |
| MOS-MOD-022 | mission-recovery-env | System Image | System (root) |
| MOS-MOD-023 | mission-network | Application + Service | Mixed |
| MOS-MOD-024 | mission-accessibility | Application + Service | User |
| MOS-MOD-025 | mission-workspaces | User Service | User |

---

## 3. Module Definitions

### 3.1 MOS-MOD-001: mission-core

**Purpose:** Shared foundational library for all Mission OS components.

**Responsibilities:**
- Common data structures and types
- Configuration file parsing (TOML-based)
- Logging interface
- Error types and handling
- IPC helpers
- System information queries
- Permission checking helpers
- Version information
- Path resolution

**Dependencies:** glibc, libsystemd (journal integration)

**Consumers:** Every Mission OS service and application

**Privilege Level:** None (shared library)

**Security Boundary:** None (process inherits caller's privileges)

**Data Ownership:** None (no persistent state)

**Public Interfaces:**
- `libmission_core.so` — C API with versioned symbols
- Header files: `<mission/core.h>`

**Testing Requirements:**
- Unit tests for all public API functions
- Fuzz testing for configuration parsers

**Failure Behavior:** Library functions return error codes. No abort() unless preconditions are fatally violated.

**Recovery Behavior:** N/A (no persistent state)

---

### 3.2 MOS-MOD-002: mission-crypto

**Purpose:** Cryptographic operations shared across Mission OS.

**Responsibilities:**
- Key generation
- Encryption/decryption (LUKS integration)
- Signing/verification
- Hash computation
- Secure random number generation
- Key wrapping
- Recovery key management

**Dependencies:** mission-core, libsodium / OpenSSL 3.x

**Consumers:** mission-securityd, mission-privileged, mission-updated, mission-installer

**Privilege Level:** None (shared library)

**Security Boundary:** Must not leak key material through return values, logs, or core dumps.

**Data Ownership:** None

**Public Interfaces:**
- `libmission_crypto.so` — C API
- Header files: `<mission/crypto.h>`

**Testing Requirements:**
- Known-answer tests for all algorithms
- Property-based tests for key generation
- Memory scrubbing verification

**Failure Behavior:** Fail closed on cryptographic errors. Never return partial keys.

**Recovery Behavior:** N/A

---

### 3.3 MOS-MOD-003: mission-ui

**Purpose:** Reusable UI components for all Mission OS applications.

**Responsibilities:**
- QML component library (mission-ui QML module)
- Design system tokens
- Theme support (Dark, Light, High Contrast)
- Common dialogs (confirm, error, progress)
- Navigation components (sidebar, breadcrumbs, tabs)
- Accessibility wrappers

**Dependencies:** Qt 6, KDE Kirigami, KDE Frameworks

**Consumers:** All Mission OS applications

**Privilege Level:** None (UI library, runs in application process)

**Security Boundary:** Never handle secrets. Never make authorization decisions.

**Data Ownership:** None

**Public Interfaces:**
- QML module: `org.mission.ui`
- C++ plugin: `libmission_ui_plugin.so`

**Testing Requirements:**
- Visual regression tests
- Accessibility validation tests
- Keyboard navigation tests

**Failure Behavior:** UI components degrade gracefully. Missing themes fall back to defaults.

**Recovery Behavior:** N/A

---

### 3.4 MOS-MOD-004: mission-securityd

**Purpose:** System security policy daemon.

**Responsibilities:**
- Firewall management (nftables)
- Mandatory Access Control policy
- Application sandbox management
- Security event monitoring
- Audit log management
- Certificate trust store
- Secure Boot status
- TPM interaction

**Dependencies:** mission-core, mission-crypto, nftables, tpm2-tss

**Consumers:** mission-security-center, mission-hub

**Privilege Level:** System (runs as root or mission-security system user)

**Security Boundary:** Critical. Compromise of this service weakens all security guarantees.

**Data Ownership:** Audit logs, firewall rules, trust store

**Public Interfaces:**
- D-Bus: `org.mission.Security1`
- PolKit actions: `org.mission.security.*`

**Testing Requirements:**
- Integration tests with nftables
- Security audit tests
- Fuzz testing of D-Bus interface
- Property-based tests for policy evaluation

**Failure Behavior:** Fail closed. If firewall cannot be applied, deny all until resolved.

**Recovery Behavior:** Automatic restart via systemd. State recovery from persistent configuration.

---

### 3.5 MOS-MOD-005: mission-updated

**Purpose:** System update service.

**Responsibilities:**
- Update check scheduling
- Package download and verification
- Snapshot creation before updates
- Update application
- Rollback management
- Update cache management

**Dependencies:** mission-core, mission-crypto, dpkg/APT

**Consumers:** mission-update-manager, mission-hub

**Privilege Level:** System (runs as root)

**Security Boundary:** Critical. Compromise of this service could install malicious updates.

**Data Ownership:** Update cache, snapshot storage, update history

**Public Interfaces:**
- D-Bus: `org.mission.Update1`
- PolKit actions: `org.mission.update.*`

**Testing Requirements:**
- Integration tests with staged updates
- Rollback verification
- Download resume testing
- Verification failure handling

**Failure Behavior:** Never apply an update that fails verification. Preserve previous state.

**Recovery Behavior:** Automatic rollback on installation failure.

---

### 3.6 MOS-MOD-006: mission-driverd

**Purpose:** Hardware driver management service.

**Responsibilities:**
- Hardware detection (udev integration)
- Driver matching and installation
- Driver signature verification
- Driver update management
- Driver rollback
- Hardware compatibility database

**Dependencies:** mission-core, mission-crypto, udev, kernel modules

**Consumers:** mission-driver-manager, mission-hub, mission-diagnostics

**Privilege Level:** System (runs as root)

**Security Boundary:** High. Unsigned kernel modules are a security risk.

**Data Ownership:** Driver database, hardware compatibility records

**Public Interfaces:**
- D-Bus: `org.mission.Driver1`
- PolKit actions: `org.mission.driver.*`

**Testing Requirements:**
- Hardware emulation tests
- Signature verification tests
- Rollback tests
- Conflict detection tests

**Failure Behavior:** Reject unsigned/unverified drivers. Never install conflicting drivers.

**Recovery Behavior:** Automatic rollback of failed driver installation.

---

### 3.7 MOS-MOD-007: mission-privileged

**Purpose:** Escalation proxy for operations requiring temporary root privileges.

**Responsibilities:**
- Execute privileged operations on behalf of unprivileged callers
- Validate operation against security policy
- Log all privileged operations
- Rate-limit elevation requests

**Dependencies:** mission-core, PolKit

**Consumers:** All user services requiring privilege escalation

**Privilege Level:** System (runs as root)

**Security Boundary:** Critical. Must validate every operation. Must not execute arbitrary commands.

**Data Ownership:** None (transient)

**Public Interfaces:**
- D-Bus: `org.mission.Privileged1`
- Only accessible via PolKit authorization

**Testing Requirements:**
- Authorization bypass tests
- Input injection tests
- Rate limiting tests

**Failure Behavior:** Reject unauthenticated or unauthorized requests with clear error.

**Recovery Behavior:** N/A (stateless)

---

### 3.8 MOS-MOD-008: mission-settingsd

**Purpose:** Settings persistence and notification service.

**Responsibilities:**
- Read/write settings to configuration store
- Notify applications of setting changes
- Validate setting values before persistence
- Configuration profile import/export
- Configuration rollback

**Dependencies:** mission-core, JSON/TOML parser

**Consumers:** All Mission OS applications

**Privilege Level:** User (runs in user session)

**Security Boundary:** Low. Settings are user-specific.

**Data Ownership:** User configuration database

**Public Interfaces:**
- D-Bus: `org.mission.Settings1`

**Testing Requirements:**
- Concurrent read/write tests
- Validation tests
- Rollback tests

**Failure Behavior:** Write failures must not corrupt existing configuration.

**Recovery Behavior:** Automatic rollback to last known-good configuration on validation failure.

---

### 3.9 MOS-MOD-009: mission-privacyd

**Purpose:** Privacy policy enforcement service.

**Responsibilities:**
- Track active permissions (camera, mic, location, etc.)
- Enforce permission decisions
- Record permission access in audit log
- Manage telemetry opt-in/opt-out
- Handle clipboard privacy
- Manage network privacy (MAC randomization, etc.)

**Dependencies:** mission-core, mission-securityd (audit log)

**Consumers:** mission-privacy-center, mission-hub, all applications via permission checks

**Privilege Level:** User

**Security Boundary:** Medium. Enforces user privacy decisions.

**Data Ownership:** Permission grants, privacy audit log

**Public Interfaces:**
- D-Bus: `org.mission.Privacy1`

**Testing Requirements:**
- Permission enforcement tests
- Concurrent access tests
- Privacy audit log tests

**Failure Behavior:** Block sensitive operations when permission state cannot be determined.

**Recovery Behavior:** Default to "deny" on service restart until policy is reloaded.

---

### 3.10 MOS-MOD-010: mission-sessiond

**Purpose:** User session management and lifecycle.

**Responsibilities:**
- Session state tracking
- Session restore after restart/crash
- Workspace management
- Auto-start configuration
- Lock screen integration

**Dependencies:** mission-core

**Consumers:** Desktop shell, mission-hub

**Privilege Level:** User

**Security Boundary:** Low

**Data Ownership:** Session state, workspace configuration

**Public Interfaces:**
- D-Bus: `org.mission.Session1`

**Testing Requirements:**
- Session restore after crash test
- Multiple session handling

**Failure Behavior:** Session state loss only affects the last session. Previous saved state restored.

**Recovery Behavior:** Automatic session restore on crash.

---

### 3.11 MOS-MOD-011: mission-store

**Purpose:** Software distribution and management application.

**Type:** Application (User)

**Dependencies:** mission-ui, mission-core, mission-updated (as IPC consumer), mission-settingsd

**Public Interfaces:** Application window. IPC: D-Bus with mission-updated

**Testing Requirements:** UI tests, search tests, installation workflow tests

---

### 3.12 MOS-MOD-012: mission-hub

**Purpose:** Central system management dashboard.

**Type:** Application (User)

**Dependencies:** mission-ui, mission-core, mission-settingsd, all service D-Bus interfaces

**Public Interfaces:** Application window. IPC: D-Bus with all services

**Testing Requirements:** Dashboard integration tests, health score calculation tests

---

### 3.13 MOS-MOD-013: mission-settings

**Purpose:** System configuration application.

**Type:** Application (User)

**Dependencies:** mission-ui, mission-core, mission-settingsd, mission-privacyd, mission-securityd

**Testing Requirements:** Every settings page tested independently

---

### 3.14 MOS-MOD-014: mission-privacy-center

**Purpose:** Privacy configuration and monitoring.

**Type:** Application (User)

**Dependencies:** mission-ui, mission-core, mission-privacyd

**Testing Requirements:** Permission management tests, privacy score calculation

---

### 3.15 MOS-MOD-015: mission-security-center

**Purpose:** Security configuration and monitoring.

**Type:** Application (User)

**Dependencies:** mission-ui, mission-core, mission-securityd

**Testing Requirements:** Security score calculation, firewall rule management tests

---

### 3.16 MOS-MOD-016: mission-recovery-center

**Purpose:** System recovery operations.

**Type:** Application (User) — also available in recovery environment

**Dependencies:** mission-ui, mission-core, mission-privileged

**Testing Requirements:** Recovery workflow tests, restore point creation/rollback

---

### 3.17 MOS-MOD-017: mission-diagnostics

**Purpose:** Hardware and software health analysis.

**Type:** Application (User)

**Dependencies:** mission-ui, mission-core, mission-privileged, udev integration

**Testing Requirements:** Hardware detection tests, health score calculation

---

### 3.18 MOS-MOD-018: mission-file-manager

**Purpose:** File browsing and management.

**Type:** Application (User)

**Dependencies:** mission-ui, mission-core

**Testing Requirements:** File operation tests, large directory handling, permission handling

---

### 3.19 MOS-MOD-019: mission-update-manager

**Purpose:** Update management interface.

**Type:** Application (User)

**Dependencies:** mission-ui, mission-core, mission-updated

**Testing Requirements:** Update workflow tests, rollback tests

---

### 3.20 MOS-MOD-020: mission-driver-manager

**Purpose:** Driver management interface.

**Type:** Application (User)

**Dependencies:** mission-ui, mission-core, mission-driverd

**Testing Requirements:** Driver detection, installation, rollback tests

---

### 3.21 MOS-MOD-021: mission-installer

**Purpose:** System installation from ISO.

**Type:** Application (System, temporary) — runs with elevated privileges during installation

**Dependencies:** mission-ui, mission-core, mission-crypto, mission-driverd, calamares or custom installer

**Testing Requirements:** Installation workflow tests, partition management, encryption setup, rollback

---

### 3.22 MOS-MOD-022: mission-recovery-env

**Purpose:** Minimal recovery operating environment.

**Type:** System Image (separate from main OS)

**Dependencies:** Minimal Debian base + mission-core + mission-crypto + recovery tools

**Testing Requirements:** Boot tests, recovery operation tests, hardware compatibility

---

### 3.23 MOS-MOD-023: mission-network

**Purpose:** Network management (service + UI).

**Type:** Mixed (User Service + Application)

**Dependencies:** mission-ui, mission-core, NetworkManager

**Components:**
- `mission-networkd` (user service) — D-Bus: `org.mission.Network1`
- Network Manager application

**Testing Requirements:** Connection management, VPN tests, captive portal detection

---

### 3.24 MOS-MOD-024: mission-accessibility

**Purpose:** Accessibility services.

**Type:** Mixed (User Service + Application)

**Dependencies:** mission-ui, mission-core, at-spi2, speech-dispatcher, orca

**Components:**
- `mission-accessibilityd` (user service) — D-Bus: `org.mission.Accessibility1`
- Accessibility Settings application

**Testing Requirements:** Screen reader tests, keyboard navigation, high contrast validation

---

### 3.25 MOS-MOD-025: mission-workspaces

**Purpose:** Virtual desktop and workspace management.

**Type:** User Service

**Dependencies:** mission-core, mission-sessiond, KWin scripting API

**Public Interface:** D-Bus: `org.mission.Workspace1`

**Testing Requirements:** Workspace persistence, multi-monitor workspace tests

---

## 4. Dependency Graph (Simplified)

```
mission-core (no dependencies)
    ↓
mission-crypto (depends on mission-core)
    ↓
mission-securityd (depends on mission-core, mission-crypto)
    ↓
    ├── mission-privileged (depends on mission-core)
    ├── mission-updated (depends on mission-core, mission-crypto)
    ├── mission-driverd (depends on mission-core, mission-crypto)
    └── mission-sessiond (depends on mission-core)

mission-ui (depends on Qt/KF)
    ↓
    ├── mission-hub (depends on mission-ui, mission-core)
    ├── mission-settings (depends on mission-ui, mission-core)
    ├── mission-privacy-center (depends on mission-ui, mission-core)
    ├── mission-security-center (depends on mission-ui, mission-core)
    ├── mission-recovery-center (depends on mission-ui, mission-core)
    ├── mission-diagnostics (depends on mission-ui, mission-core)
    ├── mission-file-manager (depends on mission-ui, mission-core)
    ├── mission-update-manager (depends on mission-ui, mission-core)
    ├── mission-driver-manager (depends on mission-ui, mission-core)
    ├── mission-store (depends on mission-ui, mission-core)
    ├── mission-installer (depends on mission-ui, mission-core)
    ├── mission-network (depends on mission-ui, mission-core)
    └── mission-accessibility (depends on mission-ui, mission-core)
```

---

## 5. Module Lifecycle Rules

1. **No module may be introduced without an entry in this document.**
2. **Module dependencies must not create cycles.**
3. **Shared libraries (mission-core, mission-crypto, mission-ui) must maintain backward compatibility within a major version.**
4. **System services must declare explicit systemd unit dependencies.**
5. **Application modules must not import system service internals.**

---

**End of Document**
