# RC6 Release Report — Mission OS Nightly

> **Update (2026-08-09):** This is a point-in-time record of the RC6 cycle. Parts
> are superseded by the P15/P16 phase — installed-system boot, offline install
> and first-boot initialization are now runtime-validated (see
> `build/p15-p16-report.md` and `docs/development/IMPLEMENTATION_STATUS.md`),
> and the offline local-repository wiring described as missing in §1/§5 now
> exists (`mission-repo` / `packages` / `mission-cleanup` modules). The Calamares
> GRAPHICAL install flow, functional D-Bus/PolKit interaction and live-ISO
> desktop session remain unvalidated.

**Date:** August 1, 2026
**Cycle:** RC6 (convergence after the Nightly ISO release)
**Version:** 0.1.0-nightly.20260730
**Status:** Release gates GREEN — **CANDIDATE** for the UI/design sprint, not a Beta release

---

## 1. Release Gate Evidence (RC6 runtime gates — CLOSED GREEN)

Executed on a Linux build host on 2026-07-30. Evidence is host-bound (requires Linux + QEMU/OVMF); a Windows checkout cannot reproduce it without that environment.

| Gate | Result | Detail |
|------|--------|--------|
| `validate-iso.sh` | ✅ **15/15 PASS** | `./build/validate-iso.sh build/images/mission-os-0.1.0-nightly.20260730-amd64.hybrid.iso` — all 15 structural checks, incl. ISO 9660 type, size >500 MB, El Torito BIOS catalog, EFI system area/GPT, hidden El Torito EFI image, /boot, /live, squashfs, vmlinuz, initrd, grub.cfg, hybrid (BIOS+UEFI), SHA-256 |
| QEMU BIOS boot | ✅ **4/4 PASS** | `./build/qemu-boot-test.sh <iso> --bios` — systemd started, basic.target reached, live system detected, login prompt |
| QEMU UEFI/OVMF boot | ✅ **4/4 PASS** | `./build/qemu-boot-test.sh <iso> 180 --ci-mode` — same 4 hard checks under OVMF |
| Boot timeline | ✅ Reached | systemd → basic.target → Mission services → `debian login` prompt |

**Artifact:** `build/images/mission-os-0.1.0-nightly.20260730-amd64.hybrid.iso`

**Limitations of this evidence (do not overstate):**
- Validates ISO structure + boot-to-login on BIOS and UEFI only.
- NOT covered: Calamares install flow, installed-system boot + second boot, functional D-Bus/PolKit interaction, SDDM/Plasma/Wayland desktop session, network, audio/display/input, shutdown/reboot cycle.
- Quiet-boot design: `quiet` on the kernel cmdline suppresses kernel/initramfs lines on serial; firmware/GRUB/kernel checks in `qemu-boot-test.sh` are informational — the real serial evidence is systemd milestones + login prompt.
- i386-pc/isohybrid decisions: `isohybrid` is SYSLINUX-only and cannot process GRUB2 El Torito; hybrid BIOS+UEFI comes from `build-nightly.sh` Phase 9 (xorriso EFI append). GRUB 2.12 requires `-p /boot/grub` (patched), and i386-pc module copy prevents `grub rescue>` drops. Deliberate tradeoffs, not regressions.

---

## 2. Static Validation (re-confirmed 2026-08-01, all PASS)

| Command | Result | Evidence |
|---------|--------|----------|
| `cargo fmt --check` | ✅ PASS | exit 0 |
| `cargo check --all-targets` | ✅ PASS | exit 0, workspace compiled |
| `cargo clippy --all-targets -- -D warnings` | ✅ PASS | exit 0, zero warnings |
| `cargo test --workspace` | ✅ PASS | **622 passed, 0 failed, 4 ignored** (core 131, crypto 79, securityd 62, driverd 345, integration 5) |
| `cargo audit` | ✅ PASS | exit 0 — 201 crate dependencies scanned, 0 vulnerabilities (1177 advisories loaded) |

---

## 3. 25-Module Matrix (RC6)

Source: `docs/development/25-MODULE-AUDIT.md` (synced with MODULE_MAP.md).

