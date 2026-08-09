#!/bin/bash
# Launch the Mission OS offline-install test VM.
# Networking is COMPLETELY DISABLED (-net none) — the strongest offline test.
set -euo pipefail
# Run from the repository root; VM dir and ISO are overridable.
VM_DIR="${MISSION_VM_DIR:-$HOME/mission-vm}"
ISO="${MISSION_ISO:-$(ls build/images/mission-os-*.iso 2>/dev/null | head -1)}"
[ -n "$ISO" ] && [ -f "$ISO" ] || { echo "ISO not found; set MISSION_ISO or run from repo root" >&2; exit 1; }
# Fresh target disk
rm -f "${VM_DIR}/install-disk.qcow2"
qemu-img create -f qcow2 "${VM_DIR}/install-disk.qcow2" 20G >/dev/null
cp /usr/share/OVMF/OVMF_VARS_4M.fd "${VM_DIR}/install-vars.fd"
# Clean any stale sockets
rm -f "${VM_DIR}/serial.sock" "${VM_DIR}/monitor.sock"

nohup qemu-system-x86_64 \
    -enable-kvm -cpu host -smp 4 -m 4096 \
    -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
    -drive if=pflash,format=raw,file="${VM_DIR}/install-vars.fd" \
    -drive file="${ISO}",media=cdrom,readonly=on \
    -drive file="${VM_DIR}/install-disk.qcow2",if=virtio \
    -drive file="${VM_DIR}/script.img",format=raw,if=virtio \
    -net none \
    -serial unix:"${VM_DIR}/serial.sock",server,nowait \
    -monitor unix:"${VM_DIR}/monitor.sock",server,nowait \
    -vnc 127.0.0.1:2 \
    -daemonize
echo "VM_LAUNCHED"
