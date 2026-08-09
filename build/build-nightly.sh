#!/bin/bash
# Mission OS — Nightly ISO Build Script
#
# Orchestrates a complete Nightly ISO build from source.
#
# Steps:
#   1. Validate build environment
#   2. Build Rust workspace
#   3. Run tests (optional)
#   4. Generate version metadata
#   5. Configure live-build (lb clean + lb config)
#   6. Deploy Mission OS files into ISO overlay (AFTER lb config!)
#   7. Build ISO (lb build)
#   8. Validate ISO artifacts
#   9. Generate checksums
#
# Usage:
#   ./build/build-nightly.sh [--skip-tests] [--output-dir <path>]
#
# Requirements:
#   - Debian/Ubuntu Linux (not Windows)
#   - Rust toolchain (rustc, cargo)
#   - live-build, debootstrap, xorriso
#   - sudo access (for live-build)
#
# Security:
#   - Builds are isolated in the build directory
#   - MISSION_ALLOW_UNAUTHORIZED is NEVER set
#   - All outputs are checksummed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${PROJECT_ROOT}/build/images"
LIVE_BUILD_DIR="${LIVE_BUILD_DIR:-${PROJECT_ROOT}/build/live-build}"
SKIP_TESTS=false
SKIP_REPO=false
DRY_RUN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-tests) SKIP_TESTS=true; shift ;;
        --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        --skip-repo) SKIP_REPO=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        *) echo "Usage: $0 [--skip-tests] [--output-dir <path>] [--skip-repo] [--dry-run]"; exit 1 ;;
    esac
done

# If LIVE_BUILD_DIR is overridden to a native-filesystem location
# (recommended on WSL: /mnt/c v9fs cannot host debootstrap chroots), seed
# it with the tracked auto/config before lb config runs.
if [[ "${LIVE_BUILD_DIR}" != "${PROJECT_ROOT}/build/live-build" ]]; then
    mkdir -p "${LIVE_BUILD_DIR}/auto"
    cp "${PROJECT_ROOT}/build/live-build/auto/config" "${LIVE_BUILD_DIR}/auto/config"
    chmod +x "${LIVE_BUILD_DIR}/auto/config"
fi

# ── Check Environment ───────────────────────────────────────────
if [[ "$(uname -s)" != "Linux" ]]; then
    echo "ERROR: Nightly ISO build requires Linux (Debian/Ubuntu)." >&2
    echo "Current OS: $(uname -s)" >&2
    exit 1
fi

if [[ -n "${MISSION_ALLOW_UNAUTHORIZED:-}" ]]; then
    echo "ERROR: MISSION_ALLOW_UNAUTHORIZED is set — refusing to build Nightly ISO." >&2
    exit 1
fi

# Check required tools
# syslinux-utils provides isohybrid, which live-build requires to produce
# the hybrid ISO (BIOS+UEFI bootable). Missing it fails the binary stage.
REQUIRED_TOOLS="cargo rustc lb debootstrap xorriso mksquashfs mkfs.fat mcopy grub-mkimage isohybrid"
for tool in ${REQUIRED_TOOLS}; do
    if ! command -v "${tool}" &>/dev/null; then
        echo "ERROR: ${tool} not found — install required packages." >&2
        echo "  On Debian/Ubuntu: sudo apt install live-build debootstrap xorriso mtools" >&2
        echo "    dosfstools squashfs-tools grub-efi-amd64-bin grub-pc-bin syslinux-utils" >&2
        exit 1
    fi
done

# Check for sudo access
if ! sudo -n true 2>/dev/null; then
    echo "ERROR: sudo access required for live-build operations." >&2
    exit 1
fi

# ── Phase 1: Build Rust Workspace ────────────────────────────────
echo "========================================"
echo " Mission OS Nightly Build"
echo "========================================"

cd "${PROJECT_ROOT}"

echo "--- Phase 1: Building Rust workspace ---"
cargo build --release --workspace

if [[ "${SKIP_TESTS}" != "true" ]]; then
    echo "--- Running tests ---"
    cargo test --workspace
fi

# ── Phase 2: Generate Version ────────────────────────────────────
echo "--- Phase 2: Generating version metadata ---"

mkdir -p "${OUTPUT_DIR}"

COMMIT_SHA=""
if command -v git &>/dev/null; then
    COMMIT_SHA="$(git -C "${PROJECT_ROOT}" rev-parse HEAD 2>/dev/null || true)"
fi

"${PROJECT_ROOT}/build/nightly-version.sh" \
    --output "${OUTPUT_DIR}/nightly-version.json" \
    --commit "${COMMIT_SHA:-unknown}"

