# Mission OS IPC architecture

**Document ID:** MOS-ENG-IPC-001
**Version:** 1.0
**Status:** Draft
**Last Updated:** July 2026

---

## 1. Purpose

This document defines the Inter-Process Communication (IPC) model for Mission OS, including process boundaries, service boundaries, authentication, authorization, and failure isolation.

---

## 2. IPC principles

1. All IPC is explicitly defined. No process may communicate with another without a defined IPC contract.
2. All IPC is authenticated. The receiver must verify the caller's identity.
3. All privileged IPC is authorized. Operations that cross privilege boundaries require PolKit authorization.
4. All IPC is logged. Security-relevant IPC operations are recorded in the audit log.
5. IPC must never expose secrets. IPC channels must not transmit passwords, keys, or personal content without encryption.

---

## 3. IPC technologies

### 3.1 Primary: D-Bus

D-Bus is the primary IPC mechanism for all Mission OS communication.

| Bus | Purpose | Security |
|-----|---------|---------|
| System Bus | Communication between system services and user services | PolKit authorization, SELinux/AppArmor mediation |
| Session Bus | Communication within user session (apps ↔ user services) | Implicit trust within session |

### 3.2 Secondary: unix sockets

Unix sockets are used for:
- High-throughput data transfer (file operations)
- Streaming data (diagnostics, hardware monitoring)
- Communication with systemd journal

### 3.3 Prohibited IPC methods

- Shared memory between different privilege levels (forbidden)
- Global mutable state accessible from multiple processes (forbidden)
- Remote procedure calls over network (separate API, not IPC)
- Signal-based communication (except SIGINT/SIGTERM/SIGKILL for lifecycle)

---

## 4. D-Bus interface design

### 4.1 Naming convention

```
org.mission.<ServiceName>1
```

Examples:
- `org.mission.Security1`
- `org.mission.Update1`
- `org.mission.Privacy1`

### 4.2 Interface versioning

- Each D-Bus interface includes a version number in the name
- Backward-compatible changes: add new methods, mark old as deprecated
- Breaking changes: new interface name (e.g., `org.mission.Security2`)
- Deprecated interfaces remain available for at least one release cycle

### 4.3 Method design rules

1. Methods must validate all inputs before performing operations.
2. Methods must return structured error information on failure.
3. Methods must not block indefinitely (implement timeouts, default 30s).
4. Methods must not execute arbitrary shell commands.
5. Methods must log authorization decisions.

### 4.4 Signal design rules

1. Signals must include a sequence number for ordering.
2. Signals must include a timestamp.
3. Signals must not carry sensitive data.

---

## 5. Authorization model

### 5.1 PolKit integration

Every privileged D-Bus method requires PolKit authorization:

```xml
<policyconfig>
  <action id="org.mission.security.configure-firewall">
    <description>Configure firewall rules</description>
    <message>Authentication is required to modify firewall settings</message>
    <defaults>
      <allow_any>auth_admin</allow_any>
      <allow_inactive>auth_admin</allow_inactive>
      <allow_active>auth_admin_keep</allow_active>
    </defaults>
  </action>
</policyconfig>
```

### 5.2 Authorization levels

| Level | PolicyKit Setting | Use Case |
|-------|------------------|----------|
| None | `no` | No authorization needed (read-only info) |
| User | `auth_self` | User affecting their own settings |
| User Keep | `auth_self_keep` | Session-level authorization caching |
| Admin | `auth_admin` | System-wide changes |
| Admin Keep | `auth_admin_keep` | System changes with session caching |

### 5.3 Authorization caching

- Admin keep: cached for 5 minutes (configurable)
- User keep: cached for 15 minutes (configurable)
- Authorization cache cleared on screen lock

---

## 6. Process boundaries

### 6.1 System services

```
Process: mission-securityd
User: root (or mission-security system user)
Capabilities: CAP_NET_ADMIN, CAP_SYS_ADMIN
Systemd: Type=dbus, BusName=org.mission.Security1
```

### 6.2 User services

```
Process: mission-settingsd
User: <logged-in-user>
Systemd: Type=dbus, BusName=org.mission.Settings1, User=%
```

### 6.3 User applications

```
Process: mission-hub
User: <logged-in-user>
No direct system bus access (except via user service proxy)
```