| ID | Module | Status | RC | Stable | Evidence |
|----|--------|--------|----|--------|----------|
| 001 | mission-core | ✅ IMPLEMENTED | ✅ | ✅ | 131 tests; in ISO, service reaches boot (RC6) |
| 002 | mission-crypto | ✅ IMPLEMENTED | ✅ | ✅ | 79 tests; in ISO, service reaches boot (RC6) |
| 003 | mission-ui | 🟡 CANDIDATE | ❌ | ✅ | Design tokens + QML base components; 0 tests; no runtime validation |
| 004 | mission-securityd | ✅ IMPLEMENTED | ✅ | ✅ | 62 tests; boot-level runtime-validated (RC6); PolKit TODO at authz.rs:196 |
| 005 | mission-updated | ❌ deferred | ❌ | ✅ | Architecture only — Beta |
| 006 | mission-driverd | ✅ IMPLEMENTED | ✅ | ✅ | 345 tests; boot-level runtime-validated (RC6) |
| 007 | mission-privileged | ❌ deferred | ⚠️ | ✅ | Workaround: direct service PolKit — Beta |
| 008–010 | settingsd / privacyd / sessiond | ❌ deferred | ❌ | ✅ | Beta |
| 011–020 | Store, Hub, Settings, Privacy/Security Centers, Recovery, Diagnostics, File Manager, Update/Driver Managers | ❌ deferred | ❌ | ✅ (018, 025 ⚠️ optional) | Beta / post-Stable |
| 021 | mission-installer | ⚠️ PARTIAL | ✅ | ✅ | Calamares + branding packaged in RC6 ISO; install flow NOT executed |
| 022 | mission-recovery-env | ❌ deferred | ❌ | ✅ | Beta |
| 023 | mission-network | ⚠️ FOUNDATION | ✅ | ✅ | NetworkManager + plasma-nm in package list; custom service Beta |
| 024 | mission-accessibility | ❌ deferred | ❌ | ✅ | KDE baseline; Beta/Stable |
| 025 | mission-workspaces | ❌ deferred | ❌ | ⚠️ | KDE virtual desktops suffice |

**Implement count:** 4 fully implemented (001, 002, 004, 006) + 2 partial/foundation (021, 023) + 1 candidate (003). **18 not implemented.**

---

## 4. 8-Lens Review Scores (derived)

> **Derivation note:** the repository contains no canonical "8-lens" framework as of RC6. Per project decision, these 8 lenses are **derived from the repository's own review artifacts** (docs/qa/UI_CHECKLIST.md, SECURITY_CHECKLIST.md, PERFORMANCE_CHECKLIST.md, docs/developer/ACCESSIBILITY_CHECKLIST.md, docs/engineering/ENGINEERING_GATES.md, docs/qa/RELEASE_CHECKLIST.md, docs/engineering/TESTING_STRATEGY.md, docs/core/PRINCIPLES.md). Scores use the ENGINEERING_GATES model (✅/⚠️/❌) and RC6 evidence. Treat as a derived working artifact, not an approved formal gate.

| Lens | Source artifact | Score | RC6 evidence / rationale |
|------|-----------------|-------|--------------------------|
| 1. Security | SECURITY_CHECKLIST.md | ⚠️ | Fail-closed authz, D-Bus/PolKit policy, systemd sandboxing, sysctl hardening, cargo audit clean; NOT functionally runtime-validated; securityd PolKit TODO; no AppArmor/SELinux |
| 2. Privacy | PRINCIPLES.md, mission-environment/sysctl | ⚠️ | No telemetry, hardened defaults, offline-first; no runtime evidence; privacyd deferred |
| 3. Accessibility | ACCESSIBILITY_CHECKLIST.md | ❌ | No runtime UI to validate; KDE a11y baseline only; mission-ui accessibility wrappers CANDIDATE |
| 4. Performance | PERFORMANCE_CHECKLIST.md | ⚠️ | Boot reaches login in QEMU (2 vCPU/2 GB) — no benchmarks, no target gates met/measured |
| 5. UI/Design consistency | UI_CHECKLIST.md, design tokens | ⚠️ | Design tokens + base QML components exist; no visual/runtime validation; SDDM/GRUB/icon themes missing |
| 6. Architecture & Engineering | ENGINEERING_GATES.md | ⚠️ | 25-module map consistent, deps comply, no unsafe in core, 622 tests green; module audit shows 18/25 deferred; gates not all passable yet |
| 7. Documentation | AUDIT_REPORT.md, doc freeze | ⚠️ | RC6 sync applied (IMPLEMENTATION_STATUS, KNOWN_ISSUES, TECH_DEBT, 25-MODULE-AUDIT, BUILD.md); repo-wide audit performed; remaining drift tracked |
| 8. QA / Testing & Release readiness | RELEASE_CHECKLIST.md, TESTING_STRATEGY.md | ⚠️ | Runtime gates green; static green; installer/desktop/session runtime + hardware matrix pending → not Beta-ready |

**Overall:** ⚠️ Conditional — safe to proceed to the UI/design sprint; NOT sufficient for Beta.

