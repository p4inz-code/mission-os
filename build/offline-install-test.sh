#!/bin/bash
# Mission OS — Offline Install Validation (QEMU, networking DISABLED)
#
# Replicates the Calamares module sequence executed by the installer:
#   partition -> users -> mission-os -> grubcfg -> bootloader ->
#   networkcfg -> hwclock -> services-systemd -> mission-repo -> packages
#
# Runs INSIDE the live ISO environment (as root) against /dev/vda.
# Proves the Mission OS packages install from the local file:// repository
# staged at /opt/mission/repo with NO network connectivity.
set -euo pipefail

LOG=/tmp/offline-install.log
exec > >(tee "${LOG}") 2>&1
echo "=== MISSION OS OFFLINE INSTALL TEST (network disabled) ==="
date -u

# Sanity: confirm there is NO network interface at all
echo "--- Interfaces present (expect none or only lo) ---"
ip -o link show | awk -F': ' '{print $2}' || true
if ip -o link show | grep -qE '^[0-9]+: (eth|enp|ens|wlan)'; then
    echo "ERROR: a network interface exists — offline test invalid" >&2
    exit 1
fi

DISK=/dev/vda
echo "--- Partitioning ${DISK} (GPT: EFI + root ext4) ---"
parted -s "${DISK}" mklabel gpt
parted -s "${DISK}" mkpart primary fat32 1MiB 513MiB
parted -s "${DISK}" set 1 esp on
parted -s "${DISK}" mkpart primary ext4 513MiB 100%
partprobe "${DISK}" || true
sleep 2

echo "--- Creating filesystems ---"
mkfs.fat -F32 -n MISSION_OS "${DISK}1"
mkfs.ext4 -F -L mission_root "${DISK}2"

echo "--- Mounting target ---"
mount "${DISK}2" /mnt
mkdir -p /mnt/boot/efi
mount "${DISK}1" /mnt/boot/efi

echo "--- Copying live rootfs to target (rsync) ---"
rsync -aAXH \
    --exclude='/dev/*' --exclude='/proc/*' --exclude='/sys/*' \
    --exclude='/tmp/*' --exclude='/run/*' --exclude='/mnt/*' \
    --exclude='/media/*' --exclude='/lost+found' \
    / /mnt/ || echo "WARNING: rsync reported non-zero (continuing)"

# Bind-mount virtual filesystems for chroot
for d in dev proc sys run; do
    mount --bind "/${d}" "/mnt/${d}"
done

echo "--- Staging local repository into target (/var/cache/mission/repo) ---"
mkdir -p /mnt/var/cache/mission/repo
cp -a /opt/mission/repo/. /mnt/var/cache/mission/repo/
ls -la /mnt/var/cache/mission/repo/

echo "--- Configuring apt: ONLY the local file:// repository (offline) ---"
rm -f /mnt/etc/apt/sources.list
rm -rf /mnt/etc/apt/sources.list.d
mkdir -p /mnt/etc/apt/sources.list.d
cat > /mnt/etc/apt/sources.list.d/mission-local.list <<'EOF'
deb [trusted=yes] file:/var/cache/mission/repo ./
EOF

echo "--- apt-get update (local repo only) ---"
chroot /mnt apt-get update

echo "--- Verifying packages are resolvable locally ---"
chroot /mnt apt-cache policy mission-core-dev mission-crypto-dev mission-driverd mission-securityd

echo "--- Installing Mission OS packages (OFFLINE) ---"
chroot /mnt apt-get install -y --no-install-recommends \
    mission-core-dev mission-crypto-dev mission-driverd mission-securityd

echo "--- Verifying installed packages ---"
chroot /mnt dpkg -l | grep -E 'mission-(core|crypto|driverd|securityd)' || true
chroot /mnt dpkg -s mission-driverd | grep -E '^(Package|Status|Version)'
chroot /mnt dpkg -s mission-securityd | grep -E '^(Package|Status|Version)'

