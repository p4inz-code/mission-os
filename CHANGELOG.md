# Changelog

All notable changes to Mission OS will be documented in this file.

The format is based on Keep a Changelog.

## [0.1.0-nightly.20260730] — 2026-08-09 (Open Beta)

### Added

- **Official Open Beta release** — public testing begins; see `docs/development/BETA_RELEASE_REPORT.md`.
- Calamares installer pipeline: `mission-os` / `mission-repo` / `mission-cleanup` modules,
  offline local repository (`installer/build-local-repo.sh`), three-phase `settings.conf`
  sequence (`mount → unpackfs → fstab → machineid → users → displaymanager → bootloader →
  mission-repo → packages → mission-cleanup → umount`).
- `mission-cleanup` removes live-session leftovers (Calamares, SDDM autologin, autostart,
  saved Plasma session) from installed systems so first boot lands on a clean login prompt.
- Offline-safe `packages.conf` (`update: false`) — installation requires no network.
- Calamares branding slideshow (`show.qml`) + fixed `branding.desc` (slideshow/images keys).
- Debian packaging for all four crates with `polkitd` (no obsolete `policykit-1`).
- P15/P16 installed-system verification evidence (`build/p15-p16-report.md`).

### Changed

- README, BUILD.md, IMPLEMENTATION_STATUS.md and KNOWN_ISSUES.md updated for the open beta.
- Final beta ISO rebuilt with the installer-cleanup changes (2026-08-09) and statically
  re-validated (structure 15/15, 30-point content manifest, EFI payload, no host-path leaks).

### Fixed

- GRUB EFI boot chain on installed systems (ESP chain file + `/boot/grub/grub.cfg`).
- `default.target` no-op in resume/offline install scripts.
- Duplicate `securityd/data/` files removed (`deploy/` is authoritative).

### Removed

- Obsolete `policykit-1` dependency (replaced by `polkitd`).
- `debian/compat` files (debhelper compat is declared via `rules` / `control`).

## [Unreleased]

### Added

### Changed

### Fixed

### Removed
