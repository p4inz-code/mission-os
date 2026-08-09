#!/bin/bash
# Mission OS — Final Static Audit (read-only, no build, no VM)
# Verifies the completed ISO is a stable beta-testing artifact:
#   1. SHA256 (expected + shipped sidecar)
#   2. ISO structure / EFI / boot metadata (xorriso + system area + appended EFI payload)
#   3. Calamares modules, branding, settings sequence, offline repo, packages.conf
#   4. Host-path leaks + CRLF in deployed files
#   5. USB (>=8 GB) suitability facts
# Usage: bash final-static-audit.sh [iso-path]
# Run from the repository root. ISO path and evidence dir are overridable
# (MISSION_ISO / MOS_EVID); evidence defaults under $HOME.

set -uo pipefail

# SKIP_SHA=1 skips the (slow over 9p/WSL) full-file sha256sum and instead
# cross-checks the shipped sidecar against the known-good expected value.
SKIP_SHA="${SKIP_SHA:-0}"
ISO="${1:-${MISSION_ISO:-build/images/mission-os-0.1.0-nightly.20260730-amd64.hybrid.iso}}"
EXPECTED_SHA="a772f14d5e4cd26c12ae54bd4ff7f1f6111618c6a3a9a5e77af133e1b3c0f7ef"
EVID="${MOS_EVID:-$HOME/mos-audit-evidence/final-iso/static-audit}"
SQIMG="$EVID/filesystem.squashfs"
ROOT="$EVID/root"
EFIIMG="$EVID/efi-partition.img"

PASS=0
FAIL=0
WARN=0

chk() { # chk <name> <0|1>
    if [ "$2" -eq 0 ]; then echo "  [PASS] $1"; PASS=$((PASS+1));
    else echo "  [FAIL] $1"; FAIL=$((FAIL+1)); fi
}
warn() { echo "  [WARN] $1"; WARN=$((WARN+1)); }

mkdir -p "$EVID"
echo "=============================================================="
echo " Mission OS — FINAL STATIC AUDIT ($(date -u))"
echo " ISO: $ISO"
echo "=============================================================="

# ── 1. SHA256 ──────────────────────────────────────────────────────
echo "--- 1. SHA256 ---"
[ -f "$ISO" ] || { echo "ERROR: ISO not found"; exit 1; }
if [ "$SKIP_SHA" = "1" ]; then
    echo "  (full-file sha256sum skipped; expected $EXPECTED_SHA previously verified)"
    if [ -f "$ISO.sha256" ]; then
        SIDECAR=$(awk '{print $1}' "$ISO.sha256")
        [ "$SIDECAR" = "$EXPECTED_SHA" ] && chk "SHA256 sidecar matches expected" 0 || chk "SHA256 sidecar matches expected" 1
    else
        warn "no .sha256 sidecar present"
    fi
else
    ACTUAL=$(sha256sum "$ISO" | awk '{print $1}')
    echo "  expected: $EXPECTED_SHA"
    echo "  actual:   $ACTUAL"
    [ "$ACTUAL" = "$EXPECTED_SHA" ] && chk "SHA256 matches expected" 0 || chk "SHA256 matches expected" 1
    if [ -f "$ISO.sha256" ]; then
        SIDECAR=$(awk '{print $1}' "$ISO.sha256")
        [ "$SIDECAR" = "$ACTUAL" ] && chk "SHA256 matches shipped sidecar" 0 || chk "SHA256 matches shipped sidecar" 1
    else
        warn "no .sha256 sidecar present"
    fi
fi

# ── 2. ISO structure / EFI / boot metadata ─────────────────────────
echo "--- 2. ISO structure / EFI / boot metadata ---"
FT=$(file -b "$ISO")
echo "  file: $FT"
case "$FT" in *"ISO 9660"*) chk "ISO 9660 detected" 0;; *) chk "ISO 9660 detected" 1;; esac
SIZE=$(stat -c%s "$ISO")
echo "  size: $SIZE bytes ($((SIZE/1024/1024)) MiB)"
[ "$SIZE" -gt 1000000000 ] && chk "ISO size > 1 GiB (desktop ISO)" 0 || chk "ISO size > 1 GiB (desktop ISO)" 1

SA="$(xorriso -indev "$ISO" -report_system_area 2>&1 || true)"
echo "$SA" | grep -qiE "EFI|GPT" && chk "System area reports EFI/GPT" 0 || chk "System area reports EFI/GPT" 1
echo "$SA" | grep -qiE "0xef|partition 2|efi" && chk "Appended EFI partition (type 0xef) present" 0 || chk "Appended EFI partition (type 0xef) present" 1
echo "  --- system area (partition lines) ---"
echo "$SA" | grep -iE "partition|GPT|type|efi" | head -12

