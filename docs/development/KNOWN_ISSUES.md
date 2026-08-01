# Known Issues

## Nightly Release Candidate (RC6 — 2026-07-30)

### Build / ISO

1. **UEFI/BIOS boot runtime-validated, but re-verification requires Linux** — RC6 closed both gates (QEMU UEFI/OVMF 4/4 PASS, QEMU BIOS 4/4 PASS) on a Linux build host. Re-running them still requires Linux/WSL with QEMU + ovmf; a Windows host cannot reproduce them.

2. **Calamares installer flow not runtime-validated** — The ISO boots to the login prompt, but the install flow itself (partitioning → users → mission-os module → bootloader) has never been executed. This is a Beta blocker.

3. **cargo-audit requires Cargo.lock in CI** — CI runs `cargo audit --deny warnings` (installed via `cargo install`), and `Cargo.lock` is now tracked (RC6 fix) so the audit job works on a fresh clone. Without the lockfile the audit job fails; do not re-ignore it.

4. **Build overlay duplication — RESOLVED at RC6** — `nightly.yml` previously duplicated the overlay setup from `build-nightly.sh` (and silently dropped the package-lists, custom GRUB config, and service-enablement phases). The CI `build-iso` job now delegates to `./build/build-nightly.sh --skip-tests`, so local and CI ISO builds are identical by construction. Keep it that way — never reintroduce inline overlay steps.

### Rust / Testing

5. **Windows file locking during tests** — `cargo test` can fail on Windows with `LNK1104: cannot open file` due to file locking. Not reproduced in the RC6 static re-validation (2026-08-01, all green), but remains a Windows-only risk; Linux/WSL tests pass cleanly.

6. **PolKit integration TODO in securityd** — `src/services/securityd/src/authz.rs:196` has a `// TODO: Integrate with PolKit via zbus/polkit-rs`. The authorizer fails closed (denies privileged actions) unless `MISSION_ALLOW_UNAUTHORIZED` is set. driverd has proper PolKit integration.

### Desktop / UI

7. **SDDM theme uses Breeze default** — No Mission OS-branded SDDM theme exists yet. Uses KDE's default Breeze theme.

8. **No custom icon theme** — Uses `breeze-dark` icons. A Mission OS icon theme has not been designed.

9. **No custom GRUB theme** — Boot menu uses default GRUB appearance.

10. **Wallpaper SVG requires verification** — The wallpaper SVG file exists but has not been visually verified to match design specifications.

11. **mission-ui is CANDIDATE, not complete** — Design tokens and base QML components exist (Colors, Typography, Spacing, Radii, Elevation, Motion, MissionTheme, MissionWindow, MissionPage, SmokeTest + Qt6/CMake build), but the module has zero tests and has not been runtime-validated in a desktop session. Do not mark it IMPLEMENTED.

### Consistency / Repo Hygiene (found in RC6 audit)

12. **`.gitignore` previously hid `build/` scripts** — The blanket `build/` pattern ignored the entire directory, including `build-nightly.sh`, `validate-iso.sh`, `qemu-boot-test.sh`, `nightly-version.sh`, `patch-live-build-grub2.sh`, and `live-build/auto/config` — all of which CI and BUILD.md depend on. Fixed at RC6 with negation rules; keep generated content (`build/images/`, live-build chroot/config, logs) ignored while scripts stay trackable.

13. **`desktop/sddm/sddm.conf` and `desktop/plasma/org.mission.plasma.desktop` are never deployed** — Neither `build-nightly.sh` nor `nightly.yml` installs them into the overlay. They exist only as source config. Either wire them into the overlay deploy or remove them; currently docs overstate their presence in the ISO.

14. **`src/services/securityd/data/` duplicates `deploy/` with drift** — `data/org.mission.Security.conf` and `data/org.mission.security.policy` differ from the `deploy/` versions and are not referenced by any build path. The `deploy/` copies are authoritative; `data/` should be reconciled or removed.

15. **Quiet-boot serial limitation** — `auto/config` uses `quiet` on the kernel cmdline, so kernel/initramfs lines are NOT visible on the serial console; firmware/GRUB/kernel checks in `qemu-boot-test.sh` are informational. The real serial evidence is systemd milestones + the login prompt. This is a design choice, not a regression.

16. **i386-pc/isohybrid decisions** — `isohybrid` is SYSLINUX-only and cannot process GRUB2 El Torito images; hybrid BIOS+UEFI support is provided by `build-nightly.sh` Phase 9 (xorriso EFI append). GRUB 2.12 requires `-p /boot/grub` (handled by `patch-live-build-grub2.sh`), and the i386-pc module copy prevents `grub rescue>` drops. These are deliberate tradeoffs; see the patch script header.

### Deferred (Tracked, Not Forgotten)

17. **18 of 25 architecture modules not implemented for Stable** — Implemented: MOS-MOD-001 (core), 002 (crypto), 004 (securityd), 006 (driverd). Partial/foundation: 021 (installer/Calamares), 023 (network/NetworkManager). CANDIDATE: 003 (mission-ui). All other modules (18) are deferred to Beta/Stable. See 25-MODULE-AUDIT.md.

18. **All Mission applications deferred** — Hub, Settings, Privacy/Security Centers, File Manager, Store, Workspaces, etc. are deferred to Beta phase.

19. **No update mechanism** — mission-updated (MOS-MOD-005) is deferred. Architecture is defined but no implementation exists.

20. **No recovery environment** — mission-recovery-env (MOS-MOD-022) and mission-recovery-center (MOS-MOD-016) are deferred.

---

**Last Updated:** August 1, 2026 (RC6 convergence)
