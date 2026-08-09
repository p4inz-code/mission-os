#!/usr/bin/env python3
# Mission OS — Calamares "mission-cleanup" Module
#
# Removes live-environment leftovers from the installed system so the first
# boot lands on a clean SDDM login prompt instead of inheriting the live
# session's state (P15/P16 report, Finding 2). With a live-rootfs copy install
# (Calamares squashfs unpack or the rsync-based harness), the installed system
# otherwise contains:
#
#   - the Calamares installer itself (/usr/bin/calamares, /etc/calamares)
#   - SDDM autologin for the live user (/etc/sddm.conf [Autologin])
#   - the calamares-desktop-icon.desktop autostart entry
#   - a saved Plasma session that re-opens the installer window on first boot
#
# This module runs in the exec phase AFTER the `packages` step (see
# settings.conf) so the Mission OS packages are already installed when the
# cleanup happens.
#
# Package removal is intentionally performed with `dpkg --remove` rather than
# `apt-get remove`: removing installed packages needs no repository index and
# no network, so the cleanup works identically for online and offline installs.
#
# This module is a Calamares Python job: the target root is read from
# libcalamares global storage (`rootMountPoint`) and target commands run
# through `libcalamares.utils.target_env_call()` so they execute inside the
# target chroot. For standalone functional testing (no Calamares runtime),
# the CALAMARES_ROOT environment variable and subprocess-with-cwd fallback
# are used instead.
#
# Security:
#   - No secrets are stored in plaintext
#   - MISSION_ALLOW_UNAUTHORIZED is never set
#   - All removals are limited to Calamares/live-session artifacts
#   - Failures are logged and non-fatal (the installer may still succeed)

import os
import re
import shutil
import subprocess
import sys

try:
    import libcalamares
    HAVE_LIBCALAMARES = True
except ImportError:
    HAVE_LIBCALAMARES = False

# Calamares packages installed from the live system's package list
# (build-nightly.sh config/package-lists/mission-desktop.list.chroot).
CALAMARES_PACKAGES = ["calamares", "calamares-settings-debian"]

AUTOSTART_DIRS = [
    "etc/xdg/autostart",          # system-wide autostart (live overlay)
    "usr/share/autostart",        # packaged autostart
]

# Per-user live-session state that must not carry into a fresh install.
# Note the leading dots: these live in the user's hidden config/data dirs.
SESSION_ARTIFACTS = [
    ".local/share/ksmserver",     # saved Plasma session (directory)
    ".config/ksmserverrc",        # session-restore setting (file)
]


def _root_mount_point():
    """Return the target root mount point (Calamares global storage, or the
    CALAMARES_ROOT env var when running the standalone test harness)."""
    if HAVE_LIBCALAMARES:
        rmp = libcalamares.globalstorage.value("rootMountPoint")
        if rmp:
            return rmp
    return os.environ.get("CALAMARES_ROOT", "/target")


def _target_env_call(cmd):
    """Run a command inside the target chroot (Calamares API), or with
    cwd=root in the standalone harness. Returns the exit code."""
    if HAVE_LIBCALAMARES:
        return libcalamares.utils.target_env_call(cmd)
    try:
        return subprocess.run(cmd, cwd=_root_mount_point(), capture_output=True).returncode
    except OSError as e:
        print(f"[mission-cleanup] WARNING: cannot run {cmd[0]}: {e}", file=sys.stderr)
        return 127


def run():
    """Main entry point called by Calamares."""
    root = _root_mount_point()

    if not os.path.isdir(root):
        print(f"[mission-cleanup] WARNING: Root mount point {root} not found, skipping")
        return None

    print("[mission-cleanup] Removing live-environment leftovers from installed system...")

    _remove_calamares_packages(root)
    _remove_calamares_config(root)
    _remove_autostart_entries(root)
    _strip_sddm_autologin(root)
    _remove_saved_sessions(root)

    print("[mission-cleanup] Live-environment cleanup complete (all steps done)")
    return None


