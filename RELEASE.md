# Release Process

This document describes how Mission OS releases are planned and published.

> **Current release: OPEN BETA (2026-08-09)** — `mission-os-0.1.0-nightly.20260730-amd64.hybrid.iso`,
> SHA256 `a772f14d5e4cd26c12ae54bd4ff7f1f6111618c6a3a9a5e77af133e1b3c0f7ef`. See
> `docs/development/BETA_RELEASE_REPORT.md` for the full release report and tester workflow.

---

# Release Philosophy

Mission OS follows a quality-first release strategy.

Features are released when they are ready—not according to fixed deadlines.

Stability, security, documentation, and maintainability always take priority over release frequency.

---

# Release Stages

## Development

Active implementation and internal testing.

Features may change without notice.

---

## Alpha

Internal preview builds used for early validation.

Not recommended for production use.

---

## Beta

Public testing begins.

The focus shifts toward stability, bug fixing, accessibility, performance, and community feedback.

---

## Stable

Production-ready releases intended for everyday use.

Stable releases receive maintenance updates, bug fixes, and security improvements.

---

# Release Checklist

Before publishing a release:

- Documentation updated
- Tests passing
- Security review completed
- Accessibility review completed
- Known issues documented
- Changelog updated
- Version number updated

---

# Versioning

Mission OS follows Semantic Versioning where practical.

Examples:

- 0.1.0
- 0.5.0-beta
- 1.0.0

Development builds may include additional identifiers.

---

# Distribution

Official releases will be published through the project's GitHub Releases page.

Checksums and verification instructions will accompany every release.

---

# Support

Supported versions are listed in `SUPPORTED_VERSIONS.md`.

Older releases may receive limited or no updates depending on project resources.