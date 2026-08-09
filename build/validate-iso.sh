#!/bin/bash
# Mission OS — ISO Validation Script
#
# Validates a Mission OS ISO for structural integrity.
# Can be run locally or in CI.
#
# Usage:
#   ./build/validate-iso.sh <path-to-iso>
#
# Exit codes:
#   0 — All checks passed
#   1 — Validation failed
#   2 — ISO file not found

set -euo pipefail

ISO_FILE="${1:-}"

if [[ -z "${ISO_FILE}" ]]; then
    echo "Usage: $0 <path-to-iso>" >&2
    exit 2
fi

if [[ ! -f "${ISO_FILE}" ]]; then
    echo "ERROR: ISO file not found: ${ISO_FILE}" >&2
    exit 2
fi

PASS=0
FAIL=0

check() {
    local name="$1"
    local result="$2"
    if [[ "${result}" -eq 0 ]]; then
        echo "  ✅ ${name}"
        PASS=$((PASS + 1))
    else
        echo "  ❌ ${name}"
        FAIL=$((FAIL + 1))
    fi
}

echo "========================================="
echo " ISO Validation: ${ISO_FILE}"
echo "========================================="

# ── Basic Checks ─────────────────────────────────────────────────
echo "--- Basic Checks ---"

# Check 1: File exists and is non-empty
check "File exists and non-empty" $(test -s "${ISO_FILE}" && echo 0 || echo 1)

# Check 2: File is identified as ISO 9660
FILE_TYPE="$(file "${ISO_FILE}" 2>/dev/null || echo "unknown")"
check "File type is ISO 9660" $(echo "${FILE_TYPE}" | grep -qi "iso 9660\|boot image\|hybrid\|filesystem" && echo 0 || echo 1)
echo "     Type: ${FILE_TYPE}"

# Check 3: File size is reasonable (> 500 MB for desktop ISO)
ISO_SIZE="$(stat -c%s "${ISO_FILE}" 2>/dev/null || stat -f%z "${ISO_FILE}" 2>/dev/null || echo 0)"
check "ISO size > 500 MB" $(test "${ISO_SIZE}" -ge 500000000 && echo 0 || echo 1)
echo "     Size: $((ISO_SIZE / 1024 / 1024)) MB"

# ── Content Checks ───────────────────────────────────────────────
echo "--- Content Checks ---"