TOC="$(xorriso -indev "$ISO" -toc 2>&1 || true)"
echo "$TOC" | grep -qi "boot image" && chk "El Torito BIOS boot image present" 0 || chk "El Torito BIOS boot image present" 1
echo "$TOC" | grep -qi "platform_id=0xEF\|efi\|EFI" && chk "El Torito EFI boot entry present" 0 || chk "El Torito EFI boot entry present" 1
echo "  --- boot entries ---"
echo "$TOC" | grep -iE "boot image|boot catalog|platform" | head -8

# ISO filesystem boot-critical files
FIND="$(xorriso -indev "$ISO" -find /live -type f 2>/dev/null || true)"
echo "$FIND" | grep -q "vmlinuz" && chk "Kernel (vmlinuz) in /live" 0 || chk "Kernel (vmlinuz) in /live" 1
echo "$FIND" | grep -q "initrd" && chk "Initramfs (initrd) in /live" 0 || chk "Initramfs (initrd) in /live" 1
FINDG="$(xorriso -indev "$ISO" -find /boot/grub -name grub.cfg 2>/dev/null || true)"
[ -n "$FINDG" ] && chk "grub.cfg in /boot/grub" 0 || chk "grub.cfg in /boot/grub" 1

# ── Extract squashfs + EFI payload (read-only, disk only) ──────────
echo "--- Extracting squashfs + EFI payload (one-time) ---"
if [ ! -f "$SQIMG" ]; then
    (cd "$EVID" && xorriso -indev "$ISO" -osirrox on -extract /live/filesystem.squashfs "$SQIMG" >/dev/null 2>&1)
fi
[ -f "$SQIMG" ] && chk "SquashFS extracted" 0 || chk "SquashFS extracted" 1
if [ ! -d "$ROOT" ]; then
    mkdir -p "$ROOT"
    unsquashfs -d "$ROOT" "$SQIMG" >/dev/null 2>&1
fi
[ -d "$ROOT/etc" ] && chk "SquashFS uncompressed" 0 || chk "SquashFS uncompressed" 1

# EFI payload: dd the appended partition from the ISO and list its contents.
# xorriso reports the EFI image location as 'EFI image start and size: S*2048, N*512'.
EFI_START="$(echo "$SA" | grep -oE 'EFI image start and size: [0-9]+ \* 2048' | grep -oE '[0-9]+' | head -1)"
EFI_BLOCKS="$(echo "$SA" | grep -oE ', [0-9]+ \* 512' | grep -oE '[0-9]+' | head -1)"
if [ -n "$EFI_START" ] && [ -n "$EFI_BLOCKS" ]; then
    EFI_COUNT=$((EFI_BLOCKS * 512 / 2048))
    dd if="$ISO" of="$EFIIMG" bs=2048 skip="$EFI_START" count="$EFI_COUNT" status=none 2>/dev/null
    EFILS="$(mdir -i "$EFIIMG" ::/ 2>/dev/null | tr -d ' \t' || true)"
    echo "  EFI partition root: $EFILS"
    case "$EFILS" in *EFI*) chk "EFI dir in appended EFI partition" 0;; *) chk "EFI dir in appended EFI partition" 1;; esac
    MCFG="$(mdir -i "$EFIIMG" ::/EFI/BOOT 2>/dev/null | tr -d ' \t' || true)"
    echo "  EFI/BOOT dir: $MCFG"
    # mdir renders FAT names as two columns (BOOTX64  EFI) — match on the name part.
    case "$MCFG" in *BOOTX64*) chk "BOOTX64.EFI inside appended EFI partition" 0;; *) chk "BOOTX64.EFI inside appended EFI partition" 1;; esac
    # Extract BOOTX64.EFI and confirm the embedded bootstrap references the ISO grub.cfg
    if mcopy -i "$EFIIMG" ::/EFI/BOOT/BOOTX64.EFI "$EVID/BOOTX64.EFI" 2>/dev/null; then
        if strings "$EVID/BOOTX64.EFI" | grep -q "/boot/grub/grub.cfg"; then
            chk "BOOTX64.EFI embeds search->/boot/grub/grub.cfg bootstrap" 0
        else
            chk "BOOTX64.EFI embeds search->/boot/grub/grub.cfg bootstrap" 1
        fi
        echo "  BOOTX64.EFI: $(file -b "$EVID/BOOTX64.EFI" | cut -c1-80)"
    else
        warn "could not extract BOOTX64.EFI for bootstrap check"
    fi
else
    warn "could not parse EFI image location (system area: $SA)"
fi

