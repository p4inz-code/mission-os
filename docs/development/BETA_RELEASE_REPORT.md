# Mission OS — Open Beta Release Report

**Release status:** OFFICIAL OPEN BETA
**Release date:** August 9, 2026
**Prepared by:** the release gate (autonomous pre-tester audit)

---

## Release artifact

| Item | Value |
|------|-------|
| ISO filename | `mission-os-0.1.0-nightly.20260730-amd64.hybrid.iso` |
| ISO size | 1,867,644,928 bytes (1,781 MiB / 1.74 GiB) |
| SHA256 | `a772f14d5e4cd26c12ae54bd4ff7f1f6111618c6a3a9a5e77af133e1b3c0f7ef` |
| Sidecar checksum | `.sha256` sidecar matches the recomputed hash (verified) |
| Repository | `https://github.com/p4inz-code/mission-os` |
| License | GPL-3.0 |
| Identity | Mission OS — created by Atharva Patil (P4inz), Northbyte Studios |

## USB suitability

- **Recommended:** 14 GB or larger USB drive.
- **Minimum:** 8 GB — the ISO is 1.74 GiB, so an 8 GB drive provides ~7.45 GiB usable and
  fits with ~5.7 GiB free. **An 8 GB USB is sufficient.**
- Write the ISO in **image mode** (Rufus → "DD image mode", balenaEtcher, Ventoy, or
  `dd` on Linux). No special setup beyond standard UEFI boot selection.

## Validation performed (actually executed)

| Gate | Result | How |
|------|--------|-----|
| ISO structure (`validate-iso.sh`) | **15/15 PASS** | Full structural audit: ISO 9660, El Torito BIOS + EFI, MBR 0xef partition, kernel/initrd, grub.cfg, hybrid, SHA256 |
| EFI payload (deep) | **PASS** | Appended partition = FAT16 `MISSION_OS` volume containing `EFI/BOOT/BOOTX64.EFI` (PE32+ x86-64) embedding the Debian-style `search --file /boot/grub/grub.cfg` bootstrap chain |
| SHA256 | **PASS** | Recomputed = `a772f14d…` = shipped `.sha256` sidecar |
| Content manifest | **30/30 PASS** | All 3 Mission Calamares modules (`mission-os`, `mission-repo`, `mission-cleanup`) + `module.desc`; all 9 standard configs; `settings.conf` 3-phase sequence; branding (`branding.desc`, `show.qml`, logo); offline repo (`Packages`, `Packages.gz`, `Release`, 4 debs); all 3 services enabled; `display-manager → sddm`; `default.target → graphical` |
| `packages.conf` offline-safety | **PASS** | Effective copy (`/etc/calamares/modules/packages.conf`) = `update: false`; `backend: apt` |
| Host-path / secret scan | **PASS** | Zero matches for developer paths, WSL paths, `Admin`, evidence dirs in deployed content |
| CRLF scan | **PASS** | No CRLF in deployed Python/QML/shell/config files |
| Dependency audit | **PASS** | `Depends: polkitd` (×2), `policykit-1` = 0; Debian 13/Trixie names correct; all debs verified with `dpkg-deb` |
| Git hygiene | **PASS** | `git diff --check` clean; ISO + generated artifacts gitignored |
| Python modules | **PASS** | `py_compile` on all 3 Calamares module `main.py` files |
| YAML configs | **PASS** | `settings.conf`, `packages.conf` parse as valid YAML |
| QEMU UEFI boot (earlier ISO cycle) | **4/4 PASS** (RC6) | Boot to login prompt; the beta ISO is the same boot construction with the EFI append completed |

## Tests NOT performed (must not be claimed)

- **Real physical hardware boot/install** — to be performed by the maintainer on a
  college PC and public PCs. This is the core purpose of the open beta.
- **Calamares graphical install flow end-to-end** — the offline install path is validated
  via the QEMU harness; the GUI flow itself has not been runtime-executed.
- **Functional D-Bus/PolKit interaction** on a running system.
- **Live-ISO desktop session** (login prompt reached in QEMU; full session not exercised).
- Network / audio / display / input / shutdown-reboot cycles on real hardware.

## Known issues (see `docs/development/KNOWN_ISSUES.md`)

- Calamares graphical install flow not runtime-executed (KNOWN_ISSUES #2).
- D-Bus/PolKit functional interaction pending (KNOWN_ISSUES #6, TECH_DEBT #8).
- mission-ui is CANDIDATE — 50 QML components + 40 QtTest suites exist but are not
  runtime-validated in a desktop session; Mission Hub/Diagnostics/Recovery are UI
  surfaces with signal contracts, no host integration (KNOWN_ISSUES #11).
- No AppArmor/SELinux MAC profile (TECH_DEBT #9).
- Default Breeze SDDM/icon/GRUB themes (KNOWN_ISSUES #7–9).
- SDDM theme / icon theme / GRUB theme not custom-branded.
- No update mechanism, no recovery environment (deferred).
- `usr/share/calamares/modules/packages.conf` fallback copy still carries `update: true`
  (cosmetic — Calamares loads `/etc/calamares/modules/packages.conf` first, which is
  `update: false` and effective).

## Hardware testing status

- **QEMU (virtual):** BIOS + UEFI boot validated (RC6, 4/4 each).
- **Real hardware:** NOT YET TESTED. Beta testers (including the college PC) will map the
  hardware matrix. The minimum documented hardware is x86-64, 8 GB RAM, 20 GB disk,
  8 GB+ USB — see `SUPPORTED_HARDWARE.md`.

## Beta warning (must be communicated to testers)

Mission OS is **open beta software**: it has been statically audited and validated in
QEMU, but it has **not** been tested on real hardware. Hardware compatibility may vary,
features may change, and some services are still in development. Do not install over data
you cannot afford to lose, and do not rely on the beta for critical work.

## Tester workflow

```
DOWNLOAD ISO + .sha256
→ VERIFY SHA256 (sha256sum -c …)
→ WRITE ISO TO USB (image mode; 8 GB min, 14 GB+ recommended)
→ BOOT PC FROM USB (UEFI boot menu; GRUB auto-boots live after 10s)
→ TEST LIVE ENVIRONMENT (live user: user / live)
→ OPTIONALLY INSTALL (Install Mission OS icon → Calamares; works offline)
→ REPORT RESULTS (GitHub issue with hardware + what was tested)
```

Full instructions live in the repository README ("Try the Open Beta" section).

## Verdict

**READY FOR REAL-HARDWARE TESTING.** The shipped beta ISO is the intended tester
artifact. Publish the release and proceed with physical-machine testing.
