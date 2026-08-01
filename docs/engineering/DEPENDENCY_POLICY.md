# Mission OS Dependency Policy

**Document ID:** MOS-ENG-DEP-001
**Version:** 1.0
**Status:** Draft
**Last Updated:** July 2026

---

## 1. Purpose

This document defines the rules for managing dependencies in Mission OS.

---

## 2. Dependency Principles

1. **Minimal dependencies.** Every dependency must justify its inclusion.
2. **Trusted sources only.** Dependencies must come from trusted repositories.
3. **Review all new dependencies.** Every new dependency requires explicit approval.
4. **Pin all dependencies.** Builds must be reproducible.
5. **Audit regularly.** Dependencies are scanned for vulnerabilities.
6. **License compatibility.** All dependencies must be license-compatible with GPL-3.0.

---

## 3. Dependency Categories

### 3.1 Base System Dependencies

Dependencies from Debian Stable repositories. These are trusted and do not require additional review beyond what Debian provides.

Examples: glibc, libsystemd, libpam, coreutils, util-linux.

### 3.2 Mission OS Internal Dependencies

Dependencies between Mission OS modules:
- Must follow the module dependency graph defined in MODULE_MAP.md
- Must not create circular dependencies
- Versioned library interface (semantic versioning)

### 3.3 Third-Party Library Dependencies

Libraries not part of Debian Stable:
- Require project-level review before adoption
- Must be actively maintained
- Must have acceptable security track record
- Must be license-compatible
- Must be pinned to specific versions

### 3.4 Build-Time Dependencies

Tools required only during build:
- Documented in BUILD.md
- Included in CI environment
- Version-pinned

### 3.5 Runtime Dependencies

Libraries required at runtime:
- Explicitly declared in package metadata
- Verified during package installation
- Updated through normal update pipeline

---

## 4. Dependency Review Process

### 4.1 New Dependency Checklist

Before adding any new dependency:
- [ ] What problem does this dependency solve?
- [ ] Could we solve this with existing internal code?
- [ ] Is the dependency actively maintained?
- [ ] What is the security track record?
- [ ] What is the license? Is it GPL-3.0 compatible?
- [ ] What is the dependency's own dependency tree?
- [ ] Is the dependency available in Debian Stable?
- [ ] Is there a smaller alternative?
- [ ] Has the source code been reviewed?

### 4.2 Approval Levels

| Dependency Type | Approval Required |
|---------------|-------------------|
| Debian Stable system packages | No additional approval |
| New Rust crate (well-known, maintained) | Engineering team lead |
| New Rust crate (obscure or inactive) | Project maintainer + security review |
| New C/C++ library | Project maintainer + security review |
| New runtime dependency | Project maintainer + review |
| New build dependency | Engineering team lead |

### 4.3 Dependency Addition Workflow

```
Proposal → Review → Approval → Addition to pin file → CI verification
```

---

## 5. Dependency Management

### 5.1 Rust

- `Cargo.toml` specifies version ranges
- `Cargo.lock` committed to repository (for applications)
- Shared libraries use `Cargo.lock` generated at release time
- `cargo-audit` runs in CI

### 5.2 C/C++

- CMake `find_package` for system dependencies
- `.deb` build-dependencies declared in `debian/control`
- Git submodules for internal shared dependencies

### 5.3 QML/JavaScript

- No external JS dependencies
- Built-in QML modules only
- KDE Frameworks integration via CMake

---

## 6. Vulnerability Management

### 6.1 Scanning

- Automated vulnerability scanning in CI
- `cargo-audit` for Rust dependencies
- `trivy` or `grype` for container/OS dependencies
- GitHub Dependabot for dependency update PRs
- `snyk` or equivalent for license compliance

### 6.2 Response to Vulnerabilities

| Severity | Response Time | Action |
|----------|--------------|--------|
| Critical | 48 hours | Emergency patch release |
| High | 1 week | Patch in next release |
| Medium | 1 month | Patch in next release cycle |
| Low | Next release cycle | Triage and plan |

---

## 7. Licensing

All dependencies must be compatible with the Mission OS license (GPL-3.0).

Compatible licenses:
- GPL-2.0, GPL-3.0
- LGPL-2.1, LGPL-3.0
- MIT, BSD-2-Clause, BSD-3-Clause
- Apache-2.0 (with GPL-3.0 compatibility note)
- MPL-2.0
- CC0 (public domain equivalent)

Incompatible licenses (must not be used):
- AGPL-3.0 (network interaction — requires project-level exception)
- Proprietary licenses (must not be used in core components)
- SSPL (MongoDB license — not GPL-compatible)
- Creative Commons Non-Commercial (not open source)

---

## 8. Approved Dependencies (Baseline)

### 8.1 System Libraries (from Debian Stable)
- glibc
- libpam
- libsystemd (sd-journal, sd-bus)
- libcryptsetup (LUKS)
- libnftables
- udev (libudev)
- libpipewire
- libbluetooth
- libpci, libusb

### 8.2 UI Framework
- Qt 6 (qtbase, qtdeclarative, qtsvg, qtwayland)
- KDE Frameworks (kconfig, kcoreaddons, ki18n, kirigami)
- Plasma Framework (plasma-workspace)

### 8.3 Cryptographic
- libsodium (recommended)
- OpenSSL 3.x (for TLS)
- tpm2-tss (TPM)
- LUKS2 (cryptsetup)

### 8.4 Rust Crates (pre-approved)
- serde + serde_json (serialization)
- tokio (async runtime — for services)
- thiserror + anyhow (error handling)
- tracing (structured logging)
- zbus (D-Bus Rust implementation)
- uuid
- sha2, blake3

---

## 9. Forbidden Patterns

1. **No JavaScript/Node.js runtime as a dependency.** Mission OS does not ship Node.js.
2. **No Python as a runtime dependency** for system services (Python is acceptable for tooling).
3. **No untrusted PPAs or external repositories.**
4. **No dependencies that force a non-GPL-compatible license on the project.**
5. **No dependencies with known unpatched CVEs** (waiver required).
6. **No git clones during build** (all dependencies must be cached/pinned).

---

## 10. Code Audit for Dependencies

All third-party dependencies that are:
- Not from Debian Stable
- Not a well-known Rust crate with >1M downloads
- Written in a language not used elsewhere in the project

Must have their source code reviewed before approval.

---

**End of Document**
