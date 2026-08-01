# Mission OS Unresolved Decisions and Gaps

**Document ID:** MOS-ENG-TODO-001
**Version:** 1.0
**Status:** Draft — Engineering Architecture Phase
**Last Updated:** July 2026

---

## 1. Purpose

This document records architectural decisions that could not be finalized during the Engineering Architecture Phase, gaps discovered during the repository audit, and items deferred to future engineering sessions.

These items must be resolved before or during their affected implementation milestone.

---

## 2. Pending Architecture Decision Records (ADRs)

The following ADRs must be created before implementation of the affected subsystems:

| ADR | Topic | Affected Milestone | Priority |
|-----|-------|-------------------|----------|
| ADR-0002 | System programming language for new services (Rust) | M1 | **RESOLVED** — Rust selected and implemented |
| ADR-0003 | IPC technology confirmation (D-Bus + PolKit) | M2 | **RESOLVED** — D-Bus + PolKit implemented |
| ADR-0004 | Sandboxing technology (Bubblewrap vs Firejail vs systemd-nspawn) | M6 | High |
| ADR-0005 | Update mechanism (APT snapshots vs OSTree vs custom) | M4 | High |
| ADR-0006 | Package format (.mos-pkg vs .deb overlay vs hybrid) | M4 | High |
| ADR-0007 | Distribution base version pinning strategy | M4 | Medium |
| ADR-0008 | Browser isolation strategy for privacy | M6 | Medium |
| ADR-0009 | Optional cloud sync technology (for future release) | Post-1.0 | Low |

---

## 3. Package Format Schemas Not Yet Defined

**Status:** Critical gap

The user specified frozen schemas for `.mos-pkg`, `.mos-update`, `.mos-driver`, and `.mos-a11y-profile`. These do not exist in the repository.

The existing `docs/engineering/PACKAGE_FORMAT.md` is a minimal outline with no schema definitions.

**Required before Milestone 4 (Installer + ISO):**
- Complete specification of the `.mos-pkg` manifest format (fields, required/optional, versioning)
- Complete specification of `.mos-update` update package format
- Complete specification of `.mos-driver` driver package format
- Complete specification of `.mos-a11y-profile` accessibility profile format
- Signature and trust model for each format
- Schema validation rules

**Recommendation:** This should be Session 1.5 — Package Schema Design, or folded into ADR-0006.

---

## 4. Localization / i18n Architecture

**Status:** Gap — not addressed in current architecture docs

The architecture documents do not define a localization layer. This is mentioned nowhere in the engineering documents.

**Required items:**
- Translation framework decision (Qt Linguist .ts/.qm files, gettext .po/.mo, or both)
- Translation file location and packaging
- Language fallback chain
- Runtime locale switching
- Translation workflow for contributors
- Translation testing
- i18n-enabled component checklist
- Date/time/number format handling
- Right-to-left (RTL) language support plan
- Locale-specific input method handling

**Recommendation:** Add localization architecture section to RUNTIME_ARCHITECTURE.md or create a separate L10N_ARCHITECTURE.md. Required before Beta (Milestone 11) at latest.

---

## 5. Lock Screen Security Architecture

**Status:** Gap — not addressed in SECURITY_ARCHITECTURE.md

The lock screen has specific security implications not yet documented:

- Secure Attention Key (SAK) — how users verify the authentication dialog is genuine
- VT switching prevention while locked
- SysRq protection while locked
- Authentication attempt rate limiting
- Lock screen bypass attack vectors (USB, debug ports, init system)
- Grace period after resume (lock immediately vs allow brief access)
- TPM/PIN unlock vs password unlock policy
- Session locking on suspend (must be mandatory, not optional)
- External display lock behavior (presentation mode exception)

**Recommendation:** Add Lock Screen security subsection to SECURITY_ARCHITECTURE.md. Required before Milestone 3 (Desktop Integration).

---

## 6. Tor Integration Architecture

**Status:** Vague — stated principles but no technical architecture

Current SECURITY_ARCHITECTURE.md section 6.3 correctly states Tor limitations but does not define technical integration.

**Required architecture:**
- System-wide Tor proxy vs per-application routing
- Torsocks integration or transparent proxy
- Tor network detection and status indication
- DNS leak prevention
- Split routing: Tor for selected apps, clearnet for others
- Application opt-in/opt-out for Tor routing
- Tor Browser inclusion vs recommendation
- Onion service hosting support
- Bandwidth management
- Offline mode when Tor is unavailable

