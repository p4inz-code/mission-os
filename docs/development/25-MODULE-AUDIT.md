# Mission OS — 25-Module Audit

**Date:** August 1, 2026  
**Status:** RC6 — runtime gates GREEN (validate-iso 15/15, QEMU BIOS 4/4, QEMU UEFI 4/4)

---

## Overview

| Status | Count | Modules |
|--------|-------|---------|
| ✅ Implemented (+ boot runtime-validated) | 4 | 001, 002, 004, 006 |
| ⚠️ Partial / Foundation | 2 | 021 (installer/Calamares), 023 (network/NetworkManager) |
| 🟡 CANDIDATE | 1 | 003 (mission-ui) |
| ❌ Not Implemented | 18 | All others |
| **Total** | **25** | Per MODULE_MAP.md |

---

## RC6 Runtime Validation Scope

Modules 001/002/004/006 are present in the RC6 ISO and their services start during the live boot (systemd → basic.target → Mission services → login prompt, QEMU BIOS + UEFI). This is **boot-level** runtime validation. Functional runtime validation (D-Bus method calls, PolKit authorization, desktop session) is still pending for all modules.

---

## Per-Module Status

### MOS-MOD-001: mission-core

| Field | Value |
|-------|-------|
| **Type** | Shared Library |
| **Privilege** | None |
| **Status** | ✅ **IMPLEMENTED** |
| **RC Required** | ✅ Yes (foundation for all services) |
| **Stable Required** | ✅ Yes |
| **Tests** | 131 unit tests |
| **Security Reviewed** | ✅ — no unsafe blocks, fail-closed error handling |
| **Architecture Defined** | ✅ MODULE_MAP.md §3.1 |
| **Dependencies** | None |
| **Blockers** | None |

---

### MOS-MOD-002: mission-crypto

| Field | Value |
|-------|-------|
| **Type** | Shared Library |
| **Privilege** | None |
| **Status** | ✅ **IMPLEMENTED** |
| **RC Required** | ✅ Yes |
| **Stable Required** | ✅ Yes |
| **Tests** | 79 unit tests |
| **Security Reviewed** | ✅ — 16 unsafe blocks (confined to secure_memory) |
| **Architecture Defined** | ✅ MODULE_MAP.md §3.2 |
| **Dependencies** | mission-core |
| **Blockers** | None |

---

### MOS-MOD-003: mission-ui

| Field | Value |
|-------|-------|
| **Type** | Shared Library |
| **Privilege** | None |
| **Status** | 🟡 **CANDIDATE** (not IMPLEMENTED) |
| **RC Required** | ❌ No (applications depend on this, not core OS) |
| **Stable Required** | ✅ Yes (all Mission apps need shared UI components) |
| **Architecture Defined** | ✅ MODULE_MAP.md §3.3 |
| **Dependencies** | Qt 6, KDE Kirigami, KDE Frameworks |
| **Blockers** | No tests; not runtime-validated in a desktop session; needs Qt 6 build verification |
| **Implementation Started** | ✅ Design tokens + QML components exist: Colors, Typography, Spacing, Radii, Elevation, Motion, MissionTheme, MissionWindow, MissionPage, SmokeTest + qmldir + C++ plugin + Qt6/CMake build |
| **Target Milestone** | M5 — Beta |

---

### MOS-MOD-004: mission-securityd

| Field | Value |
|-------|-------|
| **Type** | System Service |
| **Privilege** | System (root) |
| **Status** | ✅ **IMPLEMENTED** |
| **RC Required** | ✅ Yes (core security service) |
| **Stable Required** | ✅ Yes |
| **Tests** | 62 unit tests |
| **Security Reviewed** | ✅ — D-Bus policy, PolKit, systemd sandboxing, no `|| true` bypasses |
| **Architecture Defined** | ✅ MODULE_MAP.md §3.4 |
| **Dependencies** | mission-core, mission-crypto |
| **Blockers** | TODO in authz.rs:196 (PolKit integration via zbus — future enhancement) |
| **Runtime Validated** | ⚠️ Boot-level only (RC6: service start in live boot); functional D-Bus/PolKit interaction pending |

---

### MOS-MOD-005: mission-updated

