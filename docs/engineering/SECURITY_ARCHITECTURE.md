# Mission OS Security Architecture

**Document ID:** MOS-ENG-SEC-001
**Version:** 1.0
**Status:** Draft
**Last Updated:** July 2026

---

## 1. Purpose

This document defines the complete security model of Mission OS.

Distinctions between **Privacy**, **Security**, **Anonymity**, and **Compartmentalization** are maintained throughout. These terms are not interchangeable, and the architecture treats each separately.

---

## 2. Threat Model

### 2.1 Assumptions

- The user trusts Mission OS as a platform (supply-chain trust established via signing)
- The user does not necessarily trust application vendors
- The hardware may be untrusted (portable OS use case)
- The network is untrusted
- Physical access to the device may be lost (encryption primary defense)
- The user may be using a compromised computer (portable mode)

### 2.2 Threats Considered

| Threat | Mitigation |
|--------|-----------|
| Malicious application reading user files | Sandboxing + permission model |
| Malicious application accessing hardware (camera, mic) | Permission enforcement + hardware indicators |
| Network attacker intercepting traffic | Encryption (TLS, VPN, HTTPS) |
| Offline physical attack on storage | Full disk encryption (LUKS2) |
| Boot kit / rootkit | Secure Boot + boot integrity verification |
| Supply chain attack on packages | Signature verification + repository trust |
| Privilege escalation | Least privilege + PolKit + sandboxing |
| Data exfiltration by telemetry | No telemetry by default; opt-in only |
| Downgrade attack on updates | Signed update metadata with version pinning |
| Side-channel attacks | Not mitigated in v1 (acknowledged) |
| Evil maid attack on USB boot | Boot integrity verification + signed recovery media |

### 2.3 Non-Goals (Security)

- Protection against sophisticated nation-state actors with physical access and equipment
- Full formal verification of the entire OS
- Perfect side-channel resistance
- Protection against unknown zero-day kernel exploits

---

## 3. Security Domains

Mission OS separates security into four distinct domains:

### 3.1 User Accounts

- Standard Linux user accounts (PAM-based authentication)
- Optional: systemd-homed for portable encrypted home directories
- Local accounts only — no mandatory online accounts
- Password quality enforcement with configurable policy

### 3.2 Privilege Separation

Principle: Every process runs with the minimum permissions required.

| Level | Description | Examples |
|-------|-------------|---------|
| Ring 0 | Kernel | Drivers, LSM, kernel modules |
| System | Root services | mission-securityd, mission-updated |
| Privileged | PolKit-authorized | Temporary elevation via mission-privileged |
| User | Normal user session | Mission Hub, Settings |
| Sandboxed | Restricted user | Flatpak/Bubblewrap applications |
| Network-isolated | No network access | Offline apps |
| Hardware-isolated | No camera/mic/etc | Permission-denied apps |

### 3.3 Authentication

Supported methods:
- Password (required for every account)
- PIN (optional convenience, secondary authentication)
- Biometrics (fprintd — optional, supported hardware)
- Security keys (FIDO2/U2F — future)
- TPM-assisted unlock (LUKS2 + tpm2-cryptenroll)

Authentication policies:
- Configurable lock timeout
- Configurable failed attempt handling
- Graceful degradation: fallback to password if biometric fails

### 3.4 Authorization

All authorization flows follow this pattern:

```
Application requests action
    ↓
PolKit checks authorization
    ↓
[Authorized] → Action proceeds (logged)
    OR
[Not Authorized] → mission-privileged prompts user
    ↓
User grants/denies (explanation shown)
    ↓
Action logged to audit
```

---

## 4. Defense in Depth Layers

```
Layer 1: Secure Boot (UEFI)
    ↓
Layer 2: Boot Integrity Verification (signed bootloader + kernel)
    ↓
Layer 3: Kernel LSM (AppArmor / SELinux profile)
    ↓
Layer 4: systemd security features (namespaces, capabilities, Protect*)
    ↓
Layer 5: PolKit authorization
    ↓
Layer 6: Application sandboxing (Bubblewrap/Firejail)
    ↓
Layer 7: Permission model (camera, mic, location, etc.)
    ↓
Layer 8: Audit logging + monitoring
    ↓
Layer 9: Firewall (nftables)
    ↓
Layer 10: Encryption (LUKS2 + encrypted swap)
```

---

## 5. Encryption Architecture

### 5.1 Storage Encryption

| Partition | Encryption | Default |
|-----------|-----------|---------|
| EFI System Partition | No (unencrypted, UEFI requirement) | On |
| Boot Partition | No (but signed) | On |
| Root Partition | LUKS2 (Argon2 KDF) | Recommended |
| Home Partition | LUKS2 (Argon2 KDF) | Recommended |
| Swap | LUKS2 or encrypted swap | On |
| Recovery Partition | No (but signed) | On |

Key management:
- LUKS2 passphrase (user-chosen)
- Optional: TPM-bound key for automatic unlock
- Optional: recovery key (generated during installation, printable)
- Key slots: 1 (user passphrase) + 1 (recovery key) + 1 (TPM, optional)

### 5.2 Key Management Rules

1. **Encryption keys must never be stored in plaintext on disk.**
2. **Recovery keys must be exportable during installation (PDF, printed).**
3. **Passphrase hint must not contain the actual password.**
4. **Swap encryption must be enabled by default.**
5. **Memory containing key material must be scrubbed after use (mlock() + explicit zeroing).**

