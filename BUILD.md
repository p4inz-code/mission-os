# Building Mission OS

## Quick Start

### Prerequisites

- **Rust toolchain** (rustc, cargo, rustfmt, clippy):
  ```bash
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
  ```

- **Nightly ISO build (Linux only)**:
  ```bash
  # Debian/Ubuntu
  sudo apt install live-build debootstrap xorriso mtools dosfstools \
    squashfs-tools grub-efi-amd64-bin grub-pc-bin grub-common jq \
    syslinux-utils
  # syslinux-utils provides isohybrid, required by live-build to produce
  # a hybrid ISO (BIOS+UEFI bootable from USB).
  ```

### Build Rust Components

```bash
# Build all Rust components
cargo build

# Build specific crates
cargo build -p mission-core
cargo build -p mission-crypto
cargo build -p mission-securityd
cargo build -p mission-driverd
```

### Build Nightly ISO (Linux only)

```bash
# Full Nightly ISO build (builds Rust + generates Debian live ISO)
./build/build-nightly.sh

# Skip tests for faster iteration
./build/build-nightly.sh --skip-tests
```

### Test

```bash
# Run all tests
cargo test --workspace

# Test specific crate
cargo test -p mission-core
cargo test -p mission-crypto
cargo test -p mission-securityd
cargo test -p mission-driverd
```

### Lint

```bash
# Format code
cargo fmt

# Check formatting
cargo fmt --check

# Clippy (lints)
cargo clippy --workspace --all-targets -- -D warnings
```

### Security Audit

```bash
# Install cargo-audit (one-time)
cargo install cargo-audit --locked

# Run dependency vulnerability scan
cargo audit --deny warnings
```

### Validate ISO (Linux only)

```bash
# Run full ISO validation (15 checks including BIOS + UEFI boot structure)
./build/validate-iso.sh <path-to-iso>

# QEMU boot test (UEFI mode)
./build/qemu-boot-test.sh <path-to-iso>

# QEMU boot test (BIOS mode)
./build/qemu-boot-test.sh <path-to-iso> --bios
```

### Clean

```bash
cargo clean
```

---

## Project Structure

```
mission-os/
├── Cargo.toml              # Rust workspace root (4 crates)
├── CMakeLists.txt          # C++ components (mission-ui candidate)
├── Makefile                # Convenience targets
├── VERSION                 # Nightly version: 0.1.0-nightly.20260730
├── rust-toolchain.toml     # Rust stable channel (1.97.1 as of RC6)
├── src/
│   ├── libraries/
│   │   ├── core/           # mission-core — IMPLEMENTED (Rust shared library)
│   │   ├── crypto/         # mission-crypto — IMPLEMENTED (Rust shared library)
│   │   └── ui/             # mission-ui — CANDIDATE (C++/QML design tokens + base components)
│   └── services/
│       ├── securityd/      # mission-securityd — IMPLEMENTED (62 tests)
│       └── driverd/        # mission-driverd — IMPLEMENTED (345 tests)
├── build/
│   ├── build-nightly.sh    # Main ISO build script
│   ├── live-build/         # live-build configuration (auto/config)
│   ├── validate-iso.sh     # ISO validation (15 checks)
│   ├── qemu-boot-test.sh   # QEMU boot test (BIOS + UEFI)
│   ├── nightly-version.sh  # Version metadata generator
│   └── mission-first-boot.service
├── installer/
│   ├── mission-first-boot.sh
│   └── calamares/          # Calamares branding + modules
├── desktop/
│   ├── plasma/             # KDE Plasma configuration
│   ├── sddm/               # SDDM display manager
│   └── wallpaper/          # Mission OS wallpaper
├── packages/               # Debian packaging (all 4 crates)
├── defaults/               # sysctl hardening, environment defaults
├── tests/                  # Integration tests (Rust)
└── .github/workflows/      # CI (lint, test, build, audit, ISO, QEMU)
```

---

## CI/CD

Mission OS uses GitHub Actions for continuous integration.

| Job | What it validates | Fails on |
|-----|-------------------|----------|
| `lint` | `cargo fmt --check`, `cargo clippy -- -D warnings` | Formatting or lint errors |
| `test` | `cargo test --workspace` | Test failures |
| `build` | `cargo check`, `cargo build --release` | Compilation errors |
| `security-audit` | `cargo audit --deny warnings` | Known vulnerable dependencies |
| `validate-packaging` | Debian package structure, deploy files, branding | Missing deployment files |
| `validate-services` | D-Bus names, PolKit actions, binary ELF checks | Missing service artifacts |
| `validate-installer` | Calamares config, first-boot script | Missing installer files |
| `build-iso` | Delegates to `build/build-nightly.sh --skip-tests` (single source of truth: release build, version metadata, lb config, package lists, GRUB config, overlay, service enable, GRUB 2.12 patch, EFI append, checksums) + `validate-iso.sh` | ISO build or validation failure |
| `qemu-boot` | QEMU + OVMF UEFI boot validation | Boot failure |

---

## Current Status

**Phase:** RC6 — runtime gates GREEN (2026-07-30). Static validation re-confirmed 2026-08-01.

**RC6 Gate Evidence:**
- `validate-iso.sh`: **15/15 PASS** on `build/images/mission-os-0.1.0-nightly.20260730-amd64.hybrid.iso`
- QEMU BIOS boot: **4/4 PASS**
- QEMU UEFI/OVMF boot: **4/4 PASS**
- Boot timeline reached: systemd → basic.target → Mission services → login prompt

**Implemented (Nightly):**
| Component | Status | Tests |
|-----------|--------|-------|
| mission-core | IMPLEMENTED (boot runtime-validated RC6) | 131 unit tests |
| mission-crypto | IMPLEMENTED (boot runtime-validated RC6) | 79 unit tests + doc-tests |
| mission-securityd | IMPLEMENTED (boot runtime-validated RC6) | 62 unit tests |
| mission-driverd | IMPLEMENTED (boot runtime-validated RC6) | 345 unit tests + integration |
| mission-ui | CANDIDATE (no tests, no runtime validation) | 0 |
| Debian Packaging | IMPLEMENTED | 4 crates packaged |
| KDE Plasma Integration | IMPLEMENTED (config; desktop session NOT runtime-validated) | Desktop defaults, themes, wallpaper |
| ISO Generation | IMPLEMENTED + runtime-validated (RC6) | live-build + EFI fallback |
| CI Pipeline | IMPLEMENTED + CI-VALIDATED | 9 CI jobs (nightly.yml) |

**Deferred (Beta/Stable):**
- Mission applications (Hub, Settings, Privacy Center, Security Center, etc.)
- User services (mission-settingsd, mission-privacyd, mission-sessiond, etc.)
- System services (mission-updated, mission-privileged)
- Desktop: SDDM theme, icon theme, GRUB theme
- Recovery environment
- Update mechanism
- Accessibility infrastructure

**Remaining RC runtime gaps (Beta blockers):** Calamares install flow, installed-system boot, functional D-Bus/PolKit interaction, SDDM/Plasma/Wayland desktop session, network, audio/display/input, shutdown/reboot cycle. See `docs/development/RC6-REPORT.md`.

---

## License

Mission OS is licensed under GNU General Public License v3.0 (GPL-3.0).