### 6.4 Recovery environment

```
Process: recovery tools
User: root (temporary, recovery environment only)
No D-Bus (minimal environment)
```

---

## 7. IPC flow patterns

### 7.1 Application → System Service (with elevation)

```
mission-hub
    │ request (session bus)
    ▼
mission-settingsd
    │ PolKit authorization check
    ▼
    [authorized] → forward request (system bus, authenticated)
                        ▼
                   mission-securityd
                        │
                   [return result]
                        ▼
                   mission-settingsd → mission-hub
```

### 7.2 Application → user service

```
mission-settings
    │ request (session bus)
    ▼
mission-settingsd
    │ process request (user privileges)
    ▼
    [return result]
```

### 7.3 Service → application (signal)

```
mission-updated
    │ Signal: UpdateAvailable (session bus broadcast)
    ▼
mission-hub
mission-update-manager
    │ (both receive signal)
    ▼
    [optionally update UI]
```

---

## 8. Error handling

### 8.1 Error response format

Every D-Bus error includes:
- Error name (e.g., `org.mission.Error.PermissionDenied`)
- Error message (human-readable)
- Error code (machine-parseable integer)
- Diagnostic data (optional, expandable)

### 8.2 Standard errors

| Error | Code | Description |
|-------|------|-------------|
| PermissionDenied | 100 | Caller not authorized |
| InvalidArgument | 101 | Malformed input |
| NotFound | 102 | Resource not found |
| AlreadyExists | 103 | Resource already exists |
| Busy | 104 | Service busy, retry later |
| InternalError | 105 | Unexpected service failure |
| Timeout | 106 | Operation timed out |
| NotSupported | 107 | Feature not available |
| DiskFull | 108 | Insufficient storage |
| NetworkRequired | 109 | Network required but unavailable |

### 8.3 Timeouts

- Default D-Bus method timeout: 30 seconds
- Long-running operations: return immediately with progress tracking signal
- Health check timeout: 5 seconds
- Service startup timeout: 30 seconds

---

## 9. Failure isolation

### 9.1 Service crash

- systemd automatically restarts crashed services
- Restart limit: 3 attempts within 30 seconds, then enter failed state
- Failed state: administrator intervention required
- Service state is recovered from persistent storage on restart
- In-flight operations are lost (callers receive error)

### 9.2 Bus failure

- Session bus restart: all user services reconnect automatically
- System bus restart: critical system failure, systemd reboot policy
- D-Bus proxy in mission-core library handles reconnection transparently

### 9.3 Request validation

All D-Bus method calls undergo:
1. Input type validation (D-Bus type system)
2. Input range validation (business rules)
3. Authorization check (PolKit)
4. Rate limiting (configurable per-method)

Invalid or unauthenticated requests are rejected before processing.

---

## 10. IPC security requirements

1. All system bus interfaces require PolKit authorization for privileged methods.
2. Sensitive data (passwords, keys) must not appear in D-Bus message logs.
3. D-Bus eavesdropping is disabled on the system bus by default.
4. Session bus does not require authentication (trusted within session).
5. Application must not directly connect to the system bus.
6. User services serve as proxies for system bus access.
7. All IPC errors must be logged.
8. Authorization failures must be logged in the audit trail.

---

## 11. Bus configuration

### 11.1 System bus configuration

```
<!-- /usr/share/dbus-1/system.d/org.mission.Security.conf -->
<busconfig>
  <policy user="root">
    <allow own="org.mission.Security1"/>
  </policy>
  <policy context="default">
    <deny send_destination="org.mission.Security1"/>
  </policy>
  <policy at_console="true">
    <allow send_destination="org.mission.Security1"/>
  </policy>
</busconfig>
```

### 11.2 Session bus

No additional restrictions beyond standard session bus policy.

---

## 12. IPC rules summary

| Rule | Description |
|------|-------------|
| 1 | All IPC uses D-Bus |
| 2 | All system bus methods require PolKit authorization |
| 3 | Messages are validated before processing |
| 4 | Errors are structured and logged |
| 5 | Services restart automatically |
| 6 | Authorization is time-limited |
| 7 | Secrets never traverse IPC unencrypted |
| 8 | Applications never connect directly to system bus |

---

**End of Document**