### 5.3 Secrets Storage

- GNOME Keyring / KDE Wallet for application secrets
- Encrypted with user login password by default
- Mission OS does not implement a custom secrets service

---

## 6. Network Security

### 6.1 Firewall Architecture

- Backend: nftables
- Default policy: deny incoming, allow outgoing (stateful)
- Profiles:
  - **Public**: Only outgoing connections, no listening services
  - **Private**: Allow LAN connections, no WAN listening
  - **Development**: Allow selected ports
  - **Custom**: User-defined rules
- Application-level firewall: per-application network permissions
- Mission-securityd manages dynamic rule application

### 6.2 DNS Security

- DNS over TLS (DoT) / DNS over HTTPS (DoH) configurable via systemd-resolved
- Default: system DNS
- Recommended: encrypted DNS (user-configurable)
- DNSSEC validation enabled where supported

### 6.3 VPN Integration

- First-class WireGuard support
- OpenVPN and IKEv2 supported
- Kill switch: block non-VPN traffic when VPN is active (optional, configurable)
- Split tunneling: per-application VPN routing (future)

### 6.4 Tor Integration

**Important:** Tor is NOT a universal anonymity solution. Mission OS does NOT claim Tor makes the system anonymous.

Tor integration scope:
- Optional per-application routing via Tor
- Tor Browser Bundle installed by default (or recommended)
- System-wide Tor mode as an opt-in experimental feature
- Clear documentation of Tor limitations and proper usage

**What Tor does:**
- Routes traffic through the Tor network
- Hides IP address from destination servers
- Provides onion service hosting capability

**What Tor does NOT do:**
- Cannot anonymize application-level data
- Cannot prevent browser fingerprinting
- Cannot prevent account-based tracking
- Cannot protect against compromised exit nodes

---

## 7. Package Security

### 7.1 Package Verification

Every package undergoes:
1. **Signature verification** — GPG signature checked against trusted keyring
2. **Checksum verification** — SHA-256 of package content
3. **Repository trust** — Package must come from trusted repository
4. **Dependency integrity** — All dependencies must satisfy the same checks
5. **Manifest validation** — Package manifest must match content

Verification failures abort installation with a clear error message.

### 7.2 Driver Trust

- Signed kernel modules only (enforced in production mode)
- Unsigned driver override available in Developer Mode (with warning)
- Hardware drivers from Mission repository verified automatically
- Third-party drivers require explicit user approval

### 7.3 Update Security

- All updates signed with Mission OS release keys
- Update metadata signed separately from payload
- Replay attack protection via signed version pinning
- Rollback protection: maximum rollback window configurable
- Delta updates verified after reconstruction

---

## 8. Audit Logging

### 8.1 Events Logged

| Category | Events |
|----------|--------|
| Authentication | Login, logout, failed attempts, lock/unlock |
| Privilege | Elevation requests, grant, deny |
| Security | Firewall changes, policy changes, sandbox violations |
| Privacy | Permission grant, revoke, access attempts |
| Updates | Check, download, install, rollback, failure |
| Drivers | Install, update, rollback, verification failure |
| System | Boot, shutdown, crash, recovery |

### 8.2 Audit Requirements

- Logs are local by default
- Logs are structured (JSON) and timestamped
- Logs must not contain: passwords, keys, personal file content
- Log rotation is automatic
- Users can export audit logs
- Optionally forward logs to remote syslog (enterprise)

---

## 9. Sandboxing

### 9.1 Application Sandbox

Scope (pending ADR on technology choice):
- Filesystem isolation: per-application view of filesystem
- Network isolation: per-application network access
- Device isolation: per-application hardware access
- IPC isolation: restricted D-Bus access
- Resource limits: memory, CPU, processes

### 9.2 Default Sandbox Profiles

| Application Type | Filesystem | Network | Devices |
|-----------------|-----------|---------|---------|
| Mission OS apps (trusted) | Full user home | Full | Full |
| System utilities | Read-only system | None | None |
| Third-party GUI apps | XDG directories only | By permission | By permission |
| CLI tools | Current directory | By permission | By permission |
| Network services | Read-only | Required ports | None |

---

## 10. Cer tificate Management

- System trust store: Debian ca-certificates
- Mission OS additional trust anchors stored separately
- Users can add/remove trusted certificates
- Certificate revocation checked where possible (CRL/OCSP)
- Expired certificates flagged

---

## 11. Security Guarantees

### 11.1 What Mission OS Guarantees

1. **Full disk encryption** — Data at rest is encrypted with LUKS2
2. **Verified boot chain** — Bootloader and kernel are signed
3. **Verified packages** — Every package signature is checked before installation
4. **No mandatory telemetry** — No data leaves the system without user consent
5. **Permission enforcement** — Applications cannot access protected resources without permission
6. **Firewall** — Incoming connections blocked by default
7. **Audit logs** — Security-relevant events are logged

### 11.2 What Mission OS Cannot Guarantee

1. Protection against kernel zero-day exploits
2. Immunity to hardware-level attacks (JTAG, bus sniffing, cold boot)
3. Protection if user credentials are compromised
4. Perfect side-channel resistance
5. Anonymity — Tor usage requires user education
6. Protection against malicious peripherals (BadUSB, etc.)

---

## 12. Security Compliance

Before each release:
- Full security review of this architecture
- Penetration testing of core services
- Dependency vulnerability scan
- Static analysis of security-critical code
- Audit of default configuration

---

**End of Document**
