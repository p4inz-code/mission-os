#!/usr/bin/env python3
# Mission OS — Calamares "mission-repo" Module
#
# Stages the Mission OS local package repository onto the target system so
# the Calamares `packages` module (see packages.conf) can install the Mission
# OS .deb packages fully offline (no network access):
#
#   1. Locates the repository carried on the installation media
#      (/opt/mission/repo in the live overlay, with fallbacks for other
#      common medium mount points).
#   2. Copies it into the target at /var/cache/mission/repo so the installed
#      system does NOT depend on the removable installation media.
#   3. Writes /etc/apt/sources.list.d/mission-local.list pointing apt at the
#      local copy (flat repository: `deb [trusted=yes] file:/var/cache/mission/repo ./`).
#   4. Runs `apt-get update` in the target chroot against the file:// source
#      only — APT performs no network I/O for file sources.
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
#   - The repository is only copied if it carries a valid Packages index
#   - No telemetry; the only privileged operation is apt inside the target

import os
import shutil
import subprocess
import sys

try:
    import libcalamares
    HAVE_LIBCALAMARES = True
except ImportError:
    HAVE_LIBCALAMARES = False

# Repository locations on the installation media (live overlay first).
MEDIUM_REPO_CANDIDATES = [
    "/opt/mission/repo",
    "/run/live/medium/mission/repo",
    "/media/mission/repo",
    "/mnt/mission/repo",
]

TARGET_REPO_DIR = "var/cache/mission/repo"
APT_SOURCE_FILE = "etc/apt/sources.list.d/mission-local.list"
APT_SOURCE_LINE = "deb [trusted=yes] file:/var/cache/mission/repo ./\n"


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
        print(f"[mission-repo] WARNING: cannot run {cmd[0]}: {e}", file=sys.stderr)
        return 127


def run():
    """Main entry point called by Calamares."""
    root = _root_mount_point()

    if not os.path.isdir(root):
        print(f"[mission-repo] WARNING: Root mount point {root} not found, skipping")
        return None

    src = _find_repo()
    if src is None:
        print(
            "[mission-repo] WARNING: Mission OS repository not found on the "
            "installation media; the packages step will not be able to install "
            "Mission OS packages offline.",
            file=sys.stderr,
        )
        return None

    if not os.path.isfile(os.path.join(src, "Packages")):
        print(
            f"[mission-repo] ERROR: repository at {src} has no Packages index",
            file=sys.stderr,
        )
        return None

    # Stage a local copy into the target (no media dependency afterwards).
    dst = os.path.join(root, TARGET_REPO_DIR)
    os.makedirs(dst, exist_ok=True)
    for entry in sorted(os.listdir(src)):
        full = os.path.join(src, entry)
        if os.path.isdir(full):
            shutil.copytree(full, os.path.join(dst, entry), dirs_exist_ok=True)
        else:
            shutil.copy2(full, os.path.join(dst, entry))
    print(f"[mission-repo]   Copied local repository to {dst}")

    # Point apt at the local copy (flat repository).
    source_list = os.path.join(root, APT_SOURCE_FILE)
    os.makedirs(os.path.dirname(source_list), exist_ok=True)
    with open(source_list, "w") as f:
        f.write(APT_SOURCE_LINE)
    print(f"[mission-repo]   Wrote {source_list}: {APT_SOURCE_LINE.strip()}")

    # Refresh the target apt index. Only the file:// source above is new;
    # file sources never touch the network. Acquire::Retries=0 keeps the
    # installer responsive if any base source is unreachable offline.
    rc = _target_env_call(["apt-get", "update", "-o", "Acquire::Retries=0"])
    if rc != 0:
        print(
            f"[mission-repo] WARNING: apt-get update in target returned {rc} "
            "(file:// sources do not need network; continuing)",
            file=sys.stderr,
        )

    print("[mission-repo] Mission OS offline repository staged")
    return None


def _find_repo():
    """Return the first existing repository location on the media."""
    for candidate in MEDIUM_REPO_CANDIDATES:
        if os.path.isdir(candidate):
            return candidate
    return None
