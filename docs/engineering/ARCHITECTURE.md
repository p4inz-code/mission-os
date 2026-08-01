# Mission OS Engineering Architecture

**Document ID:** MOS-ENG-ARCH-001
**Version:** 1.0
**Status:** Draft — Engineering Architecture Phase
**Last Updated:** July 2026

---

## 1. Purpose

This document defines the complete engineering architecture of Mission OS.

It establishes the system-level architectural decisions, layer boundaries, dependency rules, runtime model, and integration patterns that every implementation must follow.

---

## 2. Architectural Principles

### 2.1 Layer Isolation

Each layer depends only on the layer directly beneath it. No layer may bypass its immediate lower layer.

```
User Workspace
    ↓
Mission Applications
    ↓
Desktop Environment
    ↓
System Services
    ↓
Security/Privacy Layer
    ↓
Core OS (Debian Base)
    ↓
Linux Kernel
    ↓
Hardware
```

### 2.2 Service Modularity

Every system capability is a discrete service. Services communicate exclusively through defined IPC channels. No service may import another service's internal state.

### 2.3 Least Privilege

Every process runs with the minimum permissions required. Privilege elevation is explicit, audited, and temporary. No GUI application runs as root.

### 2.4 Defense in Depth

Security relies on multiple independent layers. Failure of any single protection mechanism must not compromise the entire system.

### 2.5 Recovery-First Design

Every destructive or state-changing operation must support rollback. The system must always prefer recovery over reinstallation.

### 2.6 Offline-First

Core functionality must never require network access. Network-dependent features degrade gracefully when offline.

---

## 3. System Architecture

### 3.1 High-Level System Layers

```
┌──────────────────────────────────────────────────────┐
│                   User Workspace                      │
│  Sessions, Profiles, Personalization, Portability     │
├──────────────────────────────────────────────────────┤
│               Mission Applications                    │
│  Hub, Settings, Security, Privacy, Recovery, etc.     │
├──────────────────────────────────────────────────────┤
│             Desktop Environment (KDE Plasma)           │
│  Shell, WM, Compositor, Panel, Launcher, Notifications│
├──────────────────────────────────────────────────────┤
│                System Services Layer                   │
│  Update, Driver, Network, Diagnostic, IPC, Session    │
├──────────────────────────────────────────────────────┤
│             Security/Privacy Services Layer            │
│  Auth, Firewall, Encryption, Sandbox, Audit, Tor      │
├──────────────────────────────────────────────────────┤
│              Core Operating System (Debian)            │
│  Base Packages, Libraries, Init, Boot, Filesystem     │
├──────────────────────────────────────────────────────┤
│                  Linux Kernel                          │
│  Drivers, Security Modules, Namespaces, Cgroups       │
├──────────────────────────────────────────────────────┤
│                     Hardware                           │
│  CPU, RAM, Storage, GPU, Network, TPM, USB, etc.      │
└──────────────────────────────────────────────────────┘
```

### 3.2 Confirmed Technology Stack

| Layer | Technology | Status |
|-------|-----------|--------|
| Distribution Base | Debian Stable | Decided |
| Desktop Environment | KDE Plasma with Wayland | Decided |
| Linux Kernel | Mainline + Mission OS hardening | Decided |
| Boot System | GRUB2 (BIOS + UEFI) | **IMPLEMENTED** |
| Init System | systemd | **IMPLEMENTED** |
| Package Management | dpkg/APT base + Mission OS overlay | **IMPLEMENTED** |
| Display Server | Wayland (KDE Wayland session) | **IMPLEMENTED** |
| Audio | PipeWire | **IMPLEMENTED** |
| Networking | NetworkManager | **IMPLEMENTED** |
| Firewall | nftables backend (mission-securityd) | **IMPLEMENTED** |
| VPN | WireGuard, OpenVPN, IKEv2 (planned) | Deferred to Beta |
| DNS | systemd-resolved + stubby (DoT/DoH) (planned) | Deferred to Beta |
| Encryption | LUKS2 + systemd-homed (optional) | Deferred to Beta |
| TPM | systemd-cryptenroll, tpm2-tools (planned) | Deferred to Beta |
| Sandboxing | Bubblewrap / Firejail / systemd-nspawn | Undecided — Beta |
| Language (System) | Rust (new services) | **IMPLEMENTED** |
| Language (UI) | QML/Kirigami (native KDE) | Design phase |
| Build System | Cargo (Rust) + CMake (C++) | **IMPLEMENTED** |
| ISO Generation | live-build + custom scripts | **IMPLEMENTED** |
| Testing | cargo test (Rust) | **IMPLEMENTED** (622 tests) |
| CI/CD | GitHub Actions (9 jobs) | **IMPLEMENTED** |
| Code Analysis | clippy, rustfmt | **IMPLEMENTED** |
| Container Runtime | Podman (future) | Proposed |

