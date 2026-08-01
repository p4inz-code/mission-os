# Mission OS Build Architecture

**Document ID:** MOS-ENG-BUILD-001
**Version:** 1.0
**Status:** Draft
**Last Updated:** July 2026

---

## 1. Purpose

This document defines the complete engineering path from source repository to bootable Mission OS image, including build system, ISO generation, CI/CD, and artifact verification.

---

## 2. Build Pipeline Overview

```
Source Repository (GitHub)
    │
    ▼
CI Pipeline (GitHub Actions)
    │
    ├── Lint/Format Check
    ├── Unit Tests
    ├── Build Libraries
    ├── Build Services
    ├── Build Applications
    ├── Integration Tests
    └── Package Creation
    │
    ▼
Package Repositories
    │  .deb packages (Mission OS overlay)
    │
    ▼
Image Generation
    │  live-build + debian-cd + custom scripts
    │
    ├── ISO (Installable + Live)
    │     ├── EFI bootable
    │     ├── BIOS bootable (fallback)
    │     └── Hybrid ISO (USB + DVD)
    │
    ├── Recovery Image
    │     └── Minimal recovery environment
    │
    └── Verification Artifacts
          ├── SHA-256 checksums
          ├── GPG signatures
          └── Build reproducibility report
```

---

## 3. Source Repository Structure

```
mission-os/
├── .github/                    → CI workflows, templates
├── architecture/               → ADRs
├── docs/                       → Documentation
│   ├── core/
│   ├── engineering/            → Engineering architecture docs
│   ├── design/
│   ├── reference/
│   ├── developer/
│   ├── development/
│   └── ...
├── src/                        → Source code
│   ├── libraries/
│   │   ├── core/               → mission-core (Rust/C)
│   │   ├── crypto/             → mission-crypto (Rust)
│   │   └── ui/                 → mission-ui (QML/C++)
│   ├── services/
│   │   ├── securityd/          → mission-securityd (Rust)
│   │   ├── updated/            → mission-updated (Rust)
│   │   ├── driverd/            → mission-driverd (Rust/C)
│   │   ├── privileged/         → mission-privileged (Rust)
│   │   ├── settingsd/          → mission-settingsd (Rust)
│   │   ├── privacyd/           → mission-privacyd (Rust)
│   │   ├── sessiond/           → mission-sessiond (Rust)
│   │   ├── networkd/           → mission-networkd (Rust)
│   │   └── accessibilityd/     → mission-accessibilityd (Rust)
│   ├── applications/
│   │   ├── mission-hub/        → (QML + C++)
│   │   ├── mission-settings/   → (QML + C++)
│   │   ├── mission-privacy-center/
│   │   ├── mission-security-center/
│   │   ├── mission-recovery-center/
│   │   ├── mission-diagnostics/
│   │   ├── mission-file-manager/
│   │   ├── mission-update-manager/
│   │   ├── mission-driver-manager/
│   │   ├── mission-store/
│   │   └── mission-installer/
│   └── tools/
│       ├── mission-iso/        → ISO generation tooling
│       └── mission-recovery/   → Recovery image builder
├── packages/                   → Debian packaging metadata
├── tests/                      → Integration/E2E tests
├── images/                     → ISO build output
├── CMakeLists.txt              → Top-level CMake (C++ components)
├── Cargo.toml                  → Workspace Cargo (Rust components)
└── Makefile                    → Top-level convenience targets
```

---

## 4. Build System

### 4.1 Technology

| Component | Build System | Language |
|-----------|-------------|----------|
| Shared libraries | Cargo (Rust) + CMake (C/C++) | Rust / C / C++ |
| System services | Cargo | Rust |
| UI applications | CMake + QML | QML / C++ / Kirigami |
| Installer | CMake + QML | QML / C++ |
| ISO/Image generation | Custom Python scripts + shell | Python / Bash |
| Packaging | dpkg-deb / debuild | Metadata |

### 4.2 Build Toolchain

Required:
- Rust toolchain (rustc, cargo, clippy, rustfmt)
- C/C++ toolchain (GCC/Clang, CMake, Ninja)
- Qt 6 + KDE Frameworks development headers
- Kirigami development headers
- Python 3.x (for tooling)
- devscripts, debhelper (for Debian packaging)
- live-build, debian-cd (for ISO generation)
- xorriso, mtools, dosfstools (for ISO creation)

### 4.3 Build Targets

| Target | Description |
|--------|-------------|
| `make libs` | Build shared libraries |
| `make services` | Build system services |
| `make apps` | Build user applications |
| `make all` | Build everything (libraries → services → apps) |
| `make iso` | Generate bootable ISO |
| `make recovery` | Generate recovery image |
| `make test` | Run all tests |
| `make check` | Run static analysis |
| `make clean` | Remove build artifacts |

---

## 5. Continuous Integration

### 5.1 GitHub Actions Workflow

