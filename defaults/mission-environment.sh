#!/bin/bash
# Mission OS — Default Environment Variables
#
# Installed to /etc/profile.d/mission-environment.sh
# These are environment defaults for all users on Mission OS.

# ── Editor ───────────────────────────────────────────────────────
export EDITOR=nano
export VISUAL=nano

# ── Pager ────────────────────────────────────────────────────────
export PAGER=less
export LESS=-FRSX

# ── History ──────────────────────────────────────────────────────
export HISTSIZE=5000
export HISTFILESIZE=10000
export HISTCONTROL=ignoreboth:erasedups
export HISTTIMEFORMAT="%F %T "

# ── Terminal ─────────────────────────────────────────────────────
export TERM=xterm-256color

# ── XDG Base Directory ──────────────────────────────────────────
export XDG_CONFIG_HOME="${HOME}/.config"
export XDG_DATA_HOME="${HOME}/.local/share"
export XDG_CACHE_HOME="${HOME}/.cache"
export XDG_STATE_HOME="${HOME}/.local/state"

# ── Qt / KDE ─────────────────────────────────────────────────────
export QT_QPA_PLATFORMTHEME=qt6ct
export QT_STYLE_OVERRIDE=breeze
export QT_AUTO_SCREEN_SCALE_FACTOR=1

# ── Wayland ──────────────────────────────────────────────────────
export MOZ_ENABLE_WAYLAND=1
export QT_QPA_PLATFORM=wayland
export CLUTTER_BACKEND=wayland
export GDK_BACKEND=wayland
export SDL_VIDEODRIVER=wayland

# ── Language / Locale ────────────────────────────────────────────
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export LANGUAGE=en_US:en

# ── Security ─────────────────────────────────────────────────────
# NEVER set MISSION_ALLOW_UNAUTHORIZED in a profile file!
# This must ONLY be set explicitly in development environments.