MISSION_VERSION="$(jq -r '.mission_os_version' "${OUTPUT_DIR}/nightly-version.json" 2>/dev/null || cat "${PROJECT_ROOT}/VERSION" | tr -d '[:space:]')"
echo "Building Mission OS ${MISSION_VERSION}"

# ── Phase 2b: Build Local Package Repository ─────────────────────
# Required for OFFLINE installation: build the four Mission OS .deb
# packages and assemble the flat local repository that the Calamares
# packages module consumes via a file:// source (see
# installer/calamares/modules/packages.conf + mission-repo module).
# --skip-repo reuses an already-built build/mission-repo.
if [[ "${SKIP_REPO}" == "false" ]]; then
    echo "--- Phase 2b: Building local package repository ---"
    "${PROJECT_ROOT}/installer/build-local-repo.sh"
else
    if [[ ! -f "${PROJECT_ROOT}/build/mission-repo/Packages" ]]; then
        echo "ERROR: --skip-repo requested but build/mission-repo/Packages is missing" >&2
        exit 1
    fi
    echo "--- Phase 2b: Reusing existing local repository ---"
fi

# ── Phase 3: Configure live-build ────────────────────────────────
echo "--- Phase 3: Configuring live-build ---"

cd "${LIVE_BUILD_DIR}"

# Clean any previous build configuration to avoid stale cache issues
# Note: lb clean --purge removes the chroot and config/ directory
# We capture its output for diagnostics but it's OK if there's nothing to clean
echo "--- Cleaning previous live-build state ---"
if ! sudo lb clean --purge 2>&1 | tee "${OUTPUT_DIR}/lb-clean.log"; then
    echo "INFO: lb clean had no prior state to clean (expected on first build)"
fi

# Configure live-build via auto/config
# auto/config is the authoritative configuration source.
# It is picked up automatically by `lb config` and handles all settings
# including --bootloader grub2 for dual BIOS+UEFI boot support.
echo "--- Configuring live-build (via auto/config) ---"
sudo lb config 2>&1 | tee "${OUTPUT_DIR}/lb-config.log"

echo "✅ live-build configured (via auto/config)"

# Fix ownership of config directory: sudo lb config creates root-owned files
# but subsequent phases run as the build user
if [[ -d "${LIVE_BUILD_DIR}/config" ]]; then
    if ! sudo chown -R "$(whoami):$(id -gn)" "${LIVE_BUILD_DIR}/config" 2>&1 | tee -a "${OUTPUT_DIR}/lb-config.log"; then
        echo "WARNING: Could not fix config ownership — subsequent phases may fail if run as non-root" >&2
    fi
fi

# ── Phase 4: Create Package Lists ─────────────────────────────────
# Package list files control which Debian packages are installed
# into the live system. Created AFTER lb config so they land in
# config/package-lists/ within the live-build directory.
echo "--- Phase 4: Creating package lists ---"

# KDE Plasma desktop — uses kde-plasma-desktop which pulls in:
#   plasma-desktop, plasma-workspace, kwin, sddm, xserver-xorg, wayland
# Plus essential desktop utilities and Calamares installer
cat > "${LIVE_BUILD_DIR}/config/package-lists/mission-desktop.list.chroot" << 'PKGLIST'
kde-plasma-desktop
sddm
xorg
network-manager
plasma-nm
firefox-esr
calamares
calamares-settings-debian
grub-efi-amd64-bin
grub-efi-amd64-signed
pipewire-pulse
wireplumber
kde-config-sddm
kde-spectacle
print-manager
# isohybrid is required in the chroot: live-build's binary stage runs
# inside the chroot and invokes isohybrid to produce the hybrid ISO.
# The old 'syslinux' package no longer ships in Debian trixie — the
# binary moved to syslinux-utils.
syslinux-utils
PKGLIST

echo "✅ Package lists created"

# ── Phase 4b: Create Custom GRUB Config ───────────────────────────
# live-build's lb_binary_grub2 copies config/binary_grub/grub.cfg to
# binary/boot/grub/grub.cfg when present, then substitutes the
# LINUX_LIVE / LINUX_INSTALL / MEMTEST / LB_BOOTAPPEND_* placeholders.
# The stock template has NO 'set timeout', so GRUB waits at the boot
# menu forever — breaking headless boot and CI validation. This override:
#   * auto-boots the default entry after 10s (set timeout=10)
#   * enables serial console output for headless validation/debugging
#   * drops the tga/xbmc theme references that error without tga.mod
echo "--- Phase 4b: Creating custom GRUB config ---"
mkdir -p "${LIVE_BUILD_DIR}/config/binary_grub"
cat > "${LIVE_BUILD_DIR}/config/binary_grub/grub.cfg" <<'GRUBCFG'
# Mission OS — live ISO GRUB configuration
# Auto-boots the default entry after 10s; serial console enabled for
# headless validation and debugging.
set default=0
set timeout=10