```
┌─────────────────────┐
│    PR Opened         │
└──────────┬──────────┘
           ▼
┌─────────────────────┐
│ Code Quality Checks  │
│ - Formatting (cargo  │
│   fmt, clang-format) │
│ - Linting (clippy,   │
│   shellcheck)        │
└──────────┬──────────┘
           ▼
┌─────────────────────┐
│ Unit Tests           │
│ - cargo test         │
│ - ctest (C++)        │
│ - Qt Test (QML)      │
└──────────┬──────────┘
           ▼
┌─────────────────────┐
│ Build Check          │
│ - Compile libraries  │
│ - Compile services   │
│ - Compile apps       │
└──────────┬──────────┘
           ▼
┌─────────────────────┐
│ Integration Tests    │
│ - Service IPC tests  │
│ - D-Bus integration  │
│ - System tests       │
└──────────┬──────────┘
           ▼
┌─────────────────────┐
│ Security Scan        │
│ - Dependency audit   │
│ - SAST (static app   │
│   security testing)  │
└──────────┬──────────┘
           ▼
┌─────────────────────┐
│ Image Build (nightly)│
│ - Generate ISO       │
│ - Verify artifact    │
│ - Store as CI        │
│   artifact           │
└─────────────────────┘
```

### 5.2 CI Triggers

| Event | Workflow |
|-------|----------|
| Pull request (any) | Quality checks + tests + build |
| Push to main branch | Full CI + integration tests |
| Tag release (v*) | Full CI + image build + signing + release |
| Nightly schedule | Full CI + image build (unstable channel) |

### 5.3 Artifact Signing

Release artifacts are signed with Mission OS GPG key:
- ISO: SHA-256 checksum file → GPG signed
- Packages: dpkg-sig with Mission OS key
- Recovery image: GPG signed checksum
- Release notes: GPG signed

---

## 6. ISO Generation

### 6.1 ISO Contents

```
mission-os-<version>-<arch>.iso
├── EFI/
│   └── BOOT/              → EFI bootloader
├── boot/
│   ├── grub/              → GRUB configuration
│   ├── vmlinuz-*          → Linux kernel
│   ├── initrd.img-*       → initramfs
│   └── memtest86+         → Memory tester
├── live/                  → Live filesystem image
│   ├── filesystem.squashfs → Compressed root filesystem
│   └── filesystem.packages → Package manifest
├── pool/                  → Debian packages
├── recovery/              → Recovery image files
├── .disk/                 → ISO metadata
├── md5sum.txt             → MD5 checksums (for verification)
└── README.html            → Getting started guide
```

### 6.2 Image Build Steps

```
1. Bootstrap base system (debootstrap Debian stable)
2. Install Mission OS overlay packages
3. Configure system defaults
4. Build kernel with Mission OS patches
5. Create initramfs with LUKS support
6. Compress root filesystem (squashfs, zstd compression)
7. Install bootloaders (GRUB2 — BIOS + UEFI)
8. Create ISO filesystem (hybrid ISO: USB + DVD)
9. Generate checksums
10. Sign artifacts
11. Verify image boots in VM
```

---

## 7. Development Builds

### 7.1 Developer Environment

For local development:
- Debian testing/unstable or Ubuntu LTS
- Mission OS SDK package (mission-sdk) provides all dependencies
- `make dev-env` command sets up the environment
- `make iso` generates local ISO for testing

### 7.2 Rapid Iteration

For service/application developers:
- Build and test individual components without full ISO build
- `make service-mission-securityd` → builds + installs locally
- `make app-mission-hub` → builds QML application
- Mock services for testing without hardware dependencies

---

## 8. Reproducible Builds

### 8.1 Goals

- Binary reproducible builds for release artifacts
- End-to-end verified build chain
- Build environment containers (Podman/Docker)

### 8.2 Techniques

- Fixed build paths
- Deterministic file ordering
- Stripped timestamps/non-deterministic metadata
- SOURCE_DATE_EPOCH for reproducible timestamps
- Build inside container with pinned dependencies

---

## 9. Release Pipeline

### 9.1 Release Channels

| Channel | Frequency | Verification |
|---------|-----------|-------------|
| Nightly | Daily | CI only |
| Developer | Weekly | CI + smoke test |
| Beta | Per-milestone | Full test suite |
| Release Preview | Per-release | Full test + security audit |
| Stable | Per-release | Full test + security + accessibility |

### 9.2 Release Artifacts

Each release:
- ISO (x86_64)
- ISO checksum file (SHA-256)
- GPG signature file
- Recovery image
- Package repository index
- Release notes
- Changelog

---

## 10. Build Verification

### 10.1 Pre-Release Verification

Before release:
1. Clean build from tagged source
2. All tests pass (unit, integration, E2E)
3. Security scan passes
4. Accessibility tests pass
5. ISO boots in VM with default settings
6. ISO boots in VM with FDE
7. Installation completes successfully
8. Recovery image boots and works

### 10.2 Verification Artifacts

- Build log (anonymized)
- Test results
- Security scan report
- ISO checksums
- VM test results

---

**End of Document**
