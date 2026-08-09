# Supported Hardware

Mission OS is currently an **open beta** (see `docs/development/BETA_RELEASE_REPORT.md`).
The beta ISO has been statically validated and boot-tested in QEMU (BIOS + UEFI), but
**has not been tested on real hardware** — hardware compatibility may vary. If your
hardware differs from the ranges below, it may still work; please test and report.

## Architecture

- x86_64 (64-bit) — required. 32-bit (i386) is **not** supported.

## Boot

- **UEFI** (primary) — the ISO ships an appended EFI partition with
  `EFI/BOOT/BOOTX64.EFI` (verified in the static audit).
- **BIOS/Legacy** — supported via GRUB2 (`grub-pc`); validated in QEMU alongside UEFI.

## CPU

- **Minimum:** any 64-bit x86-64 processor
- **Recommended:** 4+ physical cores

## Memory

- **Minimum:** 8 GB RAM
- **Recommended:** 16 GB RAM

## Storage

- Any SATA/NVMe SSD or HDD with at least **20 GB free** for installation
- USB 3.0+ portable drives are supported (Mission OS is USB-first)

## USB drive for the installer

- **Recommended:** **14 GB or larger**
- **Minimum:** **8 GB** — the beta ISO is 1,867,644,928 bytes (1,781 MiB / 1.74 GiB),
  so an 8 GB drive works with comfortable headroom; 14 GB+ is recommended for testers.

## Graphics

- Intel (open drivers)
- AMD (open drivers)
- NVIDIA (open `nouveau` by default)

## Network

- **Not required.** Live session and installation work fully offline; the Mission OS
  packages are carried on the installation media (local `file://` repository).

## Unsupported

- 32-bit processors
- End-of-life hardware without x86-64 support
- Unsupported proprietary drivers (not shipped)
