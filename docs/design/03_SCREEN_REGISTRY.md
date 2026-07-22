# Mission OS Screen Registry

**Document ID:** MOS-DESIGN-003

**Version:** 1.0

---

# 1. Purpose

This document is the master inventory of every screen in Mission OS.

Every production UI must originate from this registry.

No screen may exist without appearing here.

---

# 2. Screen Naming Convention

Every screen receives:

```
MOS-XXX-###
```

Example

```
MOS-SET-001
```

Settings Home

---

# 3. Installer

| ID | Screen |
|------|-------------------------|
| MOS-INS-001 | Welcome |
| MOS-INS-002 | Language |
| MOS-INS-003 | Keyboard |
| MOS-INS-004 | Network |
| MOS-INS-005 | Privacy Setup |
| MOS-INS-006 | Disk Selection |
| MOS-INS-007 | Partition Manager |
| MOS-INS-008 | User Account |
| MOS-INS-009 | Encryption |
| MOS-INS-010 | Summary |
| MOS-INS-011 | Installation |
| MOS-INS-012 | Completion |

---

# 4. Lock Screen

| ID | Screen |
|------|----------------|
| MOS-LCK-001 | Lock Screen |
| MOS-LCK-002 | Login |
| MOS-LCK-003 | PIN Entry |
| MOS-LCK-004 | Recovery Login |

---

# 5. Desktop

| ID | Screen |
|------|----------------|
| MOS-DES-001 | Desktop |
| MOS-DES-002 | Workspace Switcher |
| MOS-DES-003 | Notifications |
| MOS-DES-004 | Quick Settings |
| MOS-DES-005 | Search |
| MOS-DES-006 | Calendar |
| MOS-DES-007 | Clipboard History |
| MOS-DES-008 | System Tray |

---

# 6. Mission Hub

| ID | Screen |
|------|----------------|
| MOS-HUB-001 | Dashboard |
| MOS-HUB-002 | Search |
| MOS-HUB-003 | Applications |
| MOS-HUB-004 | Updates |
| MOS-HUB-005 | Security |
| MOS-HUB-006 | Privacy |
| MOS-HUB-007 | Recovery |
| MOS-HUB-008 | Diagnostics |
| MOS-HUB-009 | Devices |
| MOS-HUB-010 | Storage |

---

# 7. Settings

| ID | Screen |
|------|----------------|
| MOS-SET-001 | Home |
| MOS-SET-002 | Personalization |
| MOS-SET-003 | Display |
| MOS-SET-004 | Audio |
| MOS-SET-005 | Input |
| MOS-SET-006 | Accessibility |
| MOS-SET-007 | Network |
| MOS-SET-008 | Bluetooth |
| MOS-SET-009 | Privacy |
| MOS-SET-010 | Security |
| MOS-SET-011 | Storage |
| MOS-SET-012 | Applications |
| MOS-SET-013 | Updates |
| MOS-SET-014 | Recovery |
| MOS-SET-015 | Accounts |
| MOS-SET-016 | About |

---

# 8. Privacy Center

| ID | Screen |
|------|----------------|
| MOS-PRI-001 | Dashboard |
| MOS-PRI-002 | Permissions |
| MOS-PRI-003 | Timeline |
| MOS-PRI-004 | Reports |
| MOS-PRI-005 | Privacy Score |
| MOS-PRI-006 | Recommendations |

---

# 9. Security Center

| ID | Screen |
|------|----------------|
| MOS-SEC-001 | Dashboard |
| MOS-SEC-002 | Firewall |
| MOS-SEC-003 | Encryption |
| MOS-SEC-004 | Secure Boot |
| MOS-SEC-005 | Authentication |
| MOS-SEC-006 | Certificates |
| MOS-SEC-007 | Reports |

---

# 10. Recovery Center

| ID | Screen |
|------|----------------|
| MOS-REC-001 | Dashboard |
| MOS-REC-002 | Restore |
| MOS-REC-003 | Recovery USB |
| MOS-REC-004 | Startup Repair |
| MOS-REC-005 | Factory Reset |
| MOS-REC-006 | Advanced Recovery |

---

# 11. Diagnostics

| ID | Screen |
|------|----------------|
| MOS-DIA-001 | Dashboard |
| MOS-DIA-002 | CPU |
| MOS-DIA-003 | GPU |
| MOS-DIA-004 | Memory |
| MOS-DIA-005 | Storage |
| MOS-DIA-006 | Network |
| MOS-DIA-007 | Drivers |
| MOS-DIA-008 | Reports |

---

# Definition of Done

Every production screen appears in this registry.

# Section 2 — Core Applications

# 12. Mission Store

| ID | Screen |
|------|----------------|
| MOS-STR-001 | Home |
| MOS-STR-002 | Categories |
| MOS-STR-003 | Search |
| MOS-STR-004 | Application Details |
| MOS-STR-005 | Installed |
| MOS-STR-006 | Updates |
| MOS-STR-007 | Downloads |

---

# 13. File Manager

| ID | Screen |
|------|----------------|
| MOS-FIL-001 | Home |
| MOS-FIL-002 | Browse |
| MOS-FIL-003 | Search |
| MOS-FIL-004 | Properties |
| MOS-FIL-005 | Copy Progress |
| MOS-FIL-006 | Trash |

---

# 14. Update Manager

| ID | Screen |
|------|----------------|
| MOS-UPD-001 | Dashboard |
| MOS-UPD-002 | Updates |
| MOS-UPD-003 | History |
| MOS-UPD-004 | Rollback |
| MOS-UPD-005 | Advanced |

---

# 15. Driver Manager

| ID | Screen |
|------|----------------|
| MOS-DRV-001 | Dashboard |
| MOS-DRV-002 | Installed Drivers |
| MOS-DRV-003 | Updates |
| MOS-DRV-004 | Rollback |
| MOS-DRV-005 | Hardware Detection |

---

# 16. Network

| ID | Screen |
|------|----------------|
| MOS-NET-001 | Dashboard |
| MOS-NET-002 | Wi-Fi |
| MOS-NET-003 | Ethernet |
| MOS-NET-004 | VPN |
| MOS-NET-005 | DNS |
| MOS-NET-006 | Proxy |

---

# 17. Accessibility

| ID | Screen |
|------|----------------|
| MOS-ACC-001 | Dashboard |
| MOS-ACC-002 | Vision |
| MOS-ACC-003 | Hearing |
| MOS-ACC-004 | Motor |
| MOS-ACC-005 | Cognitive |
| MOS-ACC-006 | Profiles |

---

# 18. Common Dialogs

Every application may use:

- About
- Preferences
- Error Dialog
- Confirmation Dialog
- File Picker
- Save Dialog
- Open Dialog
- Progress Dialog
- Warning Dialog
- Success Dialog

---

# 19. Global Overlays

Mission OS includes:

- Notification Center
- Quick Settings
- Search Overlay
- Command Palette
- Clipboard Manager
- Screenshot Overlay
- Workspace Switcher
- Volume Overlay
- Brightness Overlay

---

# 20. Future Screens

Reserved IDs are maintained for future expansion.

Deprecated IDs are never reused.

---

# Acceptance Criteria

The Screen Registry passes when:

- every screen has a unique identifier
- IDs remain stable between releases
- new screens receive sequential identifiers
- deprecated screens remain documented
- no production UI exists outside this registry

---

**End of Document**