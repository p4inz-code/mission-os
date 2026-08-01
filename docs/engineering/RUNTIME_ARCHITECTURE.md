# Mission OS Runtime Architecture

**Document ID:** MOS-ENG-RUNTIME-001
**Version:** 1.0
**Status:** Draft
**Last Updated:** July 2026

---

## 1. Purpose

This document defines the runtime architecture of Mission OS, including boot sequence, startup, session lifecycle, service management, and runtime recovery.

---

## 2. Boot Sequence

### 2.1 Complete Boot Flow

```
Firmware (UEFI)
    │ Secure Boot verification
    ▼
Bootloader (GRUB2 — BIOS + UEFI)
    │ Verify signed kernel + initramfs
    ▼
Kernel Initialization
    │ Hardware detection, driver loading
    ▼
initramfs
    │ LUKS2 unlock (password, TPM, or recovery key)
    │ Root filesystem mount
    ▼
init (systemd)
    │ systemd units start
    ▼
┌──────────────────────────────────────────────────────┐
│ Basic System Services                                │
│ systemd-journald, systemd-udevd, systemd-resolved,   │
│ systemd-timesyncd, systemd-logind                    │
├──────────────────────────────────────────────────────┤
│ Mission System Services                              │
│ mission-securityd, mission-updated, mission-driverd  │
│ mission-privileged                                   │
├──────────────────────────────────────────────────────┤
│ Display Manager (SDDM)                                │
│ ─────────────────────────────────────────────────    │
│ User Authentication                                  │
│ ─────────────────────────────────────────────────    │
│ KDE Plasma Desktop Start                             │
│ kwin_wayland → plasmashell                           │
│ ─────────────────────────────────────────────────    │
│ User Session Services                                │
│ mission-sessiond → mission-settingsd → mission-priva │
│ → mission-hub (optional auto-start)                  │
├──────────────────────────────────────────────────────┤
│ User Ready                                           │
└──────────────────────────────────────────────────────┘
```

### 2.2 Boot Verification

At each boot stage:
1. **UEFI**: Secure Boot validates bootloader signature
2. **Bootloader**: Signed kernel + initramfs verified
3. **initramfs**: LUKS volume opened (authenticated)
4. **systemd**: Service integrity checked (IMA/EVM — future)
5. **Desktop**: Mission services verify their own configuration integrity

### 2.3 Boot Failure Handling

| Failure Point | Behavior |
|--------------|----------|
| Secure Boot fails | Warning displayed. Option to continue (if disabled in firmware) |
| Bootloader corrupted | Fallback bootloader entry. Recovery menu |
| Kernel panic | Automatic reboot with recovery entry |
| LUKS unlock fails | Retry prompt. Recovery key option. Emergency shell |
| Root filesystem corruption | Automatic fsck. If unrecoverable: Recovery Center |
| System service crash | systemd restart. If persistent: degrade functionality |
| Display manager crash | Restart DM. If persistent: fallback to console |

### 2.4 Boot Performance Targets

| Stage | Target |
|-------|--------|
| Firmware init | < 5 seconds (UEFI fast boot) |
| Bootloader | < 2 seconds |
| LUKS unlock | < 2 seconds (SSD + efficient KDF) |
| Kernel + initramfs | < 5 seconds |
| System services | < 5 seconds |
| Display manager | < 3 seconds |
| Desktop ready | < 5 seconds |
| **Total cold boot (SSD)** | **< 30 seconds** |

---

## 3. Startup Sequence Detail

### 3.1 System Service Startup Order

```
1. systemd-journald           (log always first)
2. systemd-udevd              (device management)
3. systemd-resolved           (DNS)
4. systemd-timesyncd          (time sync)
5. systemd-logind             (session management)
6. mission-securityd          (firewall, audit)
7. mission-driverd            (hardware detection)
8. mission-updated            (update service)
9. mission-privileged         (elevation proxy)
```

Dependencies are declared in systemd unit files. Services start in parallel where independent.

### 3.2 User Service Startup Order

```
1. mission-sessiond           (session state)
2. mission-settingsd          (settings persistence)
3. mission-privacyd           (privacy enforcement)
4. mission-networkd           (network management)
5. mission-accessibilityd     (accessibility services)
6. mission-hub (optional)     (dashboard)
```

---

## 4. Session Lifecycle

### 4.1 Login Flow

```
Display Manager (SDDM)
    │ User selects user → enters credentials
    ▼
PAM Authentication
    │ Validated against local account database
    ▼
session-init (systemd user instance)
    │ Start systemd --user
    ▼
KDE Plasma Initialization
    │ kwin_wayland starts → plasmashell loads
    ▼
Mission OS session services start
    │ mission-sessiond → restore previous session state
    ▼
Desktop ready
    │ Workspaces restored, applications launching
```

### 4.2 Session State Persistence

