<p align="center">
  <img src="https://github.com/p4inz-code/mission-os/blob/main/assets/banner.png?raw=true" alt="Mission OS Banner" width="100%">
</p>

# Mission OS

> A privacy-first, security-focused Linux operating system built on Debian Stable.

![License](https://img.shields.io/badge/License-GPL--3.0-blue.svg)
![Platform](https://img.shields.io/badge/Platform-Linux-success.svg)
![Base](https://img.shields.io/badge/Base-Debian%20Stable-red.svg)
![Desktop](https://img.shields.io/badge/Desktop-KDE%20Plasma-1f6feb.svg)
![Status](https://img.shields.io/badge/Status-Open%20Beta-blue.svg)

---

## Overview

Mission OS is an open-source Linux operating system designed around four core principles:

- Privacy by default
- Security by design
- Offline-first reliability
- USB-first portability

Built on Debian Stable and powered by KDE Plasma, Mission OS aims to provide a modern desktop experience that is fast, predictable, and easy to trust.

The project is intended for developers, students, researchers, security professionals, journalists, and anyone who values ownership of their computing environment.

Mission OS is **not** a Windows replacement or a penetration testing distribution. It is a carefully designed desktop operating system focused on everyday usability without compromising privacy or security.

**Mission OS is created by Atharva Patil (P4inz) under Northbyte Studios.**

---

## Highlights

- 🔒 Privacy-first by default
- 🛡️ Security-focused architecture (D-Bus + PolKit + sysctl hardening)
- 💾 USB-first portable operating system
- 🌐 Offline-first experience
- 🎨 KDE Plasma desktop with Mission Graphite design
- ⚡ Rust-based system services (mission-securityd, mission-driverd)
- 🏗️ CI/CD pipeline with automated ISO build + QEMU boot validation
- ❤️ Free and Open Source (GPL-3.0)

---

## Core Principles

### Privacy First

Mission OS minimizes unnecessary data collection, respects user choice, and keeps the user in control. No telemetry, no mandatory data collection.

### Security by Design

Security is considered throughout the system architecture rather than being added afterwards. Layered security: D-Bus fail-closed, PolKit authorization, systemd sandboxing, capability bounding, kernel hardening.

### Offline First

Core functionality should remain available even without an internet connection whenever practical.

### USB First

Mission OS is designed to run reliably from portable storage while also supporting traditional installations.

---

## Built With

| Foundation | Technology |
|------------|------------|
| Base Distribution | Debian Stable |
| Desktop Environment | KDE Plasma (Wayland) |
| System Services | Rust (zbus D-Bus, tokio async) |
| Display Server | Wayland (KDE Wayland session) |
| Audio | PipeWire + WirePlumber |
| Networking | NetworkManager + plasma-nm |
| Installer | Calamares |
| ISO Generation | live-build + xorriso |
| Boot | GRUB2 (BIOS + UEFI) |
| Package Format | Debian (.deb) |
| License | GPL-3.0 |

---

## Planned Features

- Mission Installer
- Mission Hub
- Mission Settings
- Mission Store
- Mission Update
- Privacy Center
- Security Center
- Recovery Center
- Diagnostics
- Driver Manager
- File Manager
- Dark and Light themes
- High-DPI support
- Accessibility-first design
- Modern, consistent desktop experience

---

## Try the Open Beta

**Mission OS is now in OFFICIAL OPEN BETA.** You can download the beta ISO, write it to a USB drive, and test it on any x86-64 PC — no special equipment, no account, no internet required.

### The beta ISO

| Item | Value |
|------|-------|
| Filename | `mission-os-0.1.0-nightly.20260730-amd64.hybrid.iso` |
| Size | 1,867,644,928 bytes (1,781 MiB / 1.74 GiB) |
| SHA256 | `a772f14d5e4cd26c12ae54bd4ff7f1f6111618c6a3a9a5e77af133e1b3c0f7ef` |
| Downloads | The `.iso` plus a matching `.iso.sha256` checksum file |

### Minimum hardware

- **CPU:** 64-bit x86-64 processor
- **RAM:** 8 GB minimum (16 GB recommended)
- **Storage:** 20 GB+ free disk for installation (an internal SSD/NVMe or a USB drive)
- **USB drive:** **14 GB or larger recommended**; **8 GB minimum** (the ISO is 1.74 GiB, so an 8 GB drive works, but 14 GB+ leaves comfortable headroom)
- **Boot:** UEFI (primary) or BIOS — both are supported
- **Graphics:** Intel, AMD, or NVIDIA (open drivers by default)
- **Network:** NOT required — installation works fully offline

### Tester workflow

1. **Download** the ISO and its `.sha256` file.
2. **Verify** the checksum:
   ```bash
   sha256sum -c mission-os-0.1.0-nightly.20260730-amd64.hybrid.iso.sha256
   # or: sha256sum mission-os-0.1.0-nightly.20260730-amd64.hybrid.iso
   # expected: a772f14d5e4cd26c12ae54bd4ff7f1f6111618c6a3a9a5e77af133e1b3c0f7ef
   ```
3. **Write the ISO to USB** (image mode — this erases the USB):
   - **Windows:** [Rufus](https://rufus.ie) → select the ISO → **"DD image mode"** (or use balenaEtcher / Ventoy).
   - **Linux:** `sudo dd if=mission-os-0.1.0-nightly.20260730-amd64.hybrid.iso of=/dev/sdX bs=4M status=progress` (replace `/dev/sdX` with your USB device).
4. **Boot the PC from the USB** — enter the UEFI boot menu (typically F12/F11/F8/ESC) and select the USB drive. GRUB auto-boots the live system after 10 seconds.
5. **Test the live environment** — the KDE Plasma desktop loads automatically (live user: `user` / `live`).
6. **Optionally install** — double-click the **Install Mission OS** desktop icon (Calamares). Installation works **offline**: all Mission OS packages are on the media. Choose **Erase disk** for a simple full-disk install, or manual partitioning if you prefer.
7. **Report results** — open a GitHub issue with your hardware details and what you tested. See [Reporting problems](#reporting-problems).

> ⚠️ **Beta software warning:** This is an **open beta** release. It works on validated QEMU configurations and has been statically audited, but it has **not** been tested on real hardware. Hardware compatibility may vary; features may change; some services are still in development. **Do not install over data you cannot afford to lose, and do not rely on it for critical work.**

---

## Project Status

**Current status: OFFICIAL OPEN BETA — public testing has begun.**

Validated to date (on a Linux/WSL build host with QEMU; evidence in `build/p15-p16-report.md` and `docs/development/IMPLEMENTATION_STATUS.md`):

- **Static validation:** formatting, clippy, workspace tests (**623 `#[test]` functions counted mechanically from source**: core 132, crypto 79, securityd 62, driverd 345, integration 5; execution requires the Linux build host), and `cargo audit` all pass.
- **Live ISO boot:** ISO structure (15/15 checks), QEMU BIOS boot (4/4), QEMU UEFI/OVMF boot (4/4) to the login prompt (RC6).
- **Installed-system boot (P15/P16):** a full offline install (partition → local-repo package install → GRUB bootloader, networking disabled) was executed and the installed system booted: systemd running, mission-first-boot + securityd + driverd active, all 4 Mission packages installed with `polkitd` (no `policykit-1`), desktop session reachable.
- **Offline installation:** validated — the four Mission OS `.deb` packages install from a local `file://` repository staged on the installation media (`installer/build-local-repo.sh`, `mission-repo` + `packages` Calamares modules).
- **Final static audit (2026-08-09):** the shipped beta ISO passed `validate-iso.sh` (15/15), a 30-point content manifest (Calamares modules, branding, slideshow QML, offline repo, services), EFI payload verification (FAT16 `MISSION_OS` volume with `EFI/BOOT/BOOTX64.EFI`), zero host-path leaks, zero CRLF in deployed files, and `packages.conf` is offline-safe (`update: false`). See `docs/development/BETA_RELEASE_REPORT.md`.
- **Reference artifact:** `build/images/mission-os-0.1.0-nightly.20260730-amd64.hybrid.iso` (SHA256 `a772f14d…`) is the shipped beta ISO.

Implemented so far:

- Shared libraries: mission-core, mission-crypto
- Core services: mission-securityd, mission-driverd (boot- and installed-system runtime-validated)
- Installer pipeline: Calamares config + branding + offline repository + first-boot + installed-system cleanup (`mission-cleanup` module)
- KDE Plasma integration (config authored; desktop session smoke-validated on the installed system in P15/P16), ISO build pipeline, CI
- mission-ui: **50 production QML components (+ SmokeTest test artifact) and 40 QtTest suites (82 CTest registrations)** — CANDIDATE (not yet runtime-validated in a live session, no host integration)

**Known limitations of the beta** (see `docs/development/KNOWN_ISSUES.md`):

- The Calamares **graphical** install flow has not been run end-to-end in a VM — the offline install path is validated via the QEMU harness.
- Functional D-Bus/PolKit interaction and the live-ISO desktop session are not runtime-validated; **physical hardware has not been tested** — that is exactly what this beta is for.
- Mission Hub, Diagnostics and Recovery screens are UI surfaces with signal contracts — no host integration exists yet.

---

## Reporting problems

Found a bug, a boot failure, or a hardware incompatibility? Please open a [GitHub issue](https://github.com/p4inz-code/mission-os/issues) and include:

- Your hardware (CPU, RAM, GPU, storage, UEFI or BIOS)
- The exact ISO you used (filename + SHA256)
- What you did (live boot / install / desktop)
- What happened (logs, photos, screenshots welcome)

Security issues: see [`SECURITY.md`](SECURITY.md) and [`SECURITY_CONTACT.md`](SECURITY_CONTACT.md) — do **not** open a public issue for vulnerabilities.

---

## Roadmap

- ✅ RC6 (Release Candidate) — release gates GREEN, validated
- ✅ UI/UX design & implementation sprint (50 production QML components + SmokeTest, 40 QtTest suites)
- ✅ Installed-system boot + offline install validation (P15/P16, 2026-08-09)
- ✅ Pre-hardware repository audit + installer cleanup (2026-08-09)
- ✅ Final beta ISO rebuilt + statically validated (2026-08-09)
- ✅ **Official Open Beta released (2026-08-09)** — public testing
- ⏳ Real-hardware testing across the hardware matrix
- ⏳ Beta hardening + fixes from tester feedback
- ⏳ Version 1.0 (Stable)

---

## Repository Structure

```
mission-os/
├── Cargo.toml              # Rust workspace (4 crates)
├── src/
│   ├── libraries/          # Shared libraries
│   └── services/           # System services
├── build/                  # ISO build scripts + validation
├── installer/              # Calamares config + first-boot
├── desktop/                # KDE Plasma, SDDM, wallpaper
├── packages/               # Debian packaging
├── defaults/               # sysctl hardening, environment
├── docs/                   # Full documentation
├── tests/                  # Integration tests
└── .github/workflows/      # CI/CD (9 jobs)
```

---

## Building & Testing

```bash
# Build Rust components
cargo build --release --workspace

# Run tests
cargo test --workspace

# Build Nightly ISO (Linux only)
./build/build-nightly.sh
```

See [`BUILD.md`](BUILD.md) for detailed build instructions.

---

## Documentation

Project documentation is organized under the `docs/` directory.

Key sections include:

- Vision
- Architecture
- Design
- Engineering
- User Experience
- Product Planning
- Quality Assurance
- Reference Specifications

---

## Contributing

Community contributions are welcome.

Please read:

- CONTRIBUTING.md
- CODE_OF_CONDUCT.md
- STYLE_GUIDE.md

before submitting issues or pull requests.

---

## Security

If you discover a security vulnerability, please report it responsibly.

See:

- SECURITY.md
- SECURITY_CONTACT.md

for reporting instructions.

---

## License

Mission OS is released under the GNU General Public License v3.0.

See the LICENSE file for details.

---

## Acknowledgements

Mission OS builds upon outstanding open-source projects including:

- Debian
- Linux
- KDE Plasma
- Qt
- Wayland
- Rust
- systemd
- Calamares
- PipeWire
- NetworkManager

Their work makes Mission OS possible.

---

Mission OS is developed with an emphasis on long-term maintainability, transparency, accessibility, and engineering quality.