| Field | Value |
|-------|-------|
| **Type** | System Service |
| **Privilege** | System (root) |
| **Status** | ❌ **NOT IMPLEMENTED** |
| **RC Required** | ❌ No (update mechanism not needed for RC) |
| **Stable Required** | ✅ Yes (system updates essential) |
| **Architecture Defined** | ✅ MODULE_MAP.md §3.5 |
| **Dependencies** | mission-core, mission-crypto, dpkg/APT |
| **Blockers** | Architecture defined, no implementation started |
| **Target Milestone** | M6 — Beta |
| **Risk** | If deferred too long, Stable cannot ship updates |

---

### MOS-MOD-006: mission-driverd

| Field | Value |
|-------|-------|
| **Type** | System Service |
| **Privilege** | System (root) |
| **Status** | ✅ **IMPLEMENTED** |
| **RC Required** | ✅ Yes (hardware detection essential) |
| **Stable Required** | ✅ Yes |
| **Tests** | 345 unit tests |
| **Security Reviewed** | ✅ — D-Bus policy, PolKit, systemd sandboxing, driver verification |
| **Architecture Defined** | ✅ MODULE_MAP.md §3.6 |
| **Dependencies** | mission-core, mission-crypto, udev |
| **Blockers** | None |
| **Runtime Validated** | ⚠️ Boot-level only (RC6: service start in live boot); functional D-Bus/PolKit interaction pending |

---

### MOS-MOD-007: mission-privileged

| Field | Value |
|-------|-------|
| **Type** | System Service |
| **Privilege** | System (root) |
| **Status** | ❌ **NOT IMPLEMENTED** |
| **RC Required** | ⚠️ Partial — PolKit elevation currently handled by direct service interfaces |
| **Stable Required** | ✅ Yes (privilege escalation proxy for apps) |
| **Architecture Defined** | ✅ MODULE_MAP.md §3.7 |
| **Dependencies** | mission-core, PolKit |
| **Blockers** | Depends on mission-securityd architecture for authorization flow |
| **Target Milestone** | M6 — Beta |
| **Current Workaround** | Services implement their own PolKit checks |

---

### MOS-MOD-008: mission-settingsd

| Field | Value |
|-------|-------|
| **Type** | User Service |
| **Privilege** | User |
| **Status** | ❌ **NOT IMPLEMENTED** |
| **RC Required** | ❌ No (KDE settings suffice for RC) |
| **Stable Required** | ✅ Yes (settings persistence for Mission apps) |
| **Architecture Defined** | ✅ MODULE_MAP.md §3.8 |
| **Dependencies** | mission-core |
| **Blockers** | Needs design of settings schema |
| **Target Milestone** | M5 — Beta |

---

### MOS-MOD-009: mission-privacyd

| Field | Value |
|-------|-------|
| **Type** | User Service |
| **Privilege** | User |
| **Status** | ❌ **NOT IMPLEMENTED** |
| **RC Required** | ❌ No (privacy groundwork handled by securityd and sysctl) |
| **Stable Required** | ✅ Yes (permission enforcement, privacy monitoring) |
| **Architecture Defined** | ✅ MODULE_MAP.md §3.9 |
| **Dependencies** | mission-core, mission-securityd (audit log) |
| **Blockers** | Depends on mission-securityd runtime architecture |
| **Target Milestone** | M6 — Beta |

---

### MOS-MOD-010: mission-sessiond

| Field | Value |
|-------|-------|
| **Type** | User Service |
| **Privilege** | User |
| **Status** | ❌ **NOT IMPLEMENTED** |
| **RC Required** | ❌ No (KDE session management sufficient for RC) |
| **Stable Required** | ✅ Yes (session restore, workspace management) |
| **Architecture Defined** | ✅ MODULE_MAP.md §3.10 |
| **Dependencies** | mission-core |
| **Blockers** | Session management architecture needs refinement |
| **Target Milestone** | M6 — Beta |

---

### MOS-MOD-011: mission-store

| Field | Value |
|-------|-------|
| **Type** | Application |
| **Privilege** | User |
| **Status** | ❌ **NOT IMPLEMENTED** |
| **RC Required** | ❌ No |
| **Stable Required** | ✅ Yes (software distribution essential) |
| **Architecture Defined** | ⚠️ Briefly in MODULE_MAP.md §3.11, no detailed spec |
| **Dependencies** | mission-ui, mission-core, mission-updated, mission-settingsd |
| **Blockers** | Depends on mission-ui, mission-updated, mission-settingsd |
| **Target Milestone** | M5 — Stable |

