#!/bin/bash
# Mission OS P15/P16 installed-system verification.
# Runs INSIDE the booted VM as root. Output goes to /mnt/v/verify-results.txt
# (an attached FAT evidence disk, mounted by the caller).
R=/mnt/v/verify-results.txt
{
echo "=== P15/P16 INSTALLED-SYSTEM VERIFICATION $(date -u) ==="
echo "=== A. Kernel booted ==="
uname -a
echo
echo "=== B. System state ==="
systemctl is-system-running 2>&1
echo
echo "=== C. mission-first-boot ==="
echo "-- is-active --"; systemctl is-active mission-first-boot 2>&1
echo "-- is-enabled --"; systemctl is-enabled mission-first-boot 2>&1
echo "-- status --"; systemctl status mission-first-boot --no-pager -l 2>&1 | head -25
echo "-- state file --"; cat /var/lib/mission/first-boot-complete 2>&1
echo "-- journal tail --"; journalctl -u mission-first-boot --no-pager 2>&1 | tail -25
echo
echo "=== D. mission services ==="
for s in mission-securityd mission-driverd; do
  echo "-- $s --"
  echo "active: $(systemctl is-active $s 2>&1)"
  echo "enabled: $(systemctl is-enabled $s 2>&1)"
  systemctl status $s --no-pager -l 2>&1 | head -18
  echo
done
echo
echo "=== E. Mission packages installed ==="
dpkg -l | grep -E "mission-(core|crypto|driverd|securityd)"
echo
echo "=== F. polkit packages ==="
dpkg -l | grep -E "polkitd|policykit"
echo
echo "=== G. fstab ==="
cat /etc/fstab
echo
echo "=== H. Networking (expect loopback only) ==="
echo "-- ip link --"
ip -o link show 2>&1
echo "-- ip addr --"
ip -o addr show 2>&1
echo "-- ip route --"
ip route show 2>&1
echo
echo "=== I. FAILED services ==="
systemctl --failed --no-pager -l 2>&1
echo "--- end failed list ---"
echo
echo "=== J. Boot journal errors (this boot) ==="
journalctl -b --no-pager -p err 2>&1 | head -60
echo
echo "=== K. Target / display manager / hostname ==="
echo "default.target: $(readlink /etc/systemd/system/default.target 2>&1)"
echo "sddm active: $(systemctl is-active sddm 2>&1)"
echo "hostname: $(cat /etc/hostname 2>&1)"
echo
echo "=== VERIFICATION COMPLETE ==="
} > "$R" 2>&1
sync
echo "DONE" >> "$R"
sync