serial --unit=0 --speed=115200
terminal_input serial console
terminal_output serial console

LINUX_LIVE

LINUX_INSTALL

MEMTEST
GRUBCFG
echo "✅ Custom GRUB config created (auto-boot timeout + serial console)"

# ── Phase 5: Deploy Mission OS Package Overlay ───────────────────
# IMPORTANT: This runs AFTER lb config because lb clean --purge
# would destroy the config/ directory. lb config creates the
# config/includes.chroot/ directory structure.
echo "--- Phase 5: Deploying Mission OS package overlay ---"

OVERLAY_DIR="${LIVE_BUILD_DIR}/config/includes.chroot"
mkdir -p "${OVERLAY_DIR}/usr/lib/mission"
mkdir -p "${OVERLAY_DIR}/usr/lib/systemd/system"
mkdir -p "${OVERLAY_DIR}/usr/share/dbus-1/system.d"
mkdir -p "${OVERLAY_DIR}/usr/share/polkit-1/actions"
mkdir -p "${OVERLAY_DIR}/etc/mission"
mkdir -p "${OVERLAY_DIR}/etc/sysctl.d"
mkdir -p "${OVERLAY_DIR}/etc/profile.d"
mkdir -p "${OVERLAY_DIR}/var/cache/mission/drivers"
mkdir -p "${OVERLAY_DIR}/var/cache/mission/drivers/partials"
mkdir -p "${OVERLAY_DIR}/var/lib/mission"

# Copy binaries
install -m 755 "${PROJECT_ROOT}/target/release/mission-securityd" "${OVERLAY_DIR}/usr/lib/mission/"
install -m 755 "${PROJECT_ROOT}/target/release/mission-driverd" "${OVERLAY_DIR}/usr/lib/mission/"

# Copy libraries
install -m 644 "${PROJECT_ROOT}/target/release/libmission_core.so" "${OVERLAY_DIR}/usr/lib/mission/"
install -m 644 "${PROJECT_ROOT}/target/release/libmission_crypto.so" "${OVERLAY_DIR}/usr/lib/mission/"

# Copy systemd units (from deploy/ dir)
install -m 644 "${PROJECT_ROOT}/src/services/securityd/deploy/mission-securityd.service" "${OVERLAY_DIR}/usr/lib/systemd/system/"
install -m 644 "${PROJECT_ROOT}/src/services/driverd/deploy/mission-driverd.service" "${OVERLAY_DIR}/usr/lib/systemd/system/"

# Copy first-boot service
install -m 644 "${PROJECT_ROOT}/build/mission-first-boot.service" "${OVERLAY_DIR}/usr/lib/systemd/system/"
install -m 755 "${PROJECT_ROOT}/installer/mission-first-boot.sh" "${OVERLAY_DIR}/usr/lib/mission/"

# Copy D-Bus policies (from deploy/ dir)
install -m 644 "${PROJECT_ROOT}/src/services/securityd/deploy/org.mission.Security1.conf" "${OVERLAY_DIR}/usr/share/dbus-1/system.d/"
install -m 644 "${PROJECT_ROOT}/src/services/driverd/deploy/org.mission.Driver1.conf" "${OVERLAY_DIR}/usr/share/dbus-1/system.d/"

# Copy PolKit policies (from deploy/ dir)
install -m 644 "${PROJECT_ROOT}/src/services/securityd/deploy/org.mission.security.policy" "${OVERLAY_DIR}/usr/share/polkit-1/actions/"
install -m 644 "${PROJECT_ROOT}/src/services/driverd/deploy/org.mission.driver.policy" "${OVERLAY_DIR}/usr/share/polkit-1/actions/"

# Copy configuration (from deploy/ dir)
install -m 644 "${PROJECT_ROOT}/src/services/securityd/deploy/securityd.toml" "${OVERLAY_DIR}/etc/mission/"
install -m 644 "${PROJECT_ROOT}/src/services/driverd/deploy/driverd.toml" "${OVERLAY_DIR}/etc/mission/"

# Copy sysctl hardening
install -m 644 "${PROJECT_ROOT}/defaults/mission-sysctl.conf" "${OVERLAY_DIR}/etc/sysctl.d/99-mission-os.conf"

# Copy environment defaults
install -m 644 "${PROJECT_ROOT}/defaults/mission-environment.sh" "${OVERLAY_DIR}/etc/profile.d/"