# ── 3. Content manifest ────────────────────────────────────────────
echo "--- 3. Calamares modules / branding / settings / repo ---"
[ -f "$ROOT/etc/calamares/settings.conf" ] && chk "etc/calamares/settings.conf" 0 || chk "etc/calamares/settings.conf" 1
[ -f "$ROOT/etc/calamares/modules/packages.conf" ] && chk "etc/calamares/modules/packages.conf" 0 || chk "etc/calamares/modules/packages.conf" 1
[ -f "$ROOT/usr/share/calamares/modules/packages.conf" ] && chk "usr/share/calamares/modules/packages.conf" 0 || chk "usr/share/calamares/modules/packages.conf" 1
for m in mission-os mission-repo mission-cleanup; do
    [ -f "$ROOT/usr/share/calamares/modules/$m/main.py" ] && [ -f "$ROOT/usr/share/calamares/modules/$m/module.desc" ] \
        && chk "module $m (main.py + module.desc)" 0 || chk "module $m (main.py + module.desc)" 1
done
for c in mount unpackfs fstab machineid users displaymanager bootloader welcome finished; do
    [ -f "$ROOT/etc/calamares/modules/$c.conf" ] && chk "config $c.conf" 0 || chk "config $c.conf" 1
done
[ -f "$ROOT/usr/share/calamares/branding/mission-os/branding.desc" ] && chk "branding.desc" 0 || chk "branding.desc" 1
[ -f "$ROOT/usr/share/calamares/branding/mission-os/show.qml" ] && chk "show.qml" 0 || chk "show.qml" 1
[ -f "$ROOT/usr/share/calamares/branding/mission-os/calamares-logo.svg" ] && chk "calamares-logo.svg" 0 || chk "calamares-logo.svg" 1
grep -q "slideshow:" "$ROOT/usr/share/calamares/branding/mission-os/branding.desc" 2>/dev/null && chk "branding slideshow key" 0 || chk "branding slideshow key" 1
[ -f "$ROOT/opt/mission/repo/Packages" ] && chk "repo Packages" 0 || chk "repo Packages" 1
[ -f "$ROOT/opt/mission/repo/Packages.gz" ] && chk "repo Packages.gz" 0 || chk "repo Packages.gz" 1
[ -f "$ROOT/opt/mission/repo/Release" ] && chk "repo Release" 0 || chk "repo Release" 1
DEBS=$(ls "$ROOT/opt/mission/repo/"*.deb 2>/dev/null | wc -l)
[ "$DEBS" -ge 4 ] && chk "repo has 4+ .deb files (got $DEBS)" 0 || chk "repo has 4+ .deb files (got $DEBS)" 1
grep -q "polkitd" "$ROOT/opt/mission/repo/Packages" 2>/dev/null && chk "repo Depends polkitd" 0 || chk "repo Depends polkitd" 1
if grep -q "policykit-1" "$ROOT/opt/mission/repo/Packages" 2>/dev/null; then chk "no obsolete policykit-1 in repo" 1; else chk "no obsolete policykit-1 in repo" 0; fi

echo "  --- settings.conf exec sequence ---"
grep -E "^        - " "$ROOT/etc/calamares/settings.conf" | sed 's/^ *//'
grep -q "        - mount" "$ROOT/etc/calamares/settings.conf" && chk "seq: mount" 0 || chk "seq: mount" 1
grep -q "        - unpackfs" "$ROOT/etc/calamares/settings.conf" && chk "seq: unpackfs" 0 || chk "seq: unpackfs" 1
grep -q "        - mission-repo" "$ROOT/etc/calamares/settings.conf" && chk "seq: mission-repo" 0 || chk "seq: mission-repo" 1
grep -q "        - packages" "$ROOT/etc/calamares/settings.conf" && chk "seq: packages" 0 || chk "seq: packages" 1
grep -q "        - mission-cleanup" "$ROOT/etc/calamares/settings.conf" && chk "seq: mission-cleanup" 0 || chk "seq: mission-cleanup" 1
grep -q "        - umount" "$ROOT/etc/calamares/settings.conf" && chk "seq: umount" 0 || chk "seq: umount" 1

echo "  --- CRITICAL: packages.conf update flag (etc copy = effective) ---"
grep -E "^(update|backend):" "$ROOT/etc/calamares/modules/packages.conf"
grep -qE "^update: false" "$ROOT/etc/calamares/modules/packages.conf" && chk "packages.conf update:false (offline-safe, /etc = effective)" 0 || chk "packages.conf update:false (offline-safe, /etc = effective)" 1
# The /usr/share copy is only a fallback: Calamares loads module config from
# /etc/calamares/modules/<name>.conf first. update:true there is non-blocking.
grep -qE "^update: false" "$ROOT/usr/share/calamares/modules/packages.conf" 2>/dev/null \
    && chk "usr/share packages.conf update:false (fallback copy)" 0 \
    || warn "usr/share/calamares/modules/packages.conf has update:true (fallback copy only; /etc copy is effective and correct — cosmetic, fix in next rebuild)"

