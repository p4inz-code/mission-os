# Supported Hardware

> **Status:** Open Beta (2026-08-09). The beta ISO has been statically validated and
> boot-tested in QEMU (BIOS + UEFI) but **not** on real hardware. Hardware compatibility
> may vary; the open beta exists to map the real-hardware matrix. See
> `docs/development/BETA_RELEASE_REPORT.md`.

## Architecture

- x86_64 (Primary)
- 32-bit is not supported

Future consideration

- ARM64

---

## Boot

- UEFI (Primary) — ISO ships an appended EFI partition with `EFI/BOOT/BOOTX64.EFI`
- BIOS (GRUB2 — supported, validated alongside UEFI)

---

## Storage

- USB 3.0+
- SATA SSD
- NVMe SSD
- ≥ 20 GB free for installation

---

## USB drive (installer media)

- **Recommended: 14 GB or larger**
- **Minimum: 8 GB** — the beta ISO is 1.74 GiB, so an 8 GB drive works with headroom

---

## Memory

Minimum

- 8 GB RAM

Recommended

- 16 GB RAM

---

## CPU

Minimum

- Modern 64-bit x86-64 processor

Recommended

- 4+ physical cores

---

## GPU

Supported

- Intel
- AMD
- NVIDIA (open drivers)

---

## Network

- Ethernet / Wi-Fi / Bluetooth supported where drivers exist
- **Not required** — live session and offline installation work with no network;
  Mission OS packages are carried on the installation media

---

## Unsupported

- 32-bit processors
- End-of-life hardware
- Unsupported proprietary drivers