# Copy KDE Plasma defaults
mkdir -p "${OVERLAY_DIR}/etc/xdg"
install -m 644 "${PROJECT_ROOT}/desktop/plasma/kdeglobals" "${OVERLAY_DIR}/etc/xdg/"
install -m 644 "${PROJECT_ROOT}/desktop/plasma/kwinrc" "${OVERLAY_DIR}/etc/xdg/"
install -m 644 "${PROJECT_ROOT}/desktop/plasma/konsolerc" "${OVERLAY_DIR}/etc/xdg/"
install -m 644 "${PROJECT_ROOT}/desktop/plasma/plasmarc" "${OVERLAY_DIR}/etc/xdg/"
install -m 644 "${PROJECT_ROOT}/desktop/plasma/kcminputrc" "${OVERLAY_DIR}/etc/xdg/"
install -m 644 "${PROJECT_ROOT}/desktop/plasma/powermanagementprofilesrc" "${OVERLAY_DIR}/etc/xdg/"
install -m 644 "${PROJECT_ROOT}/desktop/plasma/plasma-org.kde.plasma.desktop-appletsrc" "${OVERLAY_DIR}/etc/xdg/"

# Copy Calamares branding and configuration
if [[ -d "${PROJECT_ROOT}/installer/calamares" ]]; then
    mkdir -p "${OVERLAY_DIR}/etc/calamares"
    mkdir -p "${OVERLAY_DIR}/usr/share/calamares/branding"
    mkdir -p "${OVERLAY_DIR}/usr/share/calamares/modules"

    # Copy Calamares settings
    if [[ -f "${PROJECT_ROOT}/installer/calamares/settings.conf" ]]; then
        install -m 644 "${PROJECT_ROOT}/installer/calamares/settings.conf" "${OVERLAY_DIR}/etc/calamares/"
    fi

    # Copy Calamares branding directory (branding name: mission-os per settings.conf)
    if [[ -d "${PROJECT_ROOT}/installer/calamares/branding/mission-os" ]]; then
        cp -r "${PROJECT_ROOT}/installer/calamares/branding/mission-os" "${OVERLAY_DIR}/usr/share/calamares/branding/"
    fi

    # Copy Calamares custom modules (mission-os + mission-repo)
    if [[ -d "${PROJECT_ROOT}/installer/calamares/modules/mission-os" ]]; then
        cp -r "${PROJECT_ROOT}/installer/calamares/modules/mission-os" "${OVERLAY_DIR}/usr/share/calamares/modules/"
    fi
    if [[ -d "${PROJECT_ROOT}/installer/calamares/modules/mission-repo" ]]; then
        cp -r "${PROJECT_ROOT}/installer/calamares/modules/mission-repo" "${OVERLAY_DIR}/usr/share/calamares/modules/"
    fi
    if [[ -d "${PROJECT_ROOT}/installer/calamares/modules/mission-cleanup" ]]; then
        cp -r "${PROJECT_ROOT}/installer/calamares/modules/mission-cleanup" "${OVERLAY_DIR}/usr/share/calamares/modules/"
    fi
    # Copy the packages module configuration (installs Mission OS
    # packages offline from the staged local repository). Deploy to BOTH
    # /etc/calamares/modules/ (overriding the calamares-settings-debian
    # copy, which otherwise wins config precedence and would skip the
    # Mission OS installs) and /usr/share/calamares/modules/ (fallback).
    if [[ -f "${PROJECT_ROOT}/installer/calamares/modules/packages.conf" ]]; then
        mkdir -p "${OVERLAY_DIR}/etc/calamares/modules"
        install -m 644 "${PROJECT_ROOT}/installer/calamares/modules/packages.conf" "${OVERLAY_DIR}/etc/calamares/modules/"
        install -m 644 "${PROJECT_ROOT}/installer/calamares/modules/packages.conf" "${OVERLAY_DIR}/usr/share/calamares/modules/"
    fi
fi

# Copy KDE color scheme
mkdir -p "${OVERLAY_DIR}/usr/share/color-schemes"
install -m 644 "${PROJECT_ROOT}/desktop/plasma/colorschemes/mission-graphite.colors" "${OVERLAY_DIR}/usr/share/color-schemes/"

# Copy Konsole profile
mkdir -p "${OVERLAY_DIR}/usr/share/konsole"
install -m 644 "${PROJECT_ROOT}/desktop/plasma/konsole-profiles/MissionOS.profile" "${OVERLAY_DIR}/usr/share/konsole/"

# Copy wallpaper
mkdir -p "${OVERLAY_DIR}/usr/share/wallpapers/mission-os/contents/images"
install -m 644 "${PROJECT_ROOT}/desktop/wallpaper/contents/images/3840x2160.svg" "${OVERLAY_DIR}/usr/share/wallpapers/mission-os/contents/images/"
install -m 644 "${PROJECT_ROOT}/desktop/wallpaper/contents/metadata.desktop" "${OVERLAY_DIR}/usr/share/wallpapers/mission-os/"

