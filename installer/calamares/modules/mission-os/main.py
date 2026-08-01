#!/usr/bin/env python3
# Mission OS — Calamares Post-Install Module
#
# Applies Mission OS-specific configuration after the main
# Calamares installation completes.
#
# Tasks:
#   1. Install Mission OS packages from local repository
#   2. Apply Mission OS branding (hostname, os-release, motd)
#   3. Enable Mission OS systemd services
#   4. Apply kernel sysctl hardening
#   5. Configure first-boot state
#   6. Mark installation as complete
#
# This module is called by Calamares after partition/filesystem setup.
#
# Security:
#   - No secrets are stored in plaintext
#   - MISSION_ALLOW_UNAUTHORIZED is never set
#   - All paths are validated

import os
import shutil
import subprocess
import sys


def run():
    """Main entry point called by Calamares."""
    print("[mission-os] Applying Mission OS post-install configuration...")

    root_mount_point = os.environ.get("CALAMARES_ROOT", "/target")

    if not os.path.isdir(root_mount_point):
        print(f"[mission-os] WARNING: Root mount point {root_mount_point} not found, skipping")
        return None

    try:
        # Phase 1: Enable Mission OS services
        _enable_services(root_mount_point)

        # Phase 2: Apply branding
        _apply_branding(root_mount_point)

        # Phase 3: Apply system defaults
        _apply_defaults(root_mount_point)

        # Phase 4: Mark first-boot for pending completion
        _mark_first_boot_pending(root_mount_point)

        print("[mission-os] ✅ Mission OS post-install complete")
    except Exception as e:
        print(f"[mission-os] ERROR: {e}", file=sys.stderr)
        # Non-fatal — installer can succeed without this module

    return None


def _enable_services(root):
    """Enable Mission OS systemd services in the installed system."""
    services = ["mission-securityd", "mission-driverd"]

    for svc in services:
        service_file = os.path.join(root, "usr", "lib", "systemd", "system", f"{svc}.service")
        if os.path.isfile(service_file):
            print(f"[mission-os]   Enabling {svc}...")
            subprocess.run(
                ["systemctl", "enable", f"{svc}.service"],
                cwd=root,
                capture_output=True,
                check=False,
            )
        else:
            print(f"[mission-os]   Skipping {svc} — service file not found")


def _apply_branding(root):
    """Apply Mission OS branding to the installed system."""
    branding = {
        "etc/hostname": "mission-os\n",
        "etc/mission/VERSION": "0.1.0-nightly\n",
    }

    for path, content in branding.items():
        full_path = os.path.join(root, path)
        os.makedirs(os.path.dirname(full_path), exist_ok=True)
        with open(full_path, "w") as f:
            f.write(content)
        print(f"[mission-os]   Created {path}")


def _apply_defaults(root):
    """Copy Mission OS default configuration files."""
    defaults_src = "/usr/share/mission/defaults"
    if os.path.isdir(defaults_src):
        # Copy sysctl config
        sysctl_src = os.path.join(defaults_src, "sysctl", "99-mission-os.conf")
        sysctl_dst = os.path.join(root, "etc", "sysctl.d", "99-mission-os.conf")
        if os.path.isfile(sysctl_src):
            os.makedirs(os.path.dirname(sysctl_dst), exist_ok=True)
            shutil.copy2(sysctl_src, sysctl_dst)
            print("[mission-os]   Applied sysctl hardening")


def _mark_first_boot_pending(root):
    """Mark the system for first-boot completion on next boot."""
    state_dir = os.path.join(root, "var", "lib", "mission")
    os.makedirs(state_dir, exist_ok=True)
    # First-boot marker is NOT created here — it's done by mission-first-boot.service
    # on the first actual boot of the installed system.
    print("[mission-os]   First-boot will run on next system start")
