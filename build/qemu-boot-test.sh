#!/bin/bash
# Mission OS — QEMU Boot Validation
#
# Boots a Mission OS ISO in QEMU (UEFI and/or BIOS mode) and validates
# that the system reaches a usable state.
#
# Usage:
#   ./build/qemu-boot-test.sh <path-to-iso> [timeout_seconds] [--ci-mode] [--bios]
#
# Modes:
#   Default: UEFI boot via OVMF (requires ovmf package)
#   --bios: BIOS/Legacy boot mode
#
# Default timeout: 120 seconds
#
# Requirements:
#   - qemu-system-x86_64
#   - OVMF (UEFI firmware for QEMU, optional for BIOS mode)
#   - The ISO to test
#
# Exit codes:
#   0 — Boot validation passed
#   1 — Boot validation failed
#   2 — Missing dependencies
#   3 — ISO file not found

set -euo pipefail

CI_MODE=false
BIOS_MODE=false
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --ci-mode) CI_MODE=true; shift ;;
        --bios) BIOS_MODE=true; shift ;;
        *) POSITIONAL+=("$1"); shift ;;
    esac
done

ISO_FILE="${POSITIONAL[0]:-}"
TIMEOUT="${POSITIONAL[1]:-120}"

if [[ -z "${ISO_FILE}" ]]; then
    echo "Usage: $0 <path-to-iso> [timeout_seconds] [--ci-mode] [--bios]" >&2
    exit 2
fi

if [[ "${CI_MODE}" == "true" ]]; then
    echo "Running in CI mode — strict validation enabled"
fi

if [[ ! -f "${ISO_FILE}" ]]; then
    echo "ERROR: ISO file not found: ${ISO_FILE}" >&2
    exit 3
fi

# ── Check Requirements ──────────────────────────────────────────
if ! command -v qemu-system-x86_64 &>/dev/null; then
    echo "ERROR: qemu-system-x86_64 not found" >&2
    echo "Install: sudo apt install qemu-system-x86" >&2
    exit 2
fi

BOOT_MODE="UEFI"
OVMF_CODE=""
OVMF_VARS=""

if [[ "${BIOS_MODE}" == "false" ]]; then
    # Check for OVMF UEFI firmware.
    # Different distros/versions ship different file names:
    #   Debian/older Ubuntu: OVMF_CODE.fd / OVMF_VARS.fd
    #   Newer Ubuntu (24.04+): OVMF_CODE_4M.fd / OVMF_VARS_4M.fd
    #   Debian edk2-ovmf package: /usr/share/edk2-ovmf/x64/OVMF_CODE.fd
    OVMF_CODE_CANDIDATES=(
        "/usr/share/OVMF/OVMF_CODE.fd"
        "/usr/share/OVMF/OVMF_CODE_4M.fd"
        "/usr/share/edk2-ovmf/x64/OVMF_CODE.fd"
    )
    OVMF_VARS_CANDIDATES=(
        "/usr/share/OVMF/OVMF_VARS.fd"
        "/usr/share/OVMF/OVMF_VARS_4M.fd"
        "/usr/share/edk2-ovmf/x64/OVMF_VARS.fd"
    )

    for i in "${!OVMF_CODE_CANDIDATES[@]}"; do
        if [[ -f "${OVMF_CODE_CANDIDATES[$i]}" && -f "${OVMF_VARS_CANDIDATES[$i]}" ]]; then
            OVMF_CODE="${OVMF_CODE_CANDIDATES[$i]}"
            OVMF_VARS="${OVMF_VARS_CANDIDATES[$i]}"
            break
        fi
    done

    if [[ -z "${OVMF_CODE}" ]]; then
        echo "WARNING: OVMF UEFI firmware not found in any standard location" >&2
        echo "  Tried: ${OVMF_CODE_CANDIDATES[*]}" >&2
        if [[ "${CI_MODE}" == "true" ]]; then
            echo "ERROR: UEFI boot validation requested (no --bios) but OVMF is missing." >&2
            echo "  In CI mode, a silent fallback to BIOS would produce a misleading" >&2
            echo "  pass — refusing to continue. Install ovmf and rerun." >&2
            exit 2
        fi
        echo "WARNING: falling back to BIOS mode (local run only). Install ovmf for UEFI testing." >&2
        echo "  Install UEFI support: sudo apt install ovmf" >&2
        BIOS_MODE=true
        BOOT_MODE="BIOS"
    fi