# Copy version metadata
install -m 644 "${OUTPUT_DIR}/nightly-version.json" "${OVERLAY_DIR}/etc/mission/nightly-version.json"
echo "${MISSION_VERSION}" > "${OVERLAY_DIR}/etc/mission/VERSION"

# Stage the local package repository on the installation media at
# /opt/mission/repo (the mission-repo Calamares module reads it from here
# and stages it into the target at /var/cache/mission/repo for the
# offline `packages` step).
REPO_SRC="${PROJECT_ROOT}/build/mission-repo"
if [[ -f "${REPO_SRC}/Packages" ]]; then
    mkdir -p "${OVERLAY_DIR}/opt/mission/repo"
    cp -a "${REPO_SRC}/." "${OVERLAY_DIR}/opt/mission/repo/"
    echo "✅ Local repository staged at /opt/mission/repo (offline install)"
else
    echo "ERROR: ${REPO_SRC}/Packages missing — cannot stage offline repository" >&2
    exit 1
fi

# GRUB 2.12+ compatibility: stage2_eltorito was removed but live-build expects it
# Use cdboot.img (GRUB 2 CD boot image) as replacement for El Torito boot
mkdir -p "${OVERLAY_DIR}/usr/lib/grub/i386-pc"
ln -sf cdboot.img "${OVERLAY_DIR}/usr/lib/grub/i386-pc/stage2_eltorito" 2>/dev/null || true

echo "✅ Mission OS package overlay deployed"

# ── Phase 5b: Normalize Overlay Text Files to LF ─────────────────
# The Windows working tree (core.autocrlf checkout) writes CRLF into
# text files. Linux interpreters reject CRLF: a `#!/bin/bash\r` shebang
# fails (bash: /bin/bash^M: bad interpreter) and `env` cannot resolve
# `python3\r`. Normalize every text artifact deterministically so the
# live/installed system always sees LF regardless of the checkout.
# Binary artifacts (.so, ELF, .deb) are not matched by the extensions.
echo "--- Phase 5b: Normalizing overlay text files to LF ---"
find "${OVERLAY_DIR}" -type f \( \
    -name '*.sh' -o -name '*.service' -o -name '*.conf' -o \
    -name '*.toml' -o -name '*.py' -o -name '*.desc' -o \
    -name '*.colors' -o -name '*.profile' -o -name '*.json' -o \
    -name '*.desktop' -o -name '*.svg' -o -name '*.list' -o \
    -name '*.qml' \) \
    -exec sed -i 's/\r$//' {} +
# Remove any stale Python bytecode copied from the source tree
find "${OVERLAY_DIR}" -name '__pycache__' -type d -prune -exec rm -rf {} +
echo "✅ Overlay text files normalized to LF"

# ── Phase 6: Enable Mission Services ─────────────────────────────
# Create enable symlinks so systemd units start on boot
# This is equivalent to: systemctl enable mission-securityd.service (etc.)
echo "--- Phase 6: Enabling Mission services ---"

mkdir -p "${OVERLAY_DIR}/etc/systemd/system/multi-user.target.wants"
ln -sf /usr/lib/systemd/system/mission-securityd.service "${OVERLAY_DIR}/etc/systemd/system/multi-user.target.wants/mission-securityd.service"
ln -sf /usr/lib/systemd/system/mission-driverd.service "${OVERLAY_DIR}/etc/systemd/system/multi-user.target.wants/mission-driverd.service"
ln -sf /usr/lib/systemd/system/mission-first-boot.service "${OVERLAY_DIR}/etc/systemd/system/multi-user.target.wants/mission-first-boot.service"

# Enable SDDM as display manager
ln -sf /usr/lib/systemd/system/sddm.service "${OVERLAY_DIR}/etc/systemd/system/display-manager.service" 2>/dev/null || true

# Set default target to graphical
mkdir -p "${OVERLAY_DIR}/etc/systemd/system"
ln -sf /usr/lib/systemd/system/graphical.target "${OVERLAY_DIR}/etc/systemd/system/default.target"

echo "✅ Mission services enabled"

# ── Phase 6b: Patch live-build for GRUB 2.12+ ────────────────────
# live-build 3.0~a57's lb_binary_iso invokes grub-mkimage WITHOUT -p,
# which GRUB 2.12+ (Debian trixie / Ubuntu resolute) rejects with
# "Prefix not specified (use the -p option)" — breaking grub_eltorito and
# the subsequent isohybrid step, so `lb build` exits non-zero AFTER writing
# the ISO (aborting before Phase 8). isohybrid is SYSLINUX-only and cannot
# process GRUB2 El Torito images; hybrid BIOS+UEFI support is provided by
# Phase 9 via xorriso. This idempotent host-side patch fixes both. It fails
# loudly (no suppression) if live-build differs from the expected version.
echo "--- Phase 6b: Patching live-build for GRUB 2.12+ ---"
sudo bash "${PROJECT_ROOT}/build/patch-live-build-grub2.sh"
echo "✅ live-build GRUB2 compatibility patch applied"

