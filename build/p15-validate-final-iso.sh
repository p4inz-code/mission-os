#!/bin/bash
# Mission OS — Final ISO validation (polkitd repo + SHA256 + boot content)
set -uo pipefail

# Run from the repository root; ISO and evidence dir are overridable.
ISO="${MISSION_ISO:-build/images/mission-os-0.1.0-nightly.20260730-amd64.hybrid.iso}"
EVID="${MOS_EVID:-$HOME/mos-audit-evidence/final-iso}"
mkdir -p "${EVID}"

echo "--- ISO exists? ---"
ls -la "${ISO}" 2>&1

echo "--- SHA256 recompute vs shipped ---"
sha256sum "${ISO}"
cat "${ISO}.sha256"

echo "--- ISO layout (boot-critical files) ---"
xorriso -indev "${ISO}" -find / -type f 2>/dev/null | grep -E "squashfs|vmlinuz|initrd|grub" | head -10

echo "--- Extract filesystem.squashfs ---"
xorriso -indev "${ISO}" -osirrox on -extract /live/filesystem.squashfs "${EVID}/filesystem.squashfs" 2>&1 | tail -2
ls -la "${EVID}/filesystem.squashfs"

echo "--- Repo inside squashfs: Packages Depends ---"
unsquashfs -cat "${EVID}/filesystem.squashfs" opt/mission/repo/Packages 2>/dev/null | grep -E "^(Package|Depends):" | head -20

echo "--- Repo debs present inside squashfs ---"
unsquashfs -ls "${EVID}/filesystem.squashfs" 2>/dev/null | grep -E "opt/mission/repo/mission-.*\.deb" | head -8

echo "--- polkitd check (expect polkitd, NO policykit-1) ---"
unsquashfs -cat "${EVID}/filesystem.squashfs" opt/mission/repo/Packages 2>/dev/null | grep -c "polkitd"
unsquashfs -cat "${EVID}/filesystem.squashfs" opt/mission/repo/Packages 2>/dev/null | grep -c "policykit-1"

echo "--- mission-first-boot + services inside squashfs ---"
unsquashfs -ls "${EVID}/filesystem.squashfs" 2>/dev/null | grep -E "mission-first-boot|mission-securityd.service|mission-driverd.service" | head -6

echo "DONE"