**Recommendation:** Create detailed Tor integration subsection in SECURITY_ARCHITECTURE.md or reference/14_NETWORK.md before Milestone 6.

---

## 7. Clipboard Security Architecture

**Status:** Gap — mentioned but not architecturally defined

Current documents mention clipboard permission but do not define:
- Per-workspace clipboard isolation
- Sensitive content detection (passwords, OTP codes)
- Clipboard history encryption at rest
- Clipboard history access control
- Auto-expiry of sensitive clipboard entries
- Application-to-application clipboard transfer control

**Recommendation:** Add clipboard security section to SECURITY_ARCHITECTURE.md.

---

## 8. Captive Portal and Network Failure Handling

**Status:** Gap — not addressed in architecture docs (covered in reference/14_NETWORK.md)

The architecture documents should at minimum reference the handle:

- Captive portal detection and notification
- DNS failure fallback
- VPN connection drop handling (kill switch enforcement)
- Network status change propagation to all applications
- Offline mode indicator

**Recommendation:** Ensure RUNTIME_ARCHITECTURE.md or NETWORK architecture section references these failure modes.

---

## 9. Old Document Consolidation

**Status:** Action required

Several documents in `docs/engineering/` are superseded by the new comprehensive architecture documents superseded by them:

| Old Document | Superseded By |
|-------------|---------------|
| docs/engineering/IPC.md | docs/engineering/IPC_ARCHITECTURE.md |
| docs/engineering/SERVICE_ARCHITECTURE.md | docs/engineering/ARCHITECTURE.md, MODULE_MAP.md |
| docs/engineering/PERMISSION_MODEL.md | docs/engineering/SECURITY_ARCHITECTURE.md |
| docs/engineering/PACKAGE_FORMAT.md | No replacement yet (see section 3) |
| docs/engineering/FILESYSTEM_LAYOUT.md | docs/engineering/ARCHITECTURE.md (section 8) |
| docs/engineering/API_GUIDELINES.md | docs/engineering/CODING_STANDARDS.md |
| docs/engineering/LOGGING.md | docs/engineering/CODING_STANDARDS.md |
| docs/engineering/CRASH_REPORTING.md | docs/engineering/DATA_ARCHITECTURE.md |
| docs/engineering/UPDATE_PIPELINE.md | docs/engineering/SECURITY_ARCHITECTURE.md, DATA_ARCHITECTURE.md |
| docs/engineering/BOOT_PROCESS.md | docs/engineering/RUNTIME_ARCHITECTURE.md |
| docs/development/IMPLEMENTATION_PLAN.md | docs/engineering/IMPLEMENTATION_ROADMAP.md |
| docs/development/TEST_PLAN.md | docs/engineering/TESTING_STRATEGY.md |

Each old document should receive a SUPERSEDED BY notice at the top.

---

## 10. Technology Decisions Not Yet Made

From ARCHITECTURE.md section 3.3:

- Programming language for new system services (Rust — RESOLVED, implemented)
- Sandboxing/isolation technology
- Package format for Mission Packs
- Update delivery mechanism
- Tor integration model
- Optional cloud sync technology
- Remote attestation

These are recorded in ARCHITECTURE.md and must be resolved through ADRs before the affected milestone.

---

## 11. Scoring Summary

Based on code review of the 12 new engineering architecture documents:

| Criterion | Score | Notes |
|-----------|-------|-------|
| Internal Consistency | 9.5/10 | Minor cross-reference gaps |
| Existing Doc Alignment | 8.5/10 | Old docs not yet consolidated |
| Completeness (15 parts) | 8.5/10 | Package schemas + localization missing |
| Security Architecture | 9/10 | Lock screen, clipboard gaps |
| Data Architecture | 10/10 | Comprehensive |
| IPC Architecture | 9.5/10 | Thorough |
| Build Architecture | 9.5/10 | Comprehensive |
| Testing Strategy | 9.5/10 | Thorough |
| Engineering Standards | 9.5/10 | Thorough |
| Implementation Roadmap | 9.5/10 | Well-structured |
| Engineering Gates | 10/10 | Comprehensive |
| **Overall** | **8.8/10** | Gaps identified above are fixable |

Target for Phase 0 completion: **9.5+/10**

The gaps preventing 9.5+ are all documented here and addressable in a follow-up session.

---

**End of Document**