# ── Phase 6c: Verify Overlay & Installer Inputs ──────────────────
# Every file the ISO and the offline installer depend on must exist
# BEFORE the long lb build starts. This is the pre-ISO dry-run gate.
echo "--- Phase 6c: Verifying overlay and installer inputs ---"
MISSING=0
for f in \
    "${OVERLAY_DIR}/usr/lib/mission/mission-securityd" \
    "${OVERLAY_DIR}/usr/lib/mission/mission-driverd" \
    "${OVERLAY_DIR}/usr/lib/mission/libmission_core.so" \
    "${OVERLAY_DIR}/usr/lib/mission/libmission_crypto.so" \
    "${OVERLAY_DIR}/usr/lib/mission/mission-first-boot.sh" \
    "${OVERLAY_DIR}/usr/lib/systemd/system/mission-securityd.service" \
    "${OVERLAY_DIR}/usr/lib/systemd/system/mission-driverd.service" \
    "${OVERLAY_DIR}/usr/lib/systemd/system/mission-first-boot.service" \
    "${OVERLAY_DIR}/usr/share/calamares/modules/packages.conf" \
    "${OVERLAY_DIR}/etc/calamares/modules/packages.conf" \
    "${OVERLAY_DIR}/usr/share/calamares/branding/mission-os/branding.desc" \
    "${OVERLAY_DIR}/usr/share/calamares/branding/mission-os/show.qml" \
    "${OVERLAY_DIR}/usr/share/calamares/modules/mission-repo/main.py" \
    "${OVERLAY_DIR}/usr/share/calamares/modules/mission-repo/module.desc" \
    "${OVERLAY_DIR}/usr/share/calamares/modules/mission-os/main.py" \
    "${OVERLAY_DIR}/usr/share/calamares/modules/mission-cleanup/main.py" \
    "${OVERLAY_DIR}/usr/share/calamares/modules/mission-cleanup/module.desc" \
    "${OVERLAY_DIR}/etc/calamares/settings.conf" \
    "${OVERLAY_DIR}/opt/mission/repo/Packages" \
    "${OVERLAY_DIR}/opt/mission/repo/Packages.gz" \
    "${OVERLAY_DIR}/opt/mission/repo/Release" \
    "${OVERLAY_DIR}/etc/sysctl.d/99-mission-os.conf" \
    "${OVERLAY_DIR}/etc/profile.d/mission-environment.sh" \
    "${OVERLAY_DIR}/usr/share/wallpapers/mission-os/contents/images/3840x2160.svg" \
    "${OVERLAY_DIR}/usr/share/color-schemes/mission-graphite.colors"; do
    if [[ ! -f "${f}" ]]; then
        echo "  ❌ MISSING: ${f}" >&2
        MISSING=1
    fi
done
if ! ls "${OVERLAY_DIR}/opt/mission/repo/"*.deb >/dev/null 2>&1; then
    echo "  ❌ MISSING: .deb artifacts in /opt/mission/repo" >&2
    MISSING=1
fi
if [[ "${MISSING}" -ne 0 ]]; then
    echo "ERROR: overlay/installer verification failed — aborting before lb build" >&2
    exit 1
fi
echo "✅ Overlay and installer inputs verified (all files present)"

# ── Phase 7: Build ISO ──────────────────────────────────────────
echo "--- Phase 7: Building ISO ---"

if [[ "${DRY_RUN}" == "true" ]]; then
    echo "DRY-RUN: stopping before lb build — all inputs verified above."
    echo "DRY-RUN: live-build configuration is ready at ${LIVE_BUILD_DIR}/config"
    exit 0
fi

cd "${LIVE_BUILD_DIR}"
sudo lb build 2>&1 | tee "${OUTPUT_DIR}/lb-build.log"

# ── Phase 8: Validate ISO ────────────────────────────────────────
echo "--- Phase 8: Validating ISO ---"

# Live-build produces binary.hybrid.iso in the live-build directory
ISO_FILE="${LIVE_BUILD_DIR}/binary.hybrid.iso"

if [[ ! -f "${ISO_FILE}" ]]; then
    # Fallback: search for any .iso file that might have been generated
    ISO_FILE="$(find "${LIVE_BUILD_DIR}" -name "binary.hybrid.iso" -type f 2>/dev/null | head -1)"
fi

