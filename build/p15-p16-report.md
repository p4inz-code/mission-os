# P15/P16 — Installed-System Boot Verification Report

> **Session update (2026-08-09, pre-hardware audit):** Finding 2 (live-environment
> leftovers) was implemented in the install pipeline: new `mission-cleanup`
> Calamares module (wired into `installer/calamares/settings.conf` and
> `build-nightly.sh` Phase 5/6c) + cleanup sections in `build/offline-install-test.sh`
> and `build/resume-install.sh` (Calamares removal via offline-safe `dpkg`,
> autostart removal, SDDM autologin strip, saved-session removal). The no-op
> `default.target` line in both scripts was also fixed (chroot-relative path +
> loud failure). **Superseded (2026-08-09):** the final ISO was since rebuilt
> (15:22, with the EFI append completed) and statically re-validated — it
> includes `mission-cleanup`, the offline-safe `packages.conf` and the full
> three-phase Calamares sequence; see `docs/development/BETA_RELEASE_REPORT.md`.

Date: 2026-08-09 (WSL Ubuntu build host)
Host: Windows 11 + WSL2 (Ubuntu) + QEMU 10.2.1 + OVMF 4M + KVM

## Artifacts

| Artifact | Location | Note |
|---|---|---|
| Original installed disk (pre-fix) | <build-host>/mission-vm/install-disk.qcow2 | Evidence of pre-fix state |
| Corrected installed disk (verified booting) | <build-host>/mission-vm/install-disk-fixed.qcow2 | Contains both boot-chain fixes |
| Verification evidence | <build-host>/mos-audit-evidence/p15-p16/ | serial logs, OCR transcripts, frames |
| In-VM verify results | <build-host>/mos-audit-evidence/p15-p16/verify-results.txt | 137 lines, machine-readable |

## Boot harness

- `qemu-system-x86_64 -enable-kvm -cpu host -smp 4 -m 4096` (launched via sudo — /dev/kvm is
  root:kvm 660 in this WSL; matches the prior session which also ran QEMU as root).
- UEFI: OVMF_CODE_4M.fd (readonly) + install-vars.fd copy (the existing install session vars).
- `-net none` (loopback-only requirement), serial → file, monitor → unix socket, VNC for screen.

## Finding 1 — The installed disk did NOT boot (GRUB rescue)

First boot of install-disk.qcow2 dropped to the **GRUB rescue shell** (`grub>` prompt,
"GNU GRUB version 2.12-9+deb13u2"). Diagnosis (evidence: serial-rescue-attempt.log,
grub-*.ppm, probe-*.ppm):

- ESP chain file EFI/MISSION_OS/grub.cfg is correct (`search.fs_uuid dd046e13-... root`).
- Root UUID **matches** (blkid root.part: dd046e13-9f39-4665-af18-90beedbcd0c8, LABEL mission_root).
- Kernel + initrd present (/boot/vmlinuz-6.12.94+deb13-amd64, /boot/initrd.img-6.12.94+deb13-amd64).
- **/boot/grub/grub.cfg was MISSING** (`debugfs: File not found by ext2_lookup`) — the resume
  session recorded the intended write in grubcmds.txt but it never executed.
- Additionally, the installed grub EFI binaries carry an embedded prefix of
  **`(hd0,gpt1)/EFI/debian`** (GRUB `set` output), and `EFI/debian/grub.cfg` did not exist —
  so GRUB's automatic config lookup found nothing → rescue.

## Fix applied (minimal, no product code touched)

1. Wrote `/boot/grub/grub.cfg` exactly as grubcmds.txt intended (UUID search, quiet, timeout 5).
2. Wrote the 3-line ESP chain `EFI/debian/grub.cfg` (search fs_uuid → prefix → configfile)
   covering the embedded-prefix mismatch.
3. `install-disk-fixed.qcow2` = qcow2 conversion of the corrected raw disk (verified booting).
4. Pipeline root cause: `build/resume-install.sh` now writes /boot/grub/grub.cfg + both ESP
   chain files so future resumes produce a bootable disk.

## Verification results (from inside the booted fixed system, verify-results.txt)

| Check | Result | Evidence |
|---|---|---|
| GRUB loads normally | PASS (after fix) | automatic boot reaches kernel; serial-final-boot.log has NO "Minimal BASH" rescue banner (grep -c = 0) |
| Linux kernel boots | PASS | `Linux mission-os 6.12.94+deb13-amd64 #1 SMP PREEMPT_DYNAMIC` |
| systemd state | PASS | `systemctl is-system-running` = running (not degraded) |
| mission-first-boot | PASS | state file `/var/lib/mission/first-boot-complete`: version 0.1.0-nightly, first_boot_complete=true, first_boot_date=2026-08-08T17:49:18Z; journal shows full completion; idempotent skip on later boots (ConditionPathExists) |
| mission-securityd | PASS | active (running), enabled; `[securityd] ready on system bus at /org/mission/Security1` |
| mission-driverd | PASS | active (running), enabled; execution engine + cache manager initialized |
| All 4 Mission packages | PASS | ii mission-core-dev/crypto-dev/driverd/securityd 0.1.0-nightly-1 amd64 |
| polkit (fixed dep) | PASS | ii polkitd 126-2 (no policykit-1) |
| fstab | PASS | `UUID=dd046e13-... / ext4 errors=remount-ro 0 1` + `UUID=CC23-84D7 /boot/efi vfat umask=0077 0 1` — both match actual partitions |
| Networking loopback-only | PASS | `ip link` = only `lo`; `ip addr` = only lo; `ip route` = empty (-net none) |
| No FAILED services | PASS | `systemctl --failed` = "0 loaded units listed" |
| Boot journal errors | PASS (minor) | only benign: fd0 floppy probe I/O error (QEMU), obexd evolution registry warnings |
| Display manager | PASS | default.target = graphical.target; sddm active; hostname mission-os |