def _remove_calamares_packages(root):
    """Uninstall the Calamares packages from the target (offline-safe dpkg)."""
    if HAVE_LIBCALAMARES:
        present = libcalamares.utils.target_env_call(["dpkg", "-s", "calamares"])
    else:
        try:
            present = subprocess.run(
                ["dpkg", "-s", "calamares"],
                cwd=root,
                capture_output=True,
                check=False,
            ).returncode
        except OSError as e:
            print(f"[mission-cleanup] WARNING: dpkg unavailable ({e}); "
                  "skipping package removal", file=sys.stderr)
            return
    if present != 0:
        # Never installed by this media — nothing to remove, no warning.
        return
    rc = _target_env_call(["dpkg", "--remove", "--force-depends", *CALAMARES_PACKAGES])
    if rc != 0:
        print(
            f"[mission-cleanup] WARNING: dpkg removal failed (exit {rc})",
            file=sys.stderr,
        )
    else:
        print("[mission-cleanup]   Removed Calamares packages (dpkg --remove)")


def _remove_calamares_config(root):
    """Remove /etc/calamares and the shared Calamares module/branding data."""
    for path in ("etc/calamares", "usr/share/calamares"):
        full = os.path.join(root, path)
        if os.path.isdir(full):
            shutil.rmtree(full, ignore_errors=True)
            print(f"[mission-cleanup]   Removed {path}/")
    # Any desktop launcher the packages may have left behind.
    apps = os.path.join(root, "usr/share/applications")
    if os.path.isdir(apps):
        for name in os.listdir(apps):
            if name.startswith("calamares"):
                os.remove(os.path.join(apps, name))
                print(f"[mission-cleanup]   Removed applications/{name}")


def _remove_autostart_entries(root):
    """Remove Calamares autostart .desktop entries (system-wide + all homes)."""
    targets = [os.path.join(root, d) for d in AUTOSTART_DIRS]
    targets += [
        os.path.join(root, "home", user, ".config", "autostart")
        for user in _list_users(root)
    ]
    for directory in targets:
        if not os.path.isdir(directory):
            continue
        for name in os.listdir(directory):
            if name.startswith("calamares"):
                os.remove(os.path.join(directory, name))
                print(f"[mission-cleanup]   Removed autostart/{name}")


def _strip_sddm_autologin(root):
    """Remove any [Autologin] section from the target SDDM configuration."""
    candidates = ["etc/sddm.conf"]
    confd = os.path.join(root, "etc/sddm.conf.d")
    if os.path.isdir(confd):
        candidates += [os.path.join("etc/sddm.conf.d", name)
                       for name in sorted(os.listdir(confd))
                       if name.endswith(".conf")]
    for rel in candidates:
        full = os.path.join(root, rel)
        if not os.path.isfile(full):
            continue
        try:
            with open(full, "r", encoding="utf-8", errors="replace") as f:
                lines = f.readlines()
        except OSError as e:
            print(f"[mission-cleanup] WARNING: cannot read {rel}: {e}", file=sys.stderr)
            continue
        kept = []
        in_autologin = False
        changed = False
        for line in lines:
            stripped = line.strip()
            if re.match(r"^\[Autologin\]", stripped, re.IGNORECASE):
                in_autologin = True
                changed = True
                continue
            if in_autologin:
                # Drop the ENTIRE section (header + all keys) until the next
                # section header — same behavior as the shell awk cleanup.
                if stripped.startswith("["):
                    in_autologin = False
                else:
                    continue
            kept.append(line)
        if not changed:
            continue
        try:
            with open(full, "w", encoding="utf-8") as f:
                f.writelines(kept)
            print(f"[mission-cleanup]   Stripped [Autologin] from {rel}")
        except OSError as e:
            print(f"[mission-cleanup] WARNING: cannot write {rel}: {e}", file=sys.stderr)


def _remove_saved_sessions(root):
    """Remove saved Plasma session data copied over from the live rootfs."""
    for user in _list_users(root):
        home = os.path.join(root, "home", user)
        for artifact in SESSION_ARTIFACTS:
            full = os.path.join(home, artifact)
            if os.path.isdir(full):
                shutil.rmtree(full, ignore_errors=True)
                print(f"[mission-cleanup]   Removed ~{user}/{artifact}/")
            elif os.path.isfile(full):
                os.remove(full)
                print(f"[mission-cleanup]   Removed ~{user}/{artifact}")


def _list_users(root):
    """Return the usernames under the target /home (live-copied or created)."""
    home = os.path.join(root, "home")
    if not os.path.isdir(home):
        return []
    return [name for name in sorted(os.listdir(home))
            if os.path.isdir(os.path.join(home, name))]