---

### MOS-MOD-012: mission-hub

| Field | Value |
|-------|-------|
| **Type** | Application |
| **Privilege** | User |
| **Status** | ❌ **NOT IMPLEMENTED** |
| **RC Required** | ❌ No (KDE system tray suffices for RC) |
| **Stable Required** | ✅ Yes (central system management dashboard) |
| **Architecture Defined** | ⚠️ Briefly in MODULE_MAP.md §3.12, wireframes exist |
| **Dependencies** | mission-ui, mission-core, mission-settingsd, all service D-Bus interfaces |
| **Blockers** | Depends on mission-ui and multiple services |
| **Target Milestone** | M5 — Beta |

---

### MOS-MOD-013: mission-settings

| Field | Value |
|-------|-------|
| **Type** | Application |
| **Privilege** | User |
| **Status** | ❌ **NOT IMPLEMENTED** |
| **RC Required** | ❌ No (KDE System Settings sufficient) |
| **Stable Required** | ✅ Yes (Mission OS unified settings experience) |
| **Architecture Defined** | ⚠️ Briefly in MODULE_MAP.md §3.13, no detailed spec |
| **Dependencies** | mission-ui, mission-core, mission-settingsd, mission-privacyd, mission-securityd |
| **Blockers** | Depends on mission-ui, all service interfaces |
| **Target Milestone** | M5 — Beta |

---

### MOS-MOD-014: mission-privacy-center

| Field | Value |
|-------|-------|
| **Type** | Application |
| **Privilege** | User |
| **Status** | ❌ **NOT IMPLEMENTED** |
| **RC Required** | ❌ No |
| **Stable Required** | ✅ Yes (privacy management essential) |
| **Architecture Defined** | ⚠️ MODULE_MAP.md §3.14, UX documentation exists |
| **Dependencies** | mission-ui, mission-core, mission-privacyd |
| **Blockers** | Depends on mission-privacyd |
| **Target Milestone** | M6 — Beta |

---

### MOS-MOD-015: mission-security-center

| Field | Value |
|-------|-------|
| **Type** | Application |
| **Privilege** | User |
| **Status** | ❌ **NOT IMPLEMENTED** |
| **RC Required** | ❌ No |
| **Stable Required** | ✅ Yes (security management essential) |
| **Architecture Defined** | ⚠️ MODULE_MAP.md §3.15, UX documentation exists |
| **Dependencies** | mission-ui, mission-core, mission-securityd |
| **Blockers** | Depends on mission-ui |
| **Target Milestone** | M6 — Beta |

---

### MOS-MOD-016: mission-recovery-center

| Field | Value |
|-------|-------|
| **Type** | Application |
| **Privilege** | User |
| **Status** | ❌ **NOT IMPLEMENTED** |
| **RC Required** | ❌ No |
| **Stable Required** | ✅ Yes (recovery management essential) |
| **Architecture Defined** | ⚠️ MODULE_MAP.md §3.16, UX documentation exists |
| **Dependencies** | mission-ui, mission-core, mission-privileged |
| **Blockers** | Depends on mission-privileged |
| **Target Milestone** | M7 — Stable |

---

### MOS-MOD-017: mission-diagnostics

| Field | Value |
|-------|-------|
| **Type** | Application |
| **Privilege** | User |
| **Status** | ❌ **NOT IMPLEMENTED** |
| **RC Required** | ❌ No |
| **Stable Required** | ✅ Yes (health monitoring essential) |
| **Architecture Defined** | ⚠️ MODULE_MAP.md §3.17, UX documentation exists |
| **Dependencies** | mission-ui, mission-core, mission-privileged, udev |
| **Blockers** | Depends on mission-privileged |
| **Target Milestone** | M7 — Stable |

---

### MOS-MOD-018: mission-file-manager

| Field | Value |
|-------|-------|
| **Type** | Application |
| **Privilege** | User |
| **Status** | ❌ **NOT IMPLEMENTED** |
| **RC Required** | ❌ No (Dolphin sufficient for RC) |
| **Stable Required** | ⚠️ Optional — could ship with Dolphin configured |
| **Architecture Defined** | ⚠️ MODULE_MAP.md §3.18, wireframes exist |
| **Dependencies** | mission-ui, mission-core |
| **Blockers** | Low priority, depends on mission-ui |
| **Target Milestone** | M8 — Post-Stable (optional) |

