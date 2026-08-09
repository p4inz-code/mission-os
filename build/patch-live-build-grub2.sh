#!/bin/bash
# Mission OS — live-build GRUB2 compatibility patch (host-side, idempotent)
#
# WHY THIS EXISTS
# --------------
# live-build 3.0~a57 (Debian trixie-era) generates a `binary.sh` script that
# runs inside the chroot during the binary stage. That script calls
#
#     grub-mkimage -d ${input_dir} -o ${core_img} -O i386-pc biosdisk iso9660
#
# WITHOUT `-p /boot/grub`. GRUB 2.12+ (Debian trixie / Ubuntu resolute) now
# REQUIRES the prefix option and aborts with:
#
#     Usage: grub-mkimage [OPTION...]
#     Prefix not specified (use the -p option).
#
# As a result grub_eltorito is never built, genisoimage writes the ISO with a
# broken El Torito boot image, and the subsequent `isohybrid` step fails with:
#
#     boot loader does not have an isolinux.bin hybrid signature
#
# which makes `lb build` exit non-zero AFTER the ISO is written — aborting
# build-nightly.sh before Phase 8 (ISO move / EFI append / checksums).
#
# Additionally: `isohybrid` is a SYSLINUX-only tool. It CANNOT process a
# GRUB2 El Torito image (verified empirically: every option combination exits
# 1 with the isolinux signature error). Modern Debian live-build / grub-mkrescue
# make GRUB2 ISOs hybrid via xorriso (EFI partition append), which is exactly
# what build-nightly.sh Phase 9 already does. So for `--bootloader grub2` the
# isohybrid step is correctly skipped.
#
# WHAT THIS PATCH DOES (only to /usr/lib/live/build/lb_binary_iso)
# ----------------------------------------------------------------
#   1. Adds `-p /boot/grub` to the grub-mkimage invocation so the BIOS
#      El Torito GRUB image is built correctly.
#   2. Guards the `isohybrid` append with `&& [ "${LB_BOOTLOADER}" != "grub2" ]`
#      so the SYSLINUX-only hybrid step is skipped for the grub2 bootloader.
#   3. Copies the GRUB modules into binary/boot/grub/i386-pc/ inside the ISO
#      (the standard Debian layout). GRUB 2.12's module loader only looks for
#      normal.mod at ${prefix}/${platform}/; live-build's flat /boot/grub/*
#      layout is NOT found and the ISO drops to 'grub rescue>' (verified
#      empirically with trixie grub 2.12).
#
# IMPORTANT — `if [ "${LB_BINARY_IMAGES}" = "iso-hybrid" ]` occurs TWICE in
# lb_binary_iso:
#     (a) near the top, guarding `Check_package ... isohybrid syslinux`
#     (b) near the end, guarding the `cat >> binary.sh` heredoc that emits the
#         `isohybrid` call into binary.sh
# Only (b) is the failing step, so the patch targets the LAST occurrence.
# To stay safe and self-healing across live-build re-installs, the patch:
#   * reverts any previously-applied (or misplaced) version of the patch text,
#   * then applies a fresh copy at the correct (last) occurrence,
#   * and verifies IN PYTHON that the isohybrid emission line now sits inside
#     the guarded block — not merely that some marker string exists.
# This makes the script idempotent, deterministic, and immune to partial or
# mis-targeted prior runs.
#
# SAFETY
# ------
#   - Fails loudly if the expected source lines are NOT found (unexpected
#     live-build version) — it will NOT patch blindly.
#   - Verifies the patch landed and that the patched file passes `bash -n`.
#   - No `|| true` / error suppression anywhere.
#
# Usage:  sudo ./build/patch-live-build-grub2.sh
# (Must run as root; the script re-invokes itself via sudo if needed.)

set -euo pipefail

LB_BINARY_ISO="/usr/lib/live/build/lb_binary_iso"

if [[ "${EUID}" -ne 0 ]]; then
    echo "INFO: re-invoking with sudo (need root to patch ${LB_BINARY_ISO})" >&2
    exec sudo bash "${BASH_SOURCE[0]}"
