# Technical Debt

## Nightly Release Candidate (RC6 — 2026-07-30)

### Low Severity

1. **CI overlay duplication — RESOLVED at RC6** — `nightly.yml` previously duplicated the overlay deployment logic from `build-nightly.sh Phase 5` (and, worse, dropped the package-lists / custom-GRUB / service-enable phases). The CI `build-iso` job now delegates to `./build/build-nightly.sh --skip-tests`, so there is exactly one source of truth for the overlay. Debt retired; guard against re-introduction in review.

2. **BUILD.md, README documentation drift** — Recently updated for RC6 but may drift again. Should be checked on each Nightly build (see RC6-REPORT.md audit items).

3. **IMPLEMENTATION_STATUS.md previously used "COMPLETE" loosely** — RC6 pass switched to precise states: IMPLEMENTED, CI-VALIDATED, RUNTIME-VALIDATED (boot), CANDIDATE, and pending. Continue using these; never mark a module complete on static evidence alone.

4. **mission-core IPC module is a stub** — `src/libraries/core/src/ipc.rs` contains `// TODO: Actual D-Bus connection via zbus`. This is a non-critical stub since actual D-Bus is handled by individual services.

5. **`desktop/sddm/sddm.conf` and `desktop/plasma/org.mission.plasma.desktop` are never deployed** — Authored but not installed by `build-nightly.sh` or `nightly.yml`. Either wire them into the overlay or delete them; docs currently overstate their presence in the ISO.

6. **`src/services/securityd/data/` duplicates `deploy/` with drift** — `data/org.mission.Security.conf` / `data/org.mission.security.policy` differ from `deploy/` and are unused by any build path. Reconcile or remove; `deploy/` is authoritative.

7. **KNOWN_ISSUES.md was previously empty** — Now populated, but may need ongoing maintenance.

### Medium Severity

8. **PolKit integration not complete in securityd** — `src/services/securityd/src/authz.rs:196` needs PolKit backend integration. driverd already has this (`PolKitAuthorizer`). securityd fails closed (denies privileged actions) unless `MISSION_ALLOW_UNAUTHORIZED` is set.

9. **No AppArmor/SELinux profile** — The security architecture defines MAC as a layer, but no implementation exists. This is a Beta blocker.

10. **mission-ui lacks tests and runtime validation** — Design tokens + base QML components exist (CANDIDATE), but zero tests and no desktop-session validation. Do not mark IMPLEMENTED; first step is a smoke test in a live Plasma session.

### New (RC6 audit)

11. **`build/` gitignore footgun** — Fixed at RC6 (blanket `build/` ignore replaced with negation rules). Future generated output must be added as explicit ignore lines under `build/`, never a blanket `build/` re-ignore, or the tracked scripts silently drop out of git.

12. **Nightly ISO + evidence are host-bound** — `validate-iso.sh` / `qemu-boot-test.sh` require Linux + QEMU/OVMF; RC6 evidence lives on the Linux build host, not on a Windows checkout. Consider a CI job that runs both QEMU modes (BIOS + UEFI) so evidence is reproducible from the repo.

---

**Last Updated:** August 1, 2026 (RC6 convergence)