### 3.3 Decisions Made Since Initial Architecture Draft

The following decisions from the initial draft have been resolved:

- **Rust** — Selected as system services language. Implemented in mission-securityd, mission-driverd. RESOLVED.
- **D-Bus + PolKit** — Confirmed as IPC technology. Implemented in both services. RESOLVED.
- **GRUB2** — Selected as bootloader for both BIOS and UEFI. RESOLVED.
- **live-build** — Selected for ISO generation with custom overlay. RESOLVED.

The following remain under consideration and require explicit ADR before implementation:

- Sandboxing/isolation technology (Bubblewrap vs Firejail vs nspawn)
- Package format for Mission Packs (.mos-pkg schema vs existing Debian format)
- Update delivery mechanism (OSTree vs APT snapshots vs custom)
- Tor integration model (system-wide vs per-application)
- Optional cloud sync technology
- Remote attestation

---

## 4. Dependency Rules

### 4.1 Dependency Direction

```
User Interface Layer
    ↓ depends on
Application Logic Layer
    ↓ depends on
Service Layer
    ↓ depends on
System Layer
    ↓ depends on
Kernel Layer
```

### 4.2 Explicit Rules

1. **UI components must never import kernel headers or syscall directly.**
2. **Application logic must never bypass the service layer to access hardware.**
3. **Services must never depend on GUI toolkit libraries.**
4. **Shared libraries (libmission*) must have no circular dependencies.**
5. **System services may only depend on:**
   - libmission-core
   - libmission-crypto
   - Linux standard libraries (glibc, libsystemd, etc.)
6. **Applications may only depend on:**
   - libmission-core
   - libmission-ui
   - Desktop environment libraries (Qt, KDE Frameworks)
   - Application-specific dependencies (explicitly approved)

### 4.3 Forbidden Dependencies

- No GUI service may import kernel headers.
- No app may import another app's internal modules.
- No service may import HTTP clients unless networking is its explicit responsibility.
- No component may embed hardcoded credentials or secrets.

---

## 5. Process Architecture

### 5.1 Process Model

Mission OS uses a multi-process architecture:

```
PID 1: systemd
├── systemd-journald          (system logging)
├── systemd-logind            (session management)
├── systemd-resolved          (DNS)
├── systemd-timesyncd         (NTP)
├── NetworkManager            (network management)
├── PipeWire                  (audio)
├── mission-securityd         (security policy daemon)
├── mission-updated           (update service)
├── mission-driverd           (driver management)
├── mission-privileged        (privileged operations)
│
├── user@uid session:
│   ├── kwin_wayland          (compositor)
│   ├── plasmashell           (desktop shell)
│   ├── mission-hub           (hub application)
│   ├── mission-settingsd     (settings service)
│   ├── mission-privacyd      (privacy service)
│   └── [user applications]
│
└── systemd-journald          (per-user journal)
```

### 5.2 Privilege Levels

| Level | Process Type | Examples |
|-------|-------------|---------|
| Kernel | Kernel threads | Drivers, modules, LSMs |
| System | systemd services (root) | securityd, updated, driverd |
| Privileged | PolKit-authorized | mission-privileged |
| User | User session (unprivileged) | Mission Hub, Settings |
| Sandboxed | Isolated containers | Mission Store apps |

### 5.3 Privilege Escalation

- All privilege escalation uses PolKit (PolicyKit).
- Elevation requests must include justification string visible to the user.
- Elevation is temporary per-operation, not per-session.
- Elevation events are logged to the audit log.

---

## 6. Architectural Boundaries

### 6.1 System Services (Privileged)

- Run as systemd services (root or dedicated system users)
- Communicate via D-Bus (system bus) with polkit authorization
- Cannot be killed by user processes
- Examples: mission-securityd, mission-updated, mission-driverd

### 6.2 User Services (Unprivileged)

- Run within user session
- Communicate via D-Bus (session bus)
- Can be stopped/restarted by the user
- Examples: mission-settingsd, mission-privacyd