fi

if [[ ! -f "${LB_BINARY_ISO}" ]]; then
    echo "ERROR: ${LB_BINARY_ISO} not found — is live-build installed?" >&2
    echo "  Install: sudo apt install live-build" >&2
    exit 1
fi

# Apply the patch (byte-exact; raw strings preserve \${...} literally).
# The python is idempotent and self-healing: it reverts any prior version of
# the patch text, then re-applies at the correct location, and verifies
# placement before writing.
python3 - <<'PYEOF' || { echo "ERROR: patch application failed" >&2; exit 1; }
import sys

path = "/usr/lib/live/build/lb_binary_iso"
marker = "MISSION_OS_GRUB2_PATCH_APPLIED"

with open(path, encoding="utf-8") as f:
    original = f.read()

src = original

# --- Patch 1: grub-mkimage needs -p /boot/grub (GRUB 2.12+ requirement) ---
old1 = r'grub-mkimage -d \${input_dir} -o \${core_img} -O i386-pc biosdisk iso9660'
new1 = r'grub-mkimage -d \${input_dir} -p /boot/grub -o \${core_img} -O i386-pc biosdisk iso9660'
# Accept EITHER form: pristine (old1) or already-patched (new1). Fail loudly
# only if the grub-mkimage invocation is entirely absent (unexpected version).
if old1 not in src and new1 not in src:
    print("ERROR: grub-mkimage line not found in lb_binary_iso — unexpected live-build version", file=sys.stderr)
    sys.exit(1)
src = src.replace(new1, old1)   # revert any previous application (self-healing)
src = src.replace(old1, new1, 1)

# --- Patch 2: skip the SYSLINUX-only isohybrid step for grub2 bootloader ---
old2 = 'if [ "${LB_BINARY_IMAGES}" = "iso-hybrid" ]'
new2 = (
    "# " + marker + ": isohybrid is SYSLINUX-only and cannot process GRUB2 El Torito images; "
    "hybrid BIOS+UEFI support is provided by build-nightly.sh Phase 9 (xorriso EFI append).\n"
    'if [ "${LB_BINARY_IMAGES}" = "iso-hybrid" ] && [ "${LB_BOOTLOADER}" != "grub2" ]'
)
# Accept EITHER form: pristine (old2) or already-patched (new2). Fail loudly
# only if the iso-hybrid guard is entirely absent (unexpected version).
if old2 not in src and new2 not in src:
    print("ERROR: iso-hybrid guard line not found in lb_binary_iso — unexpected live-build version", file=sys.stderr)
    sys.exit(1)
src = src.replace(new2, old2)   # revert any previous (possibly misplaced) application
idx = src.rfind(old2)           # target the LAST occurrence (the binary.sh heredoc guard)
if idx == -1:
    print("ERROR: iso-hybrid guard line not found after revert — unexpected live-build version", file=sys.stderr)
    sys.exit(1)
src = src[:idx] + new2 + src[idx + len(old2):]