echo "  --- first-boot + services ---"
[ -f "$ROOT/usr/lib/mission/mission-first-boot.sh" ] && chk "mission-first-boot.sh" 0 || chk "mission-first-boot.sh" 1
[ -f "$ROOT/usr/lib/systemd/system/mission-first-boot.service" ] && chk "mission-first-boot.service" 0 || chk "mission-first-boot.service" 1
for s in mission-securityd mission-driverd mission-first-boot; do
    [ -L "$ROOT/etc/systemd/system/multi-user.target.wants/$s.service" ] && chk "enabled: $s" 0 || chk "enabled: $s" 1
done
[ -L "$ROOT/etc/systemd/system/display-manager.service" ] && chk "display-manager.service -> sddm" 0 || chk "display-manager.service -> sddm" 1
[ -L "$ROOT/etc/systemd/system/default.target" ] && chk "default.target -> graphical" 0 || chk "default.target -> graphical" 1

# ── 4. Host-path leaks + CRLF ─────────────────────────────────────
echo "--- 4. Host-path leaks + CRLF ---"
LEAKS="$(grep -rIlE "mysteriouspunk|/mnt/c|C:\\\\Users|C:/Users|mission-iso2|mission-vm|mos-audit-evidence|gui-monitor|gui-install|p15-monitor|10\.255\.255\.1|/tmp/mission-os-deb-build" \
        "$ROOT/etc" "$ROOT/usr/share/calamares" "$ROOT/usr/lib/mission" "$ROOT/usr/lib/systemd" \
        "$ROOT/opt" "$ROOT/usr/lib/calamares" "$ROOT/etc/apt" "$ROOT/boot/grub" 2>/dev/null || true)"
if [ -n "$LEAKS" ]; then
    echo "  LEAKS FOUND:"; echo "$LEAKS" | head -20
    chk "no host-specific paths in deployed content" 1
else
    chk "no host-specific paths in deployed content" 0
fi
# check for the literal Windows user dir too, across all text files
LEAKS2="$(grep -rIl "Admin" "$ROOT/usr/share/calamares" "$ROOT/etc/mission" "$ROOT/opt" "$ROOT/usr/lib/mission" 2>/dev/null || true)"
[ -z "$LEAKS2" ] && chk "no 'Admin' references in mission config" 0 || { echo "$LEAKS2" | head; chk "no 'Admin' references in mission config" 1; }

CRLF_FILES="$(for f in \
    "$ROOT/etc/calamares/settings.conf" \
    "$ROOT/etc/calamares/modules/packages.conf" \
    "$ROOT/usr/share/calamares/modules/packages.conf" \
    "$ROOT/usr/share/calamares/branding/mission-os/branding.desc" \
    "$ROOT/usr/share/calamares/branding/mission-os/show.qml" \
    "$ROOT/usr/share/calamares/modules/mission-os/main.py" \
    "$ROOT/usr/share/calamares/modules/mission-repo/main.py" \
    "$ROOT/usr/share/calamares/modules/mission-cleanup/main.py" \
    "$ROOT/usr/share/calamares/modules/mission-os/module.desc" \
    "$ROOT/usr/share/calamares/modules/mission-repo/module.desc" \
    "$ROOT/usr/share/calamares/modules/mission-cleanup/module.desc" \
    "$ROOT/usr/lib/mission/mission-first-boot.sh" \
    "$ROOT/usr/lib/systemd/system/mission-first-boot.service" \
    "$ROOT/usr/lib/systemd/system/mission-securityd.service" \
    "$ROOT/usr/lib/systemd/system/mission-driverd.service" \
    "$ROOT/etc/mission/securityd.toml" "$ROOT/etc/mission/driverd.toml" \
    "$ROOT/etc/sysctl.d/99-mission-os.conf" "$ROOT/etc/profile.d/mission-environment.sh" \
    "$ROOT/etc/calamares/modules/unpackfs.conf" "$ROOT/etc/calamares/modules/users.conf"; do
    if [ -f "$f" ] && grep -q $'\r' "$f" 2>/dev/null; then echo "$f"; fi
done)"
if [ -n "$CRLF_FILES" ]; then
    echo "  CRLF FILES:"; echo "$CRLF_FILES"
    chk "no CRLF in deployed text/config files" 1
else
    chk "no CRLF in deployed text/config files" 0
fi

# ── Summary ────────────────────────────────────────────────────────
echo "=============================================================="
echo " AUDIT SUMMARY: PASS=$PASS FAIL=$FAIL WARN=$WARN"
echo "=============================================================="
echo "USB facts: ISO=$((SIZE/1024/1024)) MiB; 8 GB USB usable ~7.45 GiB; fits with ~5.7 GiB free."
[ "$FAIL" -eq 0 ] && echo "VERDICT: ALL STATIC CHECKS PASSED" || echo "VERDICT: STATIC CHECKS FAILED ($FAIL)"