if command -v xorriso &>/dev/null; then
    echo "  (Using xorriso for content analysis)"

    # Check 4: El Torito BIOS boot catalog exists
    TOC_OUTPUT="$(xorriso -indev "${ISO_FILE}" -toc 2>&1 || true)"
    check "El Torito BIOS boot catalog present" $(echo "${TOC_OUTPUT}" | grep -qi "boot image" && echo 0 || echo 1)

    # Check 5: EFI boot entry exists (check system area for EFI/GPT)
    SA_OUTPUT="$(xorriso -indev "${ISO_FILE}" -report_system_area 2>&1 || true)"
    check "EFI system area / GPT partition present" $(echo "${SA_OUTPUT}" | grep -qi "EFI\|GPT\|appended partition 2" && echo 0 || echo 1)
    echo "     System area: $(echo "${SA_OUTPUT}" | head -5 | tr '\n' ' ')"

    # Check 6: EFI boot image in TOC.
    # xorriso prints the EFI entry as 'platform_id=0xEF', NOT the literal
    # words "EFI boot" — grep the real token.
    check "El Torito EFI boot entry present" $(echo "${TOC_OUTPUT}" | grep -qi "platform_id=0xEF" && echo 0 || echo 1)

    # NOTE on the -find pipelines below: when a path is absent, xorriso
    # exits non-zero (observed: 5 for -find /EFI). Under `set -euo pipefail`
    # that would abort the whole script, silently skipping checksum + summary.
    # The `|| true` keeps the run going so check() below reports the honest
    # result (count 0 => the check fails).

    # Check 7: Boot directory exists
    BOOT_COUNT=$(xorriso -indev "${ISO_FILE}" -find /boot -type d 2>/dev/null | wc -l || true)
    check "Boot directory exists" $(test "${BOOT_COUNT}" -ge 1 && echo 0 || echo 1)

    # Check 8: Live directory exists (SquashFS)
    LIVE_COUNT=$(xorriso -indev "${ISO_FILE}" -find /live -type d 2>/dev/null | wc -l || true)
    check "Live directory exists" $(test "${LIVE_COUNT}" -ge 1 && echo 0 || echo 1)

    # Check 9: SquashFS file exists
    SQUASHFS_COUNT=$(xorriso -indev "${ISO_FILE}" -find /live -name "*.squashfs" -type f 2>/dev/null | wc -l || true)
    check "SquashFS filesystem exists" $(test "${SQUASHFS_COUNT}" -ge 1 && echo 0 || echo 1)

    # Check 10: vmlinuz (kernel) exists
    KERNEL_COUNT=$(xorriso -indev "${ISO_FILE}" -find /live -name "vmlinuz*" -type f 2>/dev/null | wc -l || true)
    check "Kernel (vmlinuz) exists" $(test "${KERNEL_COUNT}" -ge 1 && echo 0 || echo 1)

    # Check 11: initrd (initramfs) exists
    INITRD_COUNT=$(xorriso -indev "${ISO_FILE}" -find /live -name "initrd*" -type f 2>/dev/null | wc -l || true)
    check "Initramfs (initrd) exists" $(test "${INITRD_COUNT}" -ge 1 && echo 0 || echo 1)

    # Check 12: GRUB configuration exists
    GRUB_CFG_COUNT=$(xorriso -indev "${ISO_FILE}" -find /boot/grub -name "grub.cfg" -type f 2>/dev/null | wc -l || true)
    check "GRUB configuration (grub.cfg) exists" $(test "${GRUB_CFG_COUNT}" -ge 1 && echo 0 || echo 1)

    # Check 13: ISO is hybrid (BIOS El Torito + UEFI/GPT system area).
    # NOTE: do NOT grep the -toc output for the literal word "hybrid" —
    # xorriso never prints it. Check the El Torito boot catalog entries
    # and the GPT/EFI system area report instead.
    HYBRID_RESULT=1
    # BIOS leg: El Torito boot image in the TOC.
    # UEFI leg: EFI partition in the system-area report. xorriso prints
    # this as MBR partition type '0xef' (or an EFI note), not "GPT" —
    # grep the real tokens.
    if echo "${TOC_OUTPUT}" | grep -qi "boot image" && echo "${SA_OUTPUT}" | grep -qiE "0xef|EFI"; then
        HYBRID_RESULT=0
    fi
    check "ISO is hybrid (BIOS+UEFI)" ${HYBRID_RESULT}

    # Check 14: EFI boot image present.
    # The grub2/xorriso hybrid layout embeds EFI as a HIDDEN El-Torito image
    # (xorriso notes "Found hidden El-Torito image for EFI") plus an appended
    # MBR partition type 0xef — there is NO visible /EFI directory in this
    # layout. Verify the real artifact instead of a legacy /EFI dir.
    check "EFI boot image present (hidden El-Torito)" \
        $(echo "${TOC_OUTPUT}" | grep -qi "hidden El-Torito image for EFI" && echo 0 || echo 1)
elif command -v isoinfo &>/dev/null; then
    echo "  (Using isoinfo for content analysis)"
    isoinfo -l -i "${ISO_FILE}" 2>/dev/null | head -30 || echo "isoinfo list failed"
else
    echo "  ⚠️  xorriso not available — limited content checks performed"
fi

# ── Integrity Checks ────────────────────────────────────────────
echo "--- Integrity Checks ---"

# Check 15: SHA-256 checksum exists and matches.
# The .sha256 sidecar holds a BARE relative filename (e.g.
# 'mission-os-...iso'), so sha256sum -c must run from the ISO's own
# directory — otherwise it reports 'FAILED open or read' even when the
# digest is correct (observed on the RC6 ISO; the computed hash matches).
if [[ -f "${ISO_FILE}.sha256" ]]; then
    SHA256_CHECK=1
    if (cd "$(dirname "${ISO_FILE}")" && sha256sum -c "$(basename "${ISO_FILE}").sha256") >/dev/null 2>&1; then
        SHA256_CHECK=0
    fi
    check "SHA-256 checksum matches" ${SHA256_CHECK}
else
    echo "  ⚠️  No SHA-256 checksum file found (${ISO_FILE}.sha256)"
    echo "     Generating for reference..."
    ACTUAL=$(sha256sum "${ISO_FILE}" | cut -d' ' -f1)
    echo "     SHA-256: ${ACTUAL}"
fi

# ── Summary ─────────────────────────────────────────────────────
echo ""
echo "========================================="
echo " Validation Results"
echo "========================================="
echo "  Passed: ${PASS}"
echo "  Failed: ${FAIL}"

if [[ "${FAIL}" -gt 0 ]]; then
    echo ""
    echo "❌ ISO validation FAILED (${FAIL} checks failed)"
    exit 1
else
    echo ""
    echo "✅ ISO validation PASSED (${PASS} checks passed)"
    exit 0
fi