## Finding 2 — Installed system inherits live-environment leftovers (product issue, NOT fixed here)

The rsync-style install copied the live rootfs, so the INSTALLED system contains:

- Calamares itself (/usr/bin/calamares, calamares-install-debian, /etc/calamares/)
- SDDM **autologin** `/etc/sddm.conf: [Autologin] User=user Session=plasma.desktop`
- autostart `calamares-desktop-icon.desktop`; a Plasma session-restore window ("Install Debian")
  opens on the desktop on first boot (evidence: desktop-ok.ppm, snapnow frames, konsole frames).

Impact: first boot lands on the KDE desktop (via autologin) with the installer window open —
no SDDM login prompt. This should be cleaned up by the installer pipeline (remove calamares +
autostart + autologin + /etc/calamares + saved session). Left for the install-pipeline phase per
the session scope (no installer/product changes were made).

## Root login verification

- Konsole opened via KDE Run dialog (alt-f2); `user@mission-os:~$`; `su -` → `root@mission-os:~#`
  (test-VM root password set during the manual install session; not shipped).
- Desktop is reachable and interactive; terminal works; hostname mission-os.

---

# P15/P16 Follow-up — Regression, FINAL ISO Rebuild & Boot Test (2026-08-09)

## Concise regression check (only packaging control files changed this session)

- `cargo build --release --workspace` — PASS (Finished release profile; mission-securityd +
  mission-driverd binaries present in target/release).
- `cargo test --workspace --lib` — PASS, **62 passed / 0 failed** across all crates.
- Note: first test run hit E0461 (couldn't find `mission_core` for linux-gnu triple) caused by
  stale x86_64-pc-windows-msvc rlibs left in target/debug/deps by an earlier Windows-native
  build of the same checkout. Fixed with `cargo clean -p mission-core -p mission-crypto`; clean
  rebuild passed. Environmental, not a source regression.

## FINAL ISO rebuild (polkitd repo)

- The stale ISO (built 23:06 pre-polkitd-rebuild, sha256 82c37c46…) was preserved as evidence:
  <build-host>/mos-audit-evidence/final-iso/stale-pre-polkitd.iso
- Rebuilt via the existing pipeline, native live-build dir:
  `LIVE_BUILD_DIR=<build-host>/mission-iso2/live-build ./build/build-nightly.sh --skip-tests --skip-repo`
  (repo reused from build/mission-repo which contains the polkitd-fixed debs rebuilt 23:27–23:29).
- Build log: <build-host>/mission-iso2/build-final.log — "Nightly Build Complete".

## Final ISO validation (all PASS)

| Check | Result | Evidence |
|---|---|---|
| ISO rebuilt | PASS | build/images/mission-os-0.1.0-nightly.20260730-amd64.hybrid.iso, Aug 9 05:07 |
| SHA256 shipped = recomputed | PASS | 6a33f644533d065487eb03e4b6838539b78913947118803eb60dcc6b5bcbf413 (differs from stale 82c37c46… — content changed) |
| Repo staged in ISO | PASS | /opt/mission/repo in squashfs contains all 4 mission-*.deb |
| polkitd dep present in ISO repo | PASS | Packages: mission-driverd + mission-securityd both `Depends: … polkitd …`; grep polkitd = 2, policykit-1 = 0 |
| First-boot + services in ISO | PASS | mission-first-boot.sh, mission-first-boot.service, multi-user.target.wants for all 3 services |
| QEMU UEFI boot test | PASS | `sudo ./build/qemu-boot-test.sh <iso> 300` → 4 checks passed / 0 failed; serial shows sysinit.target reached + `debian login:` prompt |

Boot-test evidence: build/images/qemu-UEFI-serial.log (17 KB, Aug 9 05:14), qemu-UEFI.out.
Squashfs evidence: <build-host>/mos-audit-evidence/final-iso/filesystem.squashfs.

## Remaining work (handoff)

1. Installer cleanup so installed systems do NOT inherit live leftovers (Calamares + SDDM autologin
   + calamares autostart + Plasma session restore) — see Finding 2 above.
2. Documentation rewrite / audit phase and physical-hardware testing (out of session scope).
3. No commit/push made — repo left with uncommitted working-tree changes (including the polkitd
   control-file fix and the resume-install.sh boot-chain fix).

## Known issues flagged by code review (audit phase)

- resume-install.sh pins KERNEL/INITRD to `6.12.94+deb13-amd64` (now with a loud existence check
  that aborts rather than writing an unbootable grub.cfg). A future kernel bump must update these
  variables.
- Pre-existing (out of diff): `chroot /mnt ln -sf ... /mnt/etc/systemd/system/default.target`
  resolves to `<target>/mnt/etc/...` inside the chroot and silently no-ops (`|| true`). The
  installed system currently gets graphical.target from the live overlay rsync; the resume path
  itself never sets it. Worth fixing when the install pipeline is refactored.
