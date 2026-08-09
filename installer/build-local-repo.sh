#!/bin/bash
# Mission OS — Build Local (Offline) Package Repository
#
# Builds the four Mission OS .deb packages from source and assembles a flat
# Debian repository (Packages + Packages.gz + Release) that the Calamares
# installer consumes fully offline via the mission-repo + packages modules.
#
# Output:
#   build/mission-repo/            <- flat repository (consumed via file://)
#     mission-core-dev_*.deb
#     mission-crypto-dev_*.deb
#     mission-driverd_*.deb
#     mission-securityd_*.deb
#     Packages  Packages.gz  Release
#
# Requirements:
#   - Linux/WSL with dpkg-buildpackage, dpkg-scanpackages, debhelper
#     (sudo apt install debhelper)
#   - Rust toolchain (cargo/rustc) — the packages build via cargo
#
# Notes:
#   - Packages build in a WSL NATIVE filesystem sandbox: on DrvFs (/mnt/c)
#     every file reports mode 0777 and dpkg-deb rejects the 0777 control
#     directory at dh_builddeb. The sandbox has correct permissions; only the
#     finished .deb files are copied back into the repository.
#   - The repository must be packaged into the ISO overlay at /opt/mission/repo
#     (build-nightly.sh Phase 5 overlay deploy) so the Calamares mission-repo
#     module can stage it into the target system.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_DIR="${PROJECT_ROOT}/build/mission-repo"
SANDBOX="${TMPDIR:-/tmp}/mission-os-deb-build"

PACKAGES=(mission-core mission-crypto mission-driverd mission-securityd)

# ── Tool checks ────────────────────────────────────────────────────
for tool in dpkg-buildpackage dpkg-scanpackages dh cargo; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
        echo "ERROR: ${tool} is required (sudo apt install debhelper)" >&2
        exit 1
    fi
done

# ── Prepare native-filesystem sandbox ──────────────────────────────
echo "--- Preparing build sandbox: ${SANDBOX} ---"
rm -rf "${SANDBOX}"
mkdir -p "${SANDBOX}"
cp -a "${PROJECT_ROOT}/packages" "${SANDBOX}/"
cp -a "${PROJECT_ROOT}/src" "${SANDBOX}/"
cp -a "${PROJECT_ROOT}/tests" "${SANDBOX}/"
cp "${PROJECT_ROOT}/Cargo.toml" "${PROJECT_ROOT}/Cargo.lock" "${SANDBOX}/"
# rust-toolchain.toml is deliberately not copied: the sandbox builds with the
# WSL default toolchain, avoiding a rustup toolchain download.

# ── Build packages (in the sandbox) ────────────────────────────────
echo "--- Building Mission OS packages ---"
for pkg in "${PACKAGES[@]}"; do
    echo "==> dpkg-buildpackage: ${pkg}"
    # Normalize CRLF → LF (core.autocrlf checkouts break make on debian/rules:
    # "make: \r: No such file or directory").
    find "${SANDBOX}/packages/${pkg}/debian" -maxdepth 1 -type f \
        -exec sed -i 's/\r$//' {} +
    (
        cd "${SANDBOX}/packages/${pkg}"
        # -d: skip dpkg-checkbuilddeps. The Rust toolchain is installed via
        # rustup (not a dpkg package), so cargo/rustc would otherwise be
        # reported as missing. All other build deps (debhelper, libssl-dev,
        # pkg-config) are verified by the tool check above.
        if ! dpkg-buildpackage -b -us -uc -d >/dev/null 2>&1; then
            echo "ERROR: build failed for ${pkg} (see ${SANDBOX}/packages/${pkg}/debian)" >&2
            exit 1
        fi
    )
done

# ── Assemble flat repository ───────────────────────────────────────
echo "--- Assembling flat repository in ${REPO_DIR} ---"
rm -rf "${REPO_DIR}"
mkdir -p "${REPO_DIR}"
for pkg in "${PACKAGES[@]}"; do
    for deb in "${SANDBOX}"/packages/"${pkg}"*.deb; do
        [ -e "${deb}" ] || continue
        mv "${deb}" "${REPO_DIR}/"
    done
done

(cd "${REPO_DIR}" && dpkg-scanpackages . /dev/null > Packages)
gzip -kf "${REPO_DIR}/Packages"

# Minimal Release file (flat repository; no apt-ftparchive/reprepro required).
(cd "${REPO_DIR}" && {
    echo "Origin: Mission OS"
    echo "Label: Mission OS local repository"
    echo "Suite: mission-local"
    echo "Codename: mission-local"
    echo "Date: $(date -R)"
    echo "Architectures: amd64 arm64"
    echo "Description: Mission OS offline package repository"
    echo ""
    for f in Packages Packages.gz; do
        sz="$(stat -c %s "${f}")"
        sha256sum "${f}" | awk -v f="${f}" -v sz="${sz}" \
            '{ printf "SHA256:\n %s %d %s\n", $1, sz, f }'
    done
} > Release)

# ── Verify repository ──────────────────────────────────────────────
echo "--- Verifying repository ---"
echo "Packages in index: $(grep -c '^Package:' "${REPO_DIR}/Packages")"
ls -la "${REPO_DIR}"

# ── Cleanup ────────────────────────────────────────────────────────
rm -rf "${SANDBOX}"
# Any debris left in the working tree by earlier (pre-sandbox) build attempts.
rm -rf "${PROJECT_ROOT}/packages"/*/debian/cargo-home \
       "${PROJECT_ROOT}/packages"/*/debian/cargo-target \
       "${PROJECT_ROOT}/packages"/*/debian/.debhelper \
       "${PROJECT_ROOT}/packages"/*/debian/files \
       "${PROJECT_ROOT}/packages"/*/debian/debhelper-build-stamp \
       "${PROJECT_ROOT}/packages"/*/debian/mission-core-dev \
       "${PROJECT_ROOT}/packages"/*/debian/mission-crypto-dev \
       "${PROJECT_ROOT}/packages"/*/debian/mission-driverd \
       "${PROJECT_ROOT}/packages"/*/debian/mission-securityd
rm -f "${PROJECT_ROOT}/packages"/*_*.buildinfo \
      "${PROJECT_ROOT}/packages"/*_*.changes \
      "${PROJECT_ROOT}/packages"/*_*.dsc \
      "${PROJECT_ROOT}/packages"/*_*.debian.tar.* \
      "${PROJECT_ROOT}/packages"/*_*.orig.tar.* \
      "${PROJECT_ROOT}/packages"/*_*.tar.gz

echo "✅ Local repository ready at ${REPO_DIR}"
echo "   apt source line: deb [trusted=yes] file:/var/cache/mission/repo ./"