Saved on logout/lock:
- Open applications and windows
- Window positions and workspaces
- Current workspace layout
- Notification state

Restored on login:
- Previous session state (optional, user-configurable)
- Workspace layout with applications

### 4.3 Lock/Unlock

```
Screen Lock Trigger (timeout, shortcut, suspend)
    ▼
mission-lockd or ksmserver lock
    ▼
Lock screen shown (SDL / KDE lock screen)
    ▼
User authenticates (password, PIN, biometric)
    ▼
Desktop restored to pre-lock state
```

---

## 5. Service Management

### 5.1 systemd Integration

All Mission OS services use systemd unit files:

```ini
# /usr/lib/systemd/system/mission-securityd.service
[Unit]
Description=Mission OS Security Service
Documentation=https://docs.mission-os.org/security
After=network.target systemd-journald.service
Requires=systemd-journald.service

[Service]
Type=dbus
BusName=org.mission.Security1
ExecStart=/usr/lib/mission/mission-securityd
User=mission-security
Group=mission-security
CapabilityBoundingSet=CAP_NET_ADMIN CAP_SYS_ADMIN
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
```

### 5.2 Service Recovery Policies

| Service Type | systemd Restart Policy | Max Restarts |
|-------------|----------------------|--------------|
| Critical (securityd) | on-failure | 5 in 60s |
| Standard (updated) | on-failure | 3 in 30s |
| Optional (driverd) | on-failure | 3 in 30s |
| User services | on-failure | 3 in 30s |

### 5.3 Resource Limits

systemd resource control for all Mission services:

| Resource | Limit |
|----------|-------|
| Memory | 256 MB (soft), 512 MB (hard) |
| File descriptors | 4096 |
| Processes | 64 |
| CPU time | 10s per 30s (soft) |

---

## 6. Desktop Session Integration

### 6.1 KDE Plasma Integration

Mission OS session management:
- Uses `startplasma-wayland` as session entry
- KDE global shortcuts configured by Mission OS keyboard preset
- Custom Mission OS QML components loaded via Plasma plugin system
- Mission OS wallpaper and theme applied on session start

### 6.2 Mission OS Plasma Extensions

- `org.mission.plasma.panel` — Mission OS panel layout
- `org.mission.plasma.quick-settings` — Quick settings menu
- `org.mission.plasma.notifications` — Notification center
- `org.mission.plasma.launcher` — Application launcher

---

## 7. Power Management

### 7.1 Suspend/Resume

```
Suspend trigger
    │ Lock screen immediately
    ▼
Notify services (update: pause downloads)
    │
    ▼
Suspend to RAM
    │
▼
Wake event (lid open, key press, USB activity)
    │
    ▼
Resume
    │ Unlock screen
    ▼
Services resume normal operation
    │ Updates resume, network reconnects
```

### 7.2 Hibernate

Hibernate to disk:
- Requires swap partition (preferably encrypted)
- Enabled by default if sufficient swap detected
- Lock screen required before hibernate

### 7.3 Power Failure Recovery

On power failure during:
- **Active operation (not writing):** Resume on next boot. Temporary data may be lost.
- **Active write:** Filesystem journal recovers. Application state may be lost.
- **Update:** Update state machine resumes from last safe step.

---

## 8. Software Update at Runtime

### 8.1 Online Updates

Updates require:
1. User approval (unless automatic security updates enabled)
2. Sufficient disk space verified
3. Snapshot created
4. Packages downloaded and verified
5. Applied (may require restart)

### 8.2 Offline Updates

For kernel/core updates requiring restart:
- update staged to dedicated partition
- bootloader configured to boot update target
- On restart: update applied before login
- If update fails: rollback to previous boot entry automatically

---

## 9. Shutdown Sequence

```
User initiates shutdown
    │
    ▼
Notify all services: prepare for shutdown
    │ mission-updated: pause updates
    │ mission-driverd: release hardware
    │
    ▼
Save session state (mission-sessiond)
    │
    ▼
KDE Plasma shutdown
    │
    ▼
User service shutdown
    │
    ▼
System service shutdown
    │
    ▼
systemd shutdown
    │
    ▼
Final filesystem sync
    │
    ▼
Power off
```

---

## 10. Environment Detection

### 10.1 Runtime Environment

Mission OS detects and adapts to:
- **Installed mode:** Full feature set
- **Portable mode (Live USB):** Reduced write cycles, persistence enabled if configured
- **Recovery environment:** Minimal UI, repair tools
- **Virtual machine:** Optimized display drivers, guest tools

### 10.2 Hardware Profiles

Hardware detection at boot configures:
- Display (resolution, scaling, refresh rate)
- Audio (output device, volume)
- Network (adapter type, connection state)
- Power management (laptop vs desktop profile)
- Input devices (touchpad, touchscreen, drawing tablet)

---

**End of Document**