# --- Patch 3: GRUB 2.12 module layout — also copy modules into the i386-pc
# subdirectory. GRUB 2.12 loads modules from ${prefix}/${platform}/ and does
# NOT fall back to live-build's flat /boot/grub layout (verified empirically:
# flat-layout ISOs drop to 'grub rescue>' with normal.mod not found). ---
# Revert is FORM-AGNOSTIC: it locates any previously-applied version of this
# block by its distinctive marker comment (which is stable across edits) and
# removes everything from that marker through the following 'done\nEOF\n',
# looping until no applied block remains. This keeps self-healing intact even
# when the block's inner content changes between patch-script revisions (a
# pure string-replace revert would otherwise leave duplicate blocks behind).
anchor3 = 'done\nEOF\n'
# NOTE: marker3 is the STABLE revert key — the block's first comment line must
# stay byte-identical across future edits, or the form-agnostic revert below
# will no longer match and duplicate blocks can reappear.
marker3 = 'done\n\n# GRUB 2.12 loads modules from ${prefix}/${platform}/ (i386-pc); the\n'
patch3 = (
    'done\n\n'
    '# GRUB 2.12 loads modules from ${prefix}/${platform}/ (i386-pc); the\n'
    '# flat /boot/grub layout is NOT found. Copy into the standard subdir too.\n'
    'mkdir -p binary/boot/grub/i386-pc\n'
    'for file in \\${input_dir}/*.mod \\${input_dir}/efiemu??.o \\${input_dir}/command.lst \\${input_dir}/moddep.lst \\${input_dir}/fs.lst \\${input_dir}/handler.lst \\${input_dir}/parttool.lst\n'
    'do\n'
    '\tif test -f "\\$file"\n'
    '\tthen\n'
    '\t\tcp -f "\\$file" binary/boot/grub/i386-pc\n'
    '\tfi\n'
    'done\n'
    'EOF\n'
)
while True:
    mstart = src.find(marker3)
    if mstart == -1:
        break
    mend = src.find(anchor3, mstart)
    if mend == -1:
        print("ERROR: found i386-pc patch marker but no terminating done\\nEOF — file corrupt", file=sys.stderr)
        sys.exit(1)
    src = src[:mstart] + anchor3 + src[mend + len(anchor3):]
if src.count(anchor3) != 1:
    print("ERROR: binary.sh module-copy loop anchor not found (done\\nEOF) — unexpected live-build version", file=sys.stderr)
    sys.exit(1)
src = src.replace(anchor3, patch3, 1)

# --- Verify placement BEFORE writing ---
# The patch targets the LAST occurrence of the iso-hybrid guard (the binary.sh
# heredoc block). After patching there must be EXACTLY ONE grub2 guard + marker
# in the file, sitting immediately before the isohybrid emission line. The
# package-check guard (first occurrence) must remain plain. The distance check
# is deliberately loose (2000 chars) — the correct location is ~5 lines before
# the emission, while a mis-targeted patch would land ~146 lines away (>5000
# chars), so 2000 cleanly separates correct from misplaced.
iso_line = 'isohybrid ${ISOHYBRID_OPTIONS} ${IMAGE}'
guard_line = 'if [ "${LB_BINARY_IMAGES}" = "iso-hybrid" ] && [ "${LB_BOOTLOADER}" != "grub2" ]'
iso_idx = src.find(iso_line)
guard_idx = src.rfind(guard_line)
if iso_idx == -1:
    print("ERROR: verification failed — isohybrid emission line not found", file=sys.stderr)
    sys.exit(1)
if src.count(guard_line) != 1 or src.count(marker) != 1:
    print("ERROR: verification failed — expected exactly ONE grub2 guard and ONE marker", file=sys.stderr)
    sys.exit(1)
if guard_idx == -1 or guard_idx > iso_idx or iso_idx - guard_idx > 2000:
    print("ERROR: verification failed — isohybrid emission is NOT inside the guarded block", file=sys.stderr)
    sys.exit(1)
if new1 not in src:
    print("ERROR: verification failed — grub-mkimage -p /boot/grub missing", file=sys.stderr)
    sys.exit(1)
if 'mkdir -p binary/boot/grub/i386-pc' not in src:
    print("ERROR: verification failed — i386-pc module copy missing", file=sys.stderr)
    sys.exit(1)

with open(path, "w", encoding="utf-8") as f:
    f.write(src)

if src != original:
    print("PATCHED lb_binary_iso: grub-mkimage -p /boot/grub + isohybrid grub2 guard + i386-pc modules (placement verified)")
else:
    print("ALREADY PATCHED AND CORRECT: no changes needed")
PYEOF

# Verify the patched file still parses
if ! bash -n "${LB_BINARY_ISO}"; then
    echo "ERROR: lb_binary_iso failed bash -n after patch — inspect ${LB_BINARY_ISO} manually" >&2
    exit 1
fi

echo "✅ live-build GRUB2 patch applied and verified (${LB_BINARY_ISO})"