---

### MOS-MOD-019: mission-update-manager

| Field | Value |
|-------|-------|
| **Type** | Application |
| **Privilege** | User |
| **Status** | ❌ **NOT IMPLEMENTED** |
| **RC Required** | ❌ No |
| **Stable Required** | ✅ Yes (update management essential) |
| **Architecture Defined** | ⚠️ MODULE_MAP.md §3.19, UX documentation exists |
| **Dependencies** | mission-ui, mission-core, mission-updated |
| **Blockers** | Depends on mission-updated |
| **Target Milestone** | M8 — Stable |

---

### MOS-MOD-020: mission-driver-manager

| Field | Value |
|-------|-------|
| **Type** | Application |
| **Privilege** | User |
| **Status** | ❌ **NOT IMPLEMENTED** |
| **RC Required** | ❌ No |
| **Stable Required** | ✅ Yes (driver management essential) |
| **Architecture Defined** | ⚠️ MODULE_MAP.md §3.20, wireframes exist |
| **Dependencies** | mission-ui, mission-core, mission-driverd |
| **Blockers** | Depends on mission-ui |
| **Target Milestone** | M8 — Stable |

---

### MOS-MOD-021: mission-installer

| Field | Value |
|-------|-------|
| **Type** | Application (System, temporary) |
| **Privilege** | System (temporary elevation) |
| **Status** | ⚠️ **PARTIALLY IMPLEMENTED** (Calamares + branding) |
| **RC Required** | ✅ Yes (installation essential for RC) |
| **Stable Required** | ✅ Yes |
| **Architecture Defined** | ✅ MODULE_MAP.md §3.21 |
| **Dependencies** | Calamares, mission-ui |
| **Blockers** | Custom installer not yet Architected; Calamares may suffice for RC/Stable |
| **Deferred** | Custom mission-installer application is Stable/post-Stone |
| **Runtime Validated** | ❌ — Calamares config is packaged in the RC6 ISO, but the install flow has never been executed |

---

### MOS-MOD-022: mission-recovery-env

| Field | Value |
|-------|-------|
| **Type** | System Image |
| **Privilege** | System (root) |
| **Status** | ❌ **NOT IMPLEMENTED** |
| **RC Required** | ❌ No |
| **Stable Required** | ✅ Yes (recovery environment essential) |
| **Architecture Defined** | ⚠️ MODULE_MAP.md §3.22, no detailed spec |
| **Dependencies** | Minimal Debian + mission-core + mission-crypto |
| **Blockers** | Significant engineering effort to create separate bootable recovery image |
| **Target Milestone** | M7 — Stable |

---

### MOS-MOD-023: mission-network

| Field | Value |
|-------|-------|
| **Type** | Mixed (Service + Application) |
| **Privilege** | Mixed |
| **Status** | ⚠️ **FOUNDATION ONLY** (NetworkManager configured) |
| **RC Required** | ✅ Yes (networking essential) |
| **Stable Required** | ✅ Yes |
| **Architecture Defined** | ⚠️ MODULE_MAP.md §3.23, no detailed service spec |
| **Dependencies** | mission-ui, mission-core, NetworkManager |
| **Blockers** | NetworkManager provides RC coverage; custom service is Stable |
| **Target Milestone** | M5 — Beta |

---

### MOS-MOD-024: mission-accessibility

| Field | Value |
|-------|-------|
| **Type** | Mixed (Service + Application) |
| **Privilege** | User |
| **Status** | ❌ **NOT IMPLEMENTED** |
| **RC Required** | ❌ No (KDE accessibility features available) |
| **Stable Required** | ✅ Yes (accessibility essential) |
| **Architecture Defined** | ⚠️ MODULE_MAP.md §3.24, no detailed spec |
| **Dependencies** | mission-ui, mission-core, at-spi2, speech-dispatcher, orca |
| **Blockers** | KDE accessibility provides baseline; custom service is Stable |
| **Target Milestone** | M8 — Stable |

---

### MOS-MOD-025: mission-workspaces