---

## 5. Remaining Blockers (not falsely closed)

1. **Calamares install flow never executed** — install from the RC6 ISO (partition → users → mission-os module → bootloader) is unvalidated. Beta blocker.
2. **Installed-system boot + second boot** — only the live ISO boots have been tested. Beta blocker.
3. **Functional service runtime** — D-Bus methods + PolKit authorization on a live system are not exercised (boot-level only).
4. **Desktop session** — login prompt reached, but SDDM/Plasma/Wayland session and Mission UI have no runtime validation.
5. **mission-ui has zero tests** and is CANDIDATE — prerequisite for the app/UI sprint.
6. **18 of 25 modules deferred** — all Mission applications and user/system services are Beta/Stable scope.
7. **`desktop/sddm/sddm.conf` + `org.mission.plasma.desktop` never deployed** to the overlay (authored but unused) — either wire in or remove.
8. **`src/services/securityd/data/` duplicates `deploy/` with drift** — reconcile or delete.
9. **Repo state: implementation (src/, build/, Cargo.toml, nightly.yml, …) is untracked working-tree content** — must be committed (with the corrected .gitignore + Cargo.lock) before any release can be tagged.
10. **GitHub Actions `codeql.yml` / `docs.yml` are placeholders** — enable before Beta.

---

## 6. RC Verdict

**RC6 release gates: GREEN.** Static validation (5/5) and runtime boot gates (validate-iso 15/15, QEMU BIOS 4/4, QEMU UEFI 4/4) pass.

**Overall verdict: CANDIDATE — approved to proceed to the planned UI/design sprint; NOT a Beta release.**

The RC6 ISO is the reference Nightly artifact. Do not rebuild it without new evidence (no code/CI change in this cycle affects the released ISO; the `.gitignore` and `nightly.yml` fixes affect future builds only).

---

## 7. Exact Next Steps

1. **Commit the repository** — add the implementation with the corrected `.gitignore` (build scripts + Cargo.lock now trackable); verify `git status` shows the scripts tracked; push and confirm CI (`ci.yml` + `nightly.yml`) runs green end-to-end.
2. **Enable `codeql.yml` and `docs.yml`** (currently placeholders) so static analysis and doc jobs are real before Beta.
3. **Run the next Nightly build through the corrected CI pipeline** — the `build-iso` job now delegates to `build-nightly.sh` (parity fixed); confirm the CI ISO passes `validate-iso.sh` and the UEFI QEMU job. (Add a BIOS QEMU job for full parity — tracked in TECH_DEBT.md.)
4. **UI/design sprint (planned next)** — per `docs/design/UI_SPRINT.md` / `design/UI_SPRINT.md` scaffolding:
   - Bring mission-ui from CANDIDATE → implemented: add QML smoke tests, build in CI (cmake job), validate in a live Plasma session.
   - Resolve `desktop/sddm/sddm.conf` + `org.mission.plasma.desktop` deployment question.
   - Complete SDDM theme, icon theme, GRUB theme (currently default Breeze).
5. **Beta preparation** — close the runtime gaps: Calamares install in VM, installed-boot + second boot, D-Bus/PolKit functional tests, desktop session smoke test, then hardware matrix + performance targets per ENGINEERING_GATES / TESTING_STRATEGY §5.3–5.4.

---

## Appendix: Consistency audit summary (this cycle)

| Area | Finding | Disposition |
|------|---------|-------------|
| `.gitignore` | Blanket `build/` ignored the build/validation scripts CI depends on; `Cargo.lock` ignored | **FIXED** (negation rules; lockfile tracked) |
| nightly.yml | `build-iso` duplicated overlay logic and silently dropped package-lists, custom GRUB config, service-enablement | **FIXED** (delegates to `build-nightly.sh --skip-tests`) |
| BUILD.md | "14 checks" stale (now 15); mission-ui "STUB" stale (CANDIDATE) | **FIXED** |
| IMPLEMENTATION_STATUS.md | Runtime gates, mission-ui, service states, gaps list | **SYNCED** with RC6 evidence |
| KNOWN_ISSUES.md | Stale "7 conflicts" ref; overlay duplication noted as open | **SYNCED** (resolved items marked, new items recorded) |
| TECH_DEBT.md | Overlay duplication debt; new findings (sddm.conf, data/ drift, host-bound evidence) | **SYNCED** |
| 25-MODULE-AUDIT.md | mission-ui NOT IMPLEMENTED → CANDIDATE; runtime markers | **SYNCED** |
| 8-lens review | No canonical framework in repo | **DERIVED** from repo checklists (see §4) |

---

**End of Report**