else
    BOOT_MODE="BIOS"
fi

echo "============================================"
echo " Mission OS — QEMU Boot Validation"
echo "============================================"
echo " ISO:      ${ISO_FILE}"
echo " Mode:     ${BOOT_MODE}"
echo " Timeout:  ${TIMEOUT}s"
[[ -n "${OVMF_CODE}" ]] && echo " OVMF:     ${OVMF_CODE}"
echo "============================================"

# ── Create temporary directory for test artifacts ───────────────
# Evidence preservation: the serial log and qemu console output are copied to
# build/images/ (matching the CI artifact upload path build/images/qemu-*.log)
# BEFORE the temp dir is removed, so every validation run is auditable.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="${SCRIPT_DIR}/images"
TEST_DIR="$(mktemp -d -t mission-qemu-test-XXXXXX)"
SERIAL_LOG="${TEST_DIR}/serial.log"
QEMU_OUT=""
QEMU_PID=""

cleanup() {
    if [[ -n "${QEMU_PID}" ]]; then
        kill "${QEMU_PID}" 2>/dev/null || true
        wait "${QEMU_PID}" 2>/dev/null || true
    fi
    # Preserve boot evidence before deleting the temp dir. Best-effort: a copy
    # failure must not mask the real validation result, hence || true here.
    if [[ -n "${SERIAL_LOG}" && -f "${SERIAL_LOG}" ]]; then
        mkdir -p "${EVIDENCE_DIR}"
        cp "${SERIAL_LOG}" "${EVIDENCE_DIR}/qemu-${BOOT_MODE}-serial.log" || echo "WARNING: could not preserve serial log in ${EVIDENCE_DIR}" >&2
    fi
    if [[ -n "${QEMU_OUT}" && -f "${QEMU_OUT}" ]]; then
        mkdir -p "${EVIDENCE_DIR}"
        cp "${QEMU_OUT}" "${EVIDENCE_DIR}/qemu-${BOOT_MODE}.out" || echo "WARNING: could not preserve qemu output in ${EVIDENCE_DIR}" >&2
    fi
    rm -rf "${TEST_DIR}" 2>/dev/null || true
}
trap cleanup EXIT

# ── Boot ISO in QEMU ───────────────────────────────────────────
echo ""
echo "--- Booting ISO in QEMU (${BOOT_MODE} mode) ---"

# Build QEMU arguments
QEMU_ARGS=()

# Common arguments
QEMU_ARGS+=(
    -m 2048
    -smp 2
    -machine q35,accel=kvm:tcg
    -cdrom "${ISO_FILE}"
    -boot order=d
    -nographic
    -no-reboot
    -serial "file:${SERIAL_LOG}"
    -device virtio-rng-pci
    -net none
)

if [[ "${BIOS_MODE}" == "false" ]]; then
    # UEFI mode: use OVMF firmware
    OVMF_VARS_COPY="${TEST_DIR}/OVMF_VARS.fd"
    cp "${OVMF_VARS}" "${OVMF_VARS_COPY}"

    QEMU_ARGS+=(
        -drive if=pflash,format=raw,readonly=on,file="${OVMF_CODE}"
        -drive if=pflash,format=raw,file="${OVMF_VARS_COPY}"
    )
else
    # BIOS mode: no UEFI firmware, standard BIOS boot
    echo "  BIOS mode: booting without UEFI firmware"
fi

# Start QEMU with timeout.
# Console output goes to a file — NEVER pipe into head/tail: a closed
# pipe can SIGPIPE-kill the VM mid-boot (same lesson as the build script's
# xorriso handling). Exit code 124 (timeout kill) is expected here.
QEMU_OUT="${TEST_DIR}/qemu.out"
set +e
timeout "${TIMEOUT}" qemu-system-x86_64 "${QEMU_ARGS[@]}" > "${QEMU_OUT}" 2>&1
QEMU_EXIT_CODE=$?
set -e

echo ""
echo "QEMU exited with code: ${QEMU_EXIT_CODE}"

# ── Analyze Boot Output ────────────────────────────────────────
echo ""
echo "--- Analyzing boot output ---"

if [[ ! -f "${SERIAL_LOG}" ]]; then
    echo "ERROR: No serial output captured"
    exit 1
