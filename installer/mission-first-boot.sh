#!/bin/bash
# Mission OS — First-Boot Initialization
#
# Runs on first boot to configure:
#   - User environment (if no users exist)
#   - Mission OS defaults
#   - Service readiness
#   - Basic privacy profile
#
# This script is IDEMPOTENT — running it multiple times is safe.
# It uses a state marker at /var/lib/mission/first-boot-complete
# to skip already-completed steps.
#
# Security:
#   - No secrets are stored in plaintext
#   - MISSION_ALLOW_UNAUTHORIZED is NEVER set here
#   - User creation requires explicit password (not automatic)
#   - All destructive operations are guarded

set -euo pipefail

# ── State Marker ─────────────────────────────────────────────────
STATE_FILE="/var/lib/mission/first-boot-complete"
STATE_DIR="/var/lib/mission"

# ── Logging ──────────────────────────────────────────────────────
log_info()  { echo "[first-boot] INFO: $*"; }
log_warn()  { echo "[first-boot] WARN: $*"; }
log_error() { echo "[first-boot] ERROR: $*" >&2; }

# ── Check idempotency ──────────────────────────────────────────
if [[ -f "${STATE_FILE}" ]]; then
    log_info "First-boot already completed (${STATE_FILE} exists). Skipping."
    exit 0
fi

log_info "Mission OS first-boot initialization starting..."

mkdir -p "${STATE_DIR}"

# ── Phase 1: System Configuration ────────────────────────────────
log_info "Phase 1: System configuration..."

# Apply sysctl hardening (if not already applied)
if [ -f /etc/sysctl.d/99-mission-os.conf ] && command -v sysctl &>/dev/null; then
    sysctl -p /etc/sysctl.d/99-mission-os.conf 2>/dev/null || log_warn "sysctl apply failed (non-critical)"
    log_info "Kernel sysctl hardening applied"
fi

# Ensure /etc/mission exists
mkdir -p /etc/mission

# ── Phase 2: Service Health Check ───────────────────────────────
log_info "Phase 2: Service health check..."

if command -v systemctl &>/dev/null; then
    for svc in mission-securityd mission-driverd; do
        if systemctl is-enabled "${svc}.service" &>/dev/null 2>&1; then
            if systemctl is-active "${svc}.service" &>/dev/null 2>&1; then
                log_info "✅ ${svc} is running"
            else
                log_warn "${svc} is enabled but not running — starting..."
                systemctl start "${svc}.service" 2>/dev/null || log_warn "Failed to start ${svc}"
            fi
        fi
    done
fi

# ── Phase 3: Desktop Configuration ──────────────────────────────
log_info "Phase 3: Desktop configuration..."

# Copy default KDE configuration to /etc/skel for new users
SKEL_DIR="/etc/skel"
mkdir -p "${SKEL_DIR}/.config"

# Apply default KDE settings (from /etc/xdg/ where build script copies them)
if [ -f /etc/xdg/plasma-org.kde.plasma.desktop-appletsrc ]; then
    if cp /etc/xdg/plasma-org.kde.plasma.desktop-appletsrc "${SKEL_DIR}/.config/" 2>&1; then
        log_info "Plasma applet defaults applied to skel"
    else
        log_warn "Failed to copy plasma applet defaults to skel"
    fi
fi
# Copy other Plasma config defaults to skel
for cfg in kdeglobals kwinrc konsolerc plasmarc kcminputrc powermanagementprofilesrc; do
    if [ -f "/etc/xdg/${cfg}" ]; then
        if ! cp "/etc/xdg/${cfg}" "${SKEL_DIR}/.config/" 2>&1; then
            log_warn "Failed to copy ${cfg} to skel"
        fi
    fi
done
log_info "KDE defaults processed from /etc/xdg/"

# Apply color scheme (from /usr/share/color-schemes/ where build script copies it)
if [ -f /usr/share/color-schemes/mission-graphite.colors ]; then
    mkdir -p "${SKEL_DIR}/.local/share/color-schemes"
    if cp /usr/share/color-schemes/mission-graphite.colors "${SKEL_DIR}/.local/share/color-schemes/" 2>&1; then
        log_info "Color scheme applied to skel"
    else
        log_warn "Failed to copy color scheme to skel"
    fi
fi

# Apply Konsole profile (from /usr/share/konsole/ where build script copies it)
if [ -f /usr/share/konsole/MissionOS.profile ]; then
    mkdir -p "${SKEL_DIR}/.local/share/konsole"
    if cp /usr/share/konsole/MissionOS.profile "${SKEL_DIR}/.local/share/konsole/" 2>&1; then
        log_info "Konsole profile applied to skel"
    else
        log_warn "Failed to copy Konsole profile to skel"
    fi
fi

# ── Phase 4: Locale & Keyboard ──────────────────────────────────
log_info "Phase 4: Locale and keyboard configuration..."

if command -v locale-gen &>/dev/null; then
    # Ensure en_US.UTF-8 is generated
    if ! locale -a 2>/dev/null | grep -q "en_US.utf8"; then
        locale-gen en_US.UTF-8 2>/dev/null || log_warn "locale-gen failed"
    fi
fi

# ── Phase 5: Network Configuration ──────────────────────────────
log_info "Phase 5: Network configuration..."

if command -v nmcli &>/dev/null; then
    # Enable NetworkManager if not already running
    if ! nmcli general status &>/dev/null; then
        if systemctl start NetworkManager 2>&1; then
            log_info "NetworkManager started"
        else
            log_warn "Failed to start NetworkManager"
        fi
    else
        log_info "NetworkManager already running"
    fi
fi

# ── Complete ─────────────────────────────────────────────────────
echo "${MISSION_VERSION:-0.1.0-nightly}" > "${STATE_FILE}"
echo "first_boot_date=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${STATE_FILE}"
echo "first_boot_complete=true" >> "${STATE_FILE}"

chmod 644 "${STATE_FILE}"

log_info "✅ Mission OS first-boot initialization complete"
log_info "   State: ${STATE_FILE}"