| Field | Value |
|-------|-------|
| **Type** | User Service |
| **Privilege** | User |
| **Status** | ❌ **NOT IMPLEMENTED** |
| **RC Required** | ❌ No (KDE virtual desktops sufficient) |
| **Stable Required** | ⚠️ Optional — KDE virtual desktops may suffice |
| **Architecture Defined** | ⚠️ MODULE_MAP.md §3.25, no detailed spec |
| **Dependencies** | mission-core, mission-sessiond, KWin |
| **Blockers** | Depends on mission-sessiond |
| **Target Milestone** | M8 — Post-Stable (optional) |

---

## Summary Table

| ID | Module | Status | RC Required | Stable Required | Target |
|----|--------|--------|-------------|----------------|--------|
| 001 | mission-core | ✅ | ✅ | ✅ | M1 ✅ |
| 002 | mission-crypto | ✅ | ✅ | ✅ | M1 ✅ |
| 003 | mission-ui | 🟡 | ❌ | ✅ | M5 |
| 004 | mission-securityd | ✅ | ✅ | ✅ | M2 ✅ |
| 005 | mission-updated | ❌ | ❌ | ✅ | M6 |
| 006 | mission-driverd | ✅ | ✅ | ✅ | M2 ✅ |
| 007 | mission-privileged | ❌ | ⚠️ | ✅ | M6 |
| 008 | mission-settingsd | ❌ | ❌ | ✅ | M5 |
| 009 | mission-privacyd | ❌ | ❌ | ✅ | M6 |
| 010 | mission-sessiond | ❌ | ❌ | ✅ | M6 |
| 011 | mission-store | ❌ | ❌ | ✅ | M5 |
| 012 | mission-hub | ❌ | ❌ | ✅ | M5 |
| 013 | mission-settings | ❌ | ❌ | ✅ | M5 |
| 014 | mission-privacy-center | ❌ | ❌ | ✅ | M6 |
| 015 | mission-security-center | ❌ | ❌ | ✅ | M6 |
| 016 | mission-recovery-center | ❌ | ❌ | ✅ | M7 |
| 017 | mission-diagnostics | ❌ | ❌ | ✅ | M7 |
| 018 | mission-file-manager | ❌ | ❌ | ⚠️ | M8 |
| 019 | mission-update-manager | ❌ | ❌ | ✅ | M8 |
| 020 | mission-driver-manager | ❌ | ❌ | ✅ | M8 |
| 021 | mission-installer | ⚠️ | ✅ | ✅ | M4 |
| 022 | mission-recovery-env | ❌ | ❌ | ✅ | M7 |
| 023 | mission-network | ⚠️ | ✅ | ✅ | M5 |
| 024 | mission-accessibility | ❌ | ❌ | ✅ | M8 |
| 025 | mission-workspaces | ❌ | ❌ | ⚠️ | M8 |

---

## Critical RC Requirements (Must Be Ready for RC)

| Module | Current Status | Remaining Work |
|--------|---------------|----------------|
| 001 mission-core | ✅ Implemented | Runtime validation |
| 002 mission-crypto | ✅ Implemented | Runtime validation |
| 004 mission-securityd | ✅ Implemented | Runtime validation + PolKit TODO audit |
| 006 mission-driverd | ✅ Implemented | Runtime validation |
| 021 mission-installer | ⚠️ Partial | Calamares runtime validation |
| 023 mission-network | ⚠️ Foundation | NetworkManager coverage validation |

---

## Stable Requirements (Not RC-Blocking)

| Module | Risk Level | Reason |
|--------|-----------|--------|
| 005 mission-updated | HIGH | Stable cannot ship updates without this |
| 007 mission-privileged | MEDIUM | Workaround exists (direct service PolKit) |
| 008-010 mission-session services | MEDIUM | KDE provides fallback |
| 011-020 mission applications | MEDIUM | KDE apps provide fallback |
| 022 mission-recovery-env | HIGH | Stable needs recovery environment |
| 024 mission-accessibility | MEDIUM | KDE accessibility provides baseline |
| 025 mission-workspaces | LOW | KDE virtual desktops suffice |

---

## Modules Deferred to Post-Stable

- MOS-MOD-018 mission-file-manager (optional, KDE Dolphin suffices)
- MOS-MOD-025 mission-workspaces (optional, KDE virtual desktops suffice)

All other deferred modules are required for Stable and have explicit milestones.