if [[ ! -f "${ISO_FILE}" ]]; then
    ISO_FILE="$(find "${LIVE_BUILD_DIR}" -name "*.iso" -type f 2>/dev/null | head -1)"
fi

if [[ -z "${ISO_FILE}" || ! -f "${ISO_FILE}" ]]; then
    echo "ERROR: ISO file not found after build!" >&2
    echo "Check ${LIVE_BUILD_DIR} for build artifacts." >&2
    exit 1
fi

echo "ISO found: ${ISO_FILE}"

echo "ISO size: $(stat -c%s "${ISO_FILE}" 2>/dev/null || stat -f%z "${ISO_FILE}" 2>/dev/null) bytes"

FINAL_ISO_NAME="mission-os-${MISSION_VERSION}-amd64.hybrid.iso"
# The ISO is produced root-owned inside the root-owned chroot by
# `sudo lb build` (binary stage runs inside the chroot), so a plain mv
# fails with EACCES. Move it with sudo, then hand ownership back to the
# build user so later phases (EFI append, checksums) work normally.
sudo mv "${ISO_FILE}" "${OUTPUT_DIR}/${FINAL_ISO_NAME}"
sudo chown "$(whoami):$(id -gn)" "${OUTPUT_DIR}/${FINAL_ISO_NAME}"
ISO_FINAL="${OUTPUT_DIR}/${FINAL_ISO_NAME}"

# ── Phase 9: Ensure EFI Boot Support ──────────────────────────────
# live-build's binary_grub2 might not always generate a proper
# EFI boot image. This step verifies and adds EFI boot support
# using grub-mkimage and xorriso.
#
# CRITICAL: NEVER pipe xorriso output into `tail` or similar filters
# that can cause SIGPIPE and silently terminate the producer.
# Capture output into variables or temp files instead.
echo "--- Phase 9: Verifying EFI boot support ---"

# Check for EFI boot using xorriso system area report (more reliable than grep)
EFI_CHECK_OUTPUT="$(xorriso -indev "${ISO_FINAL}" -report_system_area 2>&1 || true)"
EFI_PRESENT=false
if echo "${EFI_CHECK_OUTPUT}" | grep -qi 'EFI\|GPT\|appended partition 2'; then
    EFI_PRESENT=true
fi

if [[ "${EFI_PRESENT}" == "false" ]]; then
    echo "No EFI boot image detected — generating EFI boot support..."
    echo "  xorriso system area report:"
    echo "${EFI_CHECK_OUTPUT}" | head -10
    echo ""

    # Check that grub-mkimage is available (on the host, not in chroot)
    if ! command -v grub-mkimage &>/dev/null; then
        echo "ERROR: grub-mkimage not available on host — install grub-efi-amd64-bin" >&2
        echo "  sudo apt install grub-efi-amd64-bin grub-pc-bin" >&2
        exit 1
    fi

    EFI_IMG="$(mktemp -p "${OUTPUT_DIR}" efi-img-XXXXXX.img)"

    # Create a FAT image large enough for GRUB EFI binary (20 MB)
    echo "  Creating FAT EFI image (${EFI_IMG})..."
    dd if=/dev/zero of="${EFI_IMG}" bs=1M count=20 2>&1 | tee -a "${OUTPUT_DIR}/lb-build.log"
    mkfs.fat "${EFI_IMG}" -n MISSION_OS 2>&1 | tee -a "${OUTPUT_DIR}/lb-build.log"
    mmd -i "${EFI_IMG}" ::/EFI ::/EFI/BOOT

    # Generate GRUB EFI binary from host modules
    GRUB_MODULES="normal part_gpt part_msdos fat ext2 iso9660 linux boot chain configfile search search_fs_file search_fs_uuid search_label ls echo test true"

    # Embed a bootstrap config: locate the ISO's /boot/grub/grub.cfg on any
    # device and chain-load it. Without this, GRUB would only look for
    # /boot/grub/grub.cfg on the FAT ESP (which contains only BOOTX64.EFI)
    # and drop to the rescue prompt. Same approach as Debian's own EFI
    # images. (Single-quoted heredoc: $root stays a GRUB variable.)
    grub_cfg_src="$(mktemp -p "${OUTPUT_DIR}" grub-cfg-XXXXXX.cfg)"
    cat > "${grub_cfg_src}" <<'EOF'