fi

SERIAL_SIZE=$(wc -c < "${SERIAL_LOG}")
echo "Serial log size: ${SERIAL_SIZE} bytes"

if [[ "${SERIAL_SIZE}" -eq 0 ]]; then
    echo "ERROR: Serial log is empty — ISO may not have booted"
    exit 1
fi

# systemd's console output interleaves ANSI escape sequences (cursor
# positioning / erase-line) into the serial stream. Verified empirically on
# the RC6 BIOS+UEFI logs: the full milestone text exists only as
# ANSI-fragmented bytes, so literal grep patterns false-negative (e.g.
# 'Reached target basic.target' reported missing despite a healthy boot to
# the login prompt). Produce a sanitized copy for all pattern checks; the
# RAW log is still preserved as boot evidence.
CLEAN_LOG="${TEST_DIR}/serial.clean.log"
sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' "${SERIAL_LOG}" | tr -d '\r' > "${CLEAN_LOG}"

# Check for expected boot indicators
PASS=0
FAIL=0

check_boot() {
    local name="$1"
    local pattern="$2"
    if grep -qiE "${pattern}" "${CLEAN_LOG}" 2>/dev/null; then
        echo "  ✅ ${name}"
        PASS=$((PASS + 1))
    else
        echo "  ❌ ${name} (pattern: '${pattern}')"
        FAIL=$((FAIL + 1))
    fi
}

# Firmware (OVMF/SeaBIOS) and GRUB menu text go to the VGA console, not the
# serial port — so they cannot appear in the serial log on a healthy boot.
# Kernel and initramfs loading messages are likewise suppressed on serial by
# the `quiet` kernel cmdline (a Mission OS boot design choice) — verified
# empirically: a full UEFI boot to the login prompt contains NO 'Linux version'
# line. Those four checks are therefore informational. The REAL serial-visible
# boot evidence is systemd milestones + the login prompt, which the hard
# checks below enforce.
# NOTE: patterns use single `|` alternation because they run under `grep -E`;
# a backslash-`|` would be treated as a LITERAL pipe and never match.
check_boot_informational() {
    local name="$1"
    local pattern="$2"
    if grep -qiE "${pattern}" "${CLEAN_LOG}" 2>/dev/null; then
        echo "  ✅ ${name}"
    else
        echo "  ⓘ  ${name} — not serial-visible (informational)"
    fi
}

check_boot_informational "Firmware started" "UEFI|BIOS|BdsDxe|Booting|SeaBIOS|OVMF|EFI Boot|Press F2|Press ESC"
check_boot_informational "Bootloader started" "GRUB|grub|Loading.*kernel|loading.*vmlinuz"
check_boot_informational "Kernel loaded" "Linux version|Booting Linux|Command line:"
check_boot_informational "initramfs loaded" "initrd|initramfs|Loading.*initrd|Begin: Loading"
check_boot "systemd started" "systemd.*running|Started.*systemd|systemd.*Starting"
check_boot "Reached basic target" "Reached target basic.target|Reached target Basic System"
check_boot "Live system detected" "live-boot|Live-session|mission"
check_boot "Login prompt reached" "debian login"

# Show key stage markers from boot output
echo ""
echo "--- Key boot timeline ---"
grep -in "Linux version\|systemd\|Reached target\|live-boot\|mission\|ERROR\|FAIL\|FATAL" "${CLEAN_LOG}" 2>/dev/null | head -30 || echo "  (no timeline markers found)"

# Show last 30 lines of boot output for diagnostics
echo ""
echo "--- Last 30 lines of boot output ---"
tail -30 "${CLEAN_LOG}"

# ── Results ─────────────────────────────────────────────────────
echo ""
echo "============================================"
echo " Boot Validation Results (${BOOT_MODE})"
echo "============================================"
echo "  Passed: ${PASS}"
echo "  Failed: ${FAIL}"
echo "  Log:    ${SERIAL_LOG}"
echo "  Evidence: ${EVIDENCE_DIR}/qemu-${BOOT_MODE}-serial.log"

if [[ "${FAIL}" -gt 0 ]]; then
    echo ""
    echo "❌ Boot validation FAILED (${FAIL} checks failed)"
    exit 1
else
    echo ""
    echo "✅ Boot validation PASSED (${PASS} checks passed)"
    exit 0
fi
