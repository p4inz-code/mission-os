#!/bin/bash
# Mission OS — Nightly version metadata generator
#
# Generates a structured version metadata file for Nightly ISO builds.
# Sources the VERSION file and enriches it with CI/build context.
#
# Usage:
#   ./build/nightly-version.sh [--output <path>] [--commit <sha>]
#
# Output: JSON file with version metadata
#
# Security:
# - No secrets are embedded in the output
# - Version string is controlled by the VERSION file (not arbitrary input)
# - Build metadata is informational only — not trusted for authorization

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSION_FILE="${PROJECT_ROOT}/VERSION"

# Default output path
OUTPUT="${PROJECT_ROOT}/build/nightly-version.json"
COMMIT_SHA=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)
            OUTPUT="$2"
            shift 2
            ;;
        --commit)
            COMMIT_SHA="$2"
            shift 2
            ;;
        *)
            echo "Usage: $0 [--output <path>] [--commit <sha>]"
            exit 1
            ;;
    esac
done

# Read version from VERSION file
if [[ ! -f "${VERSION_FILE}" ]]; then
    echo "ERROR: VERSION file not found at ${VERSION_FILE}" >&2
    exit 1
fi

MISSION_VERSION="$(cat "${VERSION_FILE}" | tr -d '[:space:]')"

if [[ -z "${MISSION_VERSION}" ]]; then
    echo "ERROR: VERSION file is empty" >&2
    exit 1
fi

# Detect CI build metadata
BUILD_DATE="$(date -u +%Y%m%d)"
BUILD_TIME="$(date -u +%H%M%S)"
BUILD_ID="nightly-${BUILD_DATE}-${BUILD_TIME}"

# Use provided commit SHA or try to detect from CI/git
if [[ -z "${COMMIT_SHA}" ]]; then
    if command -v git &>/dev/null && git rev-parse --git-dir &>/dev/null 2>&1; then
        COMMIT_SHA="$(git rev-parse HEAD 2>/dev/null || true)"
    fi
fi

# Detect architecture
ARCH="${ARCH:-amd64}"

# Detect base Debian version.
# auto/config uses `--distribution stable`, so the metadata must describe
# the TARGET distribution, not the build host. DEBIAN_VERSION may be
# overridden by the caller; otherwise a static fallback is used. Keep this
# in sync with auto/config's --distribution setting (current stable: Debian 13).
DEBIAN_VERSION="${DEBIAN_VERSION:-13}"

# Generate metadata JSON
cat > "${OUTPUT}" <<EOF
{
  "mission_os_version": "${MISSION_VERSION}",
  "channel": "nightly",
  "build_date": "${BUILD_DATE}",
  "build_time": "${BUILD_TIME}",
  "build_id": "${BUILD_ID}",
  "commit_sha": "${COMMIT_SHA}",
  "architecture": "${ARCH}",
  "debian_version": "${DEBIAN_VERSION}",
  "build_tool": "live-build",
  "is_nightly": true,
  "is_release": false,
  "is_debug": false
}
EOF

echo "✅ Nightly version metadata generated: ${OUTPUT}"
echo "   Version: ${MISSION_VERSION}"
echo "   Build:   ${BUILD_ID}"
echo "   Commit:  ${COMMIT_SHA:-unknown}"