search --no-floppy --set=root --file /boot/grub/grub.cfg
set prefix=($root)/boot/grub
configfile /boot/grub/grub.cfg
EOF

    grub_mkimage_output="$(mktemp -p "${OUTPUT_DIR}" bootx64-XXXXXX.efi)"
    grub-mkimage \
        -o "${grub_mkimage_output}" \
        -O x86_64-efi \
        -p /boot/grub \
        -c "${grub_cfg_src}" \
        ${GRUB_MODULES} 2>&1
    rm -f "${grub_cfg_src}"

    if [[ ! -f "${grub_mkimage_output}" ]]; then
        echo "ERROR: grub-mkimage failed — could not generate EFI binary" >&2
        rm -f "${EFI_IMG}" "${grub_cfg_src}"
        exit 1
    fi

    # Copy EFI binary to FAT image
    mcopy -i "${EFI_IMG}" "${grub_mkimage_output}" ::/EFI/BOOT/BOOTX64.EFI
    echo "Generated GRUB EFI binary with modules: ${GRUB_MODULES}"

    # Rebuild ISO with EFI boot partition
    # Use a temp file for the xorriso output (never pipe to tail!)
    ISO_TMP="$(mktemp -p "${OUTPUT_DIR}" iso-tmp-XXXXXX.iso)"

    xorriso -indev "${ISO_FINAL}" -outdev "${ISO_TMP}" \
        -boot_image any replay \
        -append_partition 2 0xef "${EFI_IMG}" \
        -boot_image any next \
        -boot_image any efi_path=--interval:appended_partition_2:all:: \
        -boot_image any next \
        2>&1 | tee "${OUTPUT_DIR}/xorriso-efi-add.log"

    # Check if xorriso succeeded (exit code from pipe is from tee, so check file)
    if [[ ! -f "${ISO_TMP}" ]] || [[ "$(stat -c%s "${ISO_TMP}" 2>/dev/null || echo 0)" -eq 0 ]]; then
        echo "ERROR: xorriso failed to add EFI boot partition" >&2
        rm -f "${EFI_IMG}" "${ISO_TMP}" "${grub_mkimage_output}" 2>/dev/null || true
        exit 1
    fi

    mv "${ISO_TMP}" "${ISO_FINAL}"
    rm -f "${EFI_IMG}" "${grub_mkimage_output}" 2>/dev/null || true

    # Verify EFI boot support was added
    EFI_VERIFY="$(xorriso -indev "${ISO_FINAL}" -report_system_area 2>&1 || true)"
    if echo "${EFI_VERIFY}" | grep -qi 'EFI\|GPT\|appended partition 2'; then
        echo "✅ EFI boot support added and verified"
    else
        echo "ERROR: Failed to add EFI boot image to ISO" >&2
        echo "  xorriso report: ${EFI_VERIFY}"
        exit 1
    fi
else
    echo "✅ EFI boot image already present"
fi

# ── Phase 10: ISO Analysis & Checksums ───────────────────────────
echo "--- Phase 10: ISO analysis and checksums ---"

# Analyze ISO metadata
ISO_SIZE="$(stat -c%s "${ISO_FINAL}" 2>/dev/null || stat -f%z "${ISO_FINAL}" 2>/dev/null)"
echo "ISO size: ${ISO_SIZE} bytes"

if [[ "${ISO_SIZE}" -lt 100000000 ]]; then
    echo "WARNING: ISO size (${ISO_SIZE}) seems too small for a desktop ISO" >&2
fi

FILE_TYPE="$(file "${ISO_FINAL}" 2>/dev/null || echo "unknown")"
echo "ISO type: ${FILE_TYPE}"

# List ISO structure
if command -v xorriso &>/dev/null; then
    echo "ISO El Torito boot catalog:"
    # Never pipe xorriso into head (SIGPIPE risk) — capture to a file.
    # Do not abort on failure (informational step) but DO surface it.
    TOC_LOG="$(mktemp -p "${OUTPUT_DIR}" toc-XXXXXX.log)"
    if ! xorriso -indev "${ISO_FINAL}" -toc > "${TOC_LOG}" 2>&1; then
        echo "WARNING: xorriso -toc failed — first lines of its output:" >&2
        head -5 "${TOC_LOG}" >&2
    fi
    head -30 "${TOC_LOG}"
    rm -f "${TOC_LOG}"
    echo ""
fi

# Generate checksums
cd "${OUTPUT_DIR}"

sha256sum "$(basename "${ISO_FINAL}")" > "${ISO_FINAL}.sha256"
sha256sum nightly-version.json > "nightly-version.json.sha256"

echo "Checksums:"
cat "${ISO_FINAL}.sha256"

# ── Summary ─────────────────────────────────────────────────────
echo ""
echo "========================================"
echo " Nightly Build Complete"
echo "========================================"
echo " Version:  ${MISSION_VERSION}"
echo " ISO:      ${ISO_FINAL}"
echo " Size:     ${ISO_SIZE} bytes"
echo " Checksum: ${ISO_FINAL}.sha256"
echo " Metadata: ${OUTPUT_DIR}/nightly-version.json"
echo "========================================"
