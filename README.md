<p align="center">
  <img src="https://github.com/p4inz-code/mission-os/blob/main/assets/banner.png?raw=true" alt="Mission OS Banner" width="100%">
</p>

# Mission OS

> A privacy-first, security-focused Linux operating system built on Debian Stable.

![License](https://img.shields.io/badge/License-GPL--3.0-blue.svg)
![Platform](https://img.shields.io/badge/Platform-Linux-success.svg)
![Base](https://img.shields.io/badge/Base-Debian%20Stable-red.svg)
![Desktop](https://img.shields.io/badge/Desktop-KDE%20Plasma-1f6feb.svg)
![Status](https://img.shields.io/badge/Status-Release%20Candidate-orange.svg)

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

## Project Status

**Current status: Release Candidate (RC6) — CANDIDATE for the planned UI/design sprint.**

The RC6 milestone is complete and validated, with all release gates GREEN:

- **Static validation:** formatting, clippy, workspace tests (**622 passing**), and `cargo audit` all pass.
- **Runtime validation:** ISO structure (15/15 checks), QEMU BIOS boot (4/4), and QEMU UEFI/OVMF boot (4/4) pass on a Linux build host.
- **Reference artifact:** the nightly ISO `0.1.0-nightly.20260730` is the validated release artifact.

Implemented so far:

- Shared libraries: mission-core, mission-crypto
- Core services: mission-securityd, mission-driverd (boot-level runtime-validated)
- KDE Plasma integration, installer, and ISO build pipeline

The project is **not yet a Beta release**. The next major phase is the planned **full UI/UX design and implementation sprint**, after which Beta preparation (Calamares install flow, installed-system boot, desktop session validation) begins.

---

## Roadmap

- ✅ RC6 (Release Candidate) — release gates GREEN, validated
- ⏳ UI/UX design & implementation sprint (next planned phase)
- ⏳ Beta preparation (installer flow, installed-boot, desktop session validation)
- ⏳ Public Beta
- ⏳ Version 1.0

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