echo "--- Enabling services (as installer's services-systemd step) ---"
chroot /mnt systemctl enable mission-securityd mission-driverd mission-first-boot 2>/dev/null || true
chroot /mnt systemctl enable sddm 2>/dev/null || true
# Boot target: use the chroot-relative destination (the old /mnt/etc/... path
# resolved to <target>/mnt/etc inside the chroot and silently no-opped).
chroot /mnt bash -c 'mkdir -p /etc/systemd/system && ln -sf /usr/lib/systemd/system/graphical.target /etc/systemd/system/default.target' \
    || echo "WARNING: could not set graphical default.target"

echo "--- Cleaning live-environment leftovers (P15/P16 Finding 2) ---"
# Remove the Calamares installer, its autostart entry, SDDM autologin for the
# live user, and the saved Plasma session carried over from the live rootfs so
# the installed system first-boots to a clean SDDM login prompt. dpkg --remove
# needs no repository or network (works fully offline).
chroot /mnt dpkg --remove --force-depends calamares calamares-settings-debian 2>&1 | tail -3 \
    || echo "WARNING: dpkg calamares removal reported non-zero (continuing — possibly not installed by this media)"
rm -rf /mnt/etc/calamares /mnt/usr/share/calamares
rm -f /mnt/etc/xdg/autostart/calamares-desktop-icon.desktop \
      /mnt/usr/share/autostart/calamares-desktop-icon.desktop \
      /mnt/usr/share/applications/calamares.desktop
if [ -f /mnt/etc/sddm.conf ]; then
    # Drop the [Autologin] section (User/Session) copied from the live session.
    awk 'BEGIN{s=0} /^\[Autologin\]/{s=1; next} s && /^\[/{s=0} !s' \
        /mnt/etc/sddm.conf > /mnt/etc/sddm.conf.tmp
    mv /mnt/etc/sddm.conf.tmp /mnt/etc/sddm.conf
fi
rm -rf /mnt/home/*/.local/share/ksmserver
rm -f /mnt/home/*/.config/ksmserverrc \
      /mnt/home/*/.config/autostart/calamares-desktop-icon.desktop
echo "✅ Live-environment leftovers removed"

echo "--- Installing GRUB bootloader (UEFI) ---"
chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi \
    --bootloader-id=MISSION_OS || true
# Ensure the removable-media fallback path exists so OVMF can boot the
# disk even without a persistent NVRAM entry.
mkdir -p /mnt/boot/efi/EFI/BOOT
cp -f /mnt/boot/efi/EFI/MISSION_OS/grubx64.efi /mnt/boot/efi/EFI/BOOT/BOOTX64.EFI 2>/dev/null || \
    cp -f /usr/lib/grub/x86_64-efi/*.efi /mnt/boot/efi/EFI/BOOT/BOOTX64.EFI 2>/dev/null || true
ls -la /mnt/boot/efi/EFI/BOOT/ 2>/dev/null || echo "WARNING: EFI/BOOT not populated"

echo "--- Writing fstab with UUIDs ---"
ROOT_UUID=$(chroot /mnt blkid -s UUID -o value /dev/vda2)
EFI_UUID=$(chroot /mnt blkid -s UUID -o value /dev/vda1)
cat > /mnt/etc/fstab <<EOF
UUID=${ROOT_UUID}  /  ext4  errors=remount-ro  0 1
UUID=${EFI_UUID}   /boot/efi  vfat  umask=0077  0 1
EOF
cat /mnt/etc/fstab

echo "--- Setting hostname + root password ---"
echo "mission-os" > /mnt/etc/hostname
chroot /mnt bash -c "echo 'root:mission' | chpasswd"

echo "=== OFFLINE INSTALL TEST COMPLETE ==="
echo "Installed packages:"
chroot /mnt dpkg -l | grep mission || true
echo "Install log saved at ${LOG}"