### 6.3 Mission Applications (Unprivileged)

- Run as user processes
- UI toolkit: QML + Kirigami
- Communicate with services via D-Bus
- Never run as root

### 6.4 Recovery Environment

- Separate minimal system
- Runs from recovery partition or USB
- Has direct disk access for repair operations
- UI is minimal, terminal-focused, with guided TUI

---

## 7. Communication Architecture

```
┌──────────────────────────────────┐
│     Mission Application (UI)      │
│         ┌──────────────┐         │
│         │ libmission-ui │         │
│         └──────┬───────┘         │
└────────────────┼──────────────────┘
                 │ D-Bus (session bus)
                 │ Authorization: PolKit
┌────────────────┼──────────────────┐
│  ┌─────────────┴──────────────┐   │
│  │     Service Process         │   │
│  │     ┌──────────────┐        │   │
│  │     │ libmission-core│      │   │
│  │     └──────────────┘        │   │
│  └─────────────────────────────┘   │
└────────────────────────────────────┘
                 │ D-Bus (system bus)
                 │ Authorization: PolKit
┌────────────────────────────────────┐
│     Privileged Service (root)       │
│     ┌──────────────────────┐       │
│     │ libmission-crypto     │       │
│     │ libmission-core       │       │
│     └──────────────────────┘       │
└────────────────────────────────────┘
```

---

## 8. Storage Architecture

### 8.1 Filesystem Layout (from MOS-ENG-004)

Root filesystem (/) follows Debian FHS with Mission OS overlays:

```
/                   → root filesystem
├── /boot/          → kernel, initramfs, bootloader
├── /etc/           → system configuration
│   └── /mission/   → Mission OS configuration
├── /usr/           → system software
│   └── /lib/mission/ → Mission OS shared libraries
├── /var/           → variable data
│   └── /log/       → system logs
├── /recovery/      → recovery partition mount
├── /home/          → user data (may be encrypted)
└── /mission/       → Mission OS system data
    ├── /packages/  → verified package cache
    ├── /snapshots/ → system snapshots
    ├── /updates/   → staged update data
    └── /drivers/   → driver storage
```

### 8.2 Partition Scheme (Recommended)

```
EFI System Partition   → /boot/efi   (512 MB)
Boot Partition         → /boot       (1 GB)
Root Partition         → /           (20+ GB, LUKS2 encrypted)
Home Partition         → /home       (remaining, LUKS2 encrypted)
Recovery Partition     → /recovery   (8+ GB)
```

---

## 9. Reliability Architecture

### 9.1 Failure Domains

Each subsystem is a failure domain. Failure in one domain must not cascade:

- **Desktop shell crash** → Shell restarts, apps continue running
- **Application crash** → Only that application is affected
- **Service crash** → systemd restarts the service
- **Disk full** → All writes return clear ENOSPC errors, no data corruption
- **Power loss** → Filesystem journaling + atomic writes protect integrity
- **Update failure** → Automatic rollback to previous state

### 9.2 Atomic Operations

All system state changes follow this pattern:

1. **Validate** — Verify preconditions
2. **Snapshot** — Save current state
3. **Apply** — Make the change
4. **Verify** — Confirm the change succeeded
5. **Commit** — Mark snapshot as successful
6. **Rollback on Failure** — Restore snapshot if verification fails

### 9.3 Recovery Points

Created automatically before:
- System updates
- Driver installations
- Major configuration changes

Created manually by user request.

---

## 10. Architecture Decisions (ADRs)

The following Architectural Decision Records govern this architecture:

| ADR | Topic | Status |
|-----|-------|--------|
| ADR-0001 | Repository Architecture | **COMPLETED** |
| ADR-0002 | System Programming Language (Rust) | **RESOLVED** — Rust selected and implemented |
| ADR-0003 | IPC Technology (D-Bus + PolKit) | **RESOLVED** — D-Bus + PolKit implemented in services |
| ADR-0004 | Sandboxing Technology | Pending — required before Beta |
| ADR-0005 | Update Mechanism | Pending — required before Beta |
| ADR-0006 | Package Format (.mos-pkg vs .deb) | Pending — required before Beta |

Each pending ADR must be completed before implementation of the affected subsystem begins.

---

## 11. Architecture Compliance

Every implementation must be reviewed against this architecture document.

Violations that cross layer boundaries, create forbidden dependencies, or weaken architectural isolation must be escalated for architectural review before merging.

---

**End of Document**
