#!/bin/bash
# Mission OS — Offline Install RESUME (after policykit-1 -> polkitd fix)
# Runs in the live VM where the first attempt already: partitioned /dev/vda,
# created filesystems, rsync'd the rootfs to /mnt, bound /dev /proc /sys /run,
# and staged the OLD repo. This script re-stages the FIXED repo from the
# delivery disk (/media/repo) and completes the installation.
set -euo pipefail

LOG=/tmp/resume-install.log
exec > >(tee "${LOG}") 2>&1
echo "=== MISSION OS OFFLINE INSTALL RESUME (fixed repo) ==="
date -u

echo "--- Network re-check (must be loopback-only) ---"
ip -o link show | awk -F': ' '{print $2}'

echo "--- Re-staging FIXED repo into target ---"
mkdir -p /mnt/var/cache/mission/repo
rm -f /mnt/var/cache/mission/repo/*
cp -a /media/repo/. /mnt/var/cache/mission/repo/
ls -la /mnt/var/cache/mission/repo/

echo "--- apt-get update (local file:// repo only) ---"
chroot /mnt apt-get update

echo "--- Installing Mission OS packages (OFFLINE) ---"
chroot /mnt apt-get install -y --no-install-recommends \
    mission-core-dev mission-crypto-dev mission-driverd mission-securityd

echo "--- Verifying installed packages ---"
chroot /mnt dpkg -l | grep -E 'mission-(core|crypto|driverd|securityd)' || true
chroot /mnt dpkg -s mission-driverd | grep -E '^(Package|Status|Version)'
chroot /mnt dpkg -s mission-securityd | grep -E '^(Package|Status|Version)'

echo "--- Enabling services (services-systemd step) ---"
chroot /mnt systemctl enable mission-securityd mission-driverd mission-first-boot 2>/dev/null || true
# Boot target: previous code used `chroot /mnt ln -sf ... /mnt/etc/...` which
# resolved to <target>/mnt/etc inside the chroot and silently no-opped
# (P15/P16 review finding). Use the chroot-relative destination and report
# failure loudly instead of swallowing it.
chroot /mnt bash -c 'mkdir -p /etc/systemd/system && ln -sf /usr/lib/systemd/system/graphical.target /etc/systemd/system/default.target' \
    || echo "WARNING: could not set graphical default.target"

echo "--- Cleaning live-environment leftovers (P15/P16 Finding 2) ---"
# The installed rootfs is copied from the live system, so it carries the
# Calamares installer, its autostart entry, SDDM autologin for the live user,
# and a saved Plasma session. Remove all of it so first boot lands on a clean
# SDDM login prompt instead of the installer window. dpkg --remove needs no
# repository or network, so this works for offline installs too.
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
mkdir -p /mnt/boot/efi/EFI/BOOT
cp -f /mnt/boot/efi/EFI/MISSION_OS/grubx64.efi /mnt/boot/efi/EFI/BOOT/BOOTX64.EFI 2>/dev/null || \
    cp -f /usr/lib/grub/x86_64-efi/*.efi /mnt/boot/efi/EFI/BOOT/BOOTX64.EFI 2>/dev/null || true
ls -la /mnt/boot/efi/EFI/BOOT/ 2>/dev/null || echo "WARNING: EFI/BOOT not populated"

echo "--- Writing GRUB config (root grub.cfg + ESP chain files) ---"
# P15 finding: without /boot/grub/grub.cfg the installed disk boots to the
# GRUB rescue prompt. Write it explicitly (same config previously delivered as
# a manual session command in grubcmds.txt), plus 3-line chain configs in BOTH
# candidate ESP bootloader-id directories: the installed grub EFI binaries
# were observed carrying an embedded prefix of /EFI/debian while grub-install
# --bootloader-id=MISSION_OS writes /EFI/MISSION_OS. Covering both locations
# guarantees the ESP bootstrap reaches /boot/grub/grub.cfg.
ROOT_UUID=$(chroot /mnt blkid -s UUID -o value /dev/vda2)
KERNEL=/boot/vmlinuz-6.12.94+deb13-amd64
INITRD=/boot/initrd.img-6.12.94+deb13-amd64
if [[ ! -f "/mnt${KERNEL}" || ! -f "/mnt${INITRD}" ]]; then
    echo "ERROR: kernel/initrd not found in target (/mnt${KERNEL}, /mnt${INITRD}) —" >&2
    echo "       refusing to write a grub.cfg that would boot to the rescue prompt." >&2
    echo "       Update the KERNEL/INITRD variables to the actual kernel version." >&2
    ls /mnt/boot/ >&2 || true
    exit 1
fi
mkdir -p /mnt/boot/grub
cat > /mnt/boot/grub/grub.cfg <<GRUBCFG
set default=0
set timeout=5
insmod part_gpt
insmod ext2
insmod search_fs_uuid
search --no-floppy --fs-uuid --set=root ${ROOT_UUID}
linux ${KERNEL} root=UUID=${ROOT_UUID} ro quiet
initrd ${INITRD}
boot
GRUBCFG
echo "--- /boot/grub/grub.cfg ---"
cat /mnt/boot/grub/grub.cfg

ESP_CHAIN="search.fs_uuid ${ROOT_UUID} root
set prefix=(\$root)/boot/grub
configfile \$prefix/grub.cfg"
for d in debian MISSION_OS; do
    mkdir -p "/mnt/boot/efi/EFI/${d}"
    printf '%s\n' "${ESP_CHAIN}" > "/mnt/boot/efi/EFI/${d}/grub.cfg"
done
echo "--- /boot/efi/EFI/debian/grub.cfg ---"
cat /mnt/boot/efi/EFI/debian/grub.cfg

echo "--- Writing fstab with UUIDs ---"
ROOT_UUID=$(chroot /mnt blkid -s UUID -o value /dev/vda2)
EFI_UUID=$(chroot /mnt blkid -s UUID -o value /dev/vda1)
cat > /mnt/etc/fstab <<EOF
UUID=${ROOT_UUID}  /  ext4  errors=remount-ro  0 1
UUID=${EFI_UUID}   /boot/efi  vfat  umask=0077  0 1
EOF
cat /mnt/etc/fstab

echo "--- Hostname + root password ---"
echo "mission-os" > /mnt/etc/hostname
chroot /mnt bash -c "echo 'root:mission' | chpasswd"

echo "=== RESUME INSTALL COMPLETE ==="
echo "--- Final package list ---"
chroot /mnt dpkg -l | grep mission || true
