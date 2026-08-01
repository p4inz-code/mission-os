# Mission OS Data Architecture

**Document ID:** MOS-ENG-DATA-001
**Version:** 1.0
**Status:** Draft
**Last Updated:** July 2026

---

## 1. Purpose

This document defines the data architecture of Mission OS, covering data integrity, safety, recovery, and the principle that **user data must never be lost**.

---

## 2. Data Categories

### 2.1 Data Classification

| Category | Examples | Criticality | Backup Required |
|----------|----------|-------------|-----------------|
| User Files | Documents, photos, projects, media | Critical | Yes |
| User Configuration | Workspace layout, theme, shortcuts | High | Yes |
| Application State | Open documents, window positions | Medium | Optional |
| Application Data | Store cache, thumbnail cache | Low | No |
| System Configuration | Firewall rules, security policy | High | Yes (in system snapshot) |
| Secrets | Encryption keys, passwords, tokens | Critical | Yes (encrypted) |
| System Logs | Audit logs, crash reports | Medium | Optional |
| Temporary Data | Cache files, temporary downloads | Low | No |
| Package Cache | Downloaded .deb/.rpm files | Low | No |

---

## 3. Data Integrity Requirements

### 3.1 Atomic Write Pattern

Every persistent state change MUST follow this atomic pattern:

```
1. Write to temporary file (.tmp extension)
2. fsync() the temporary file
3. Rename temporary file to target (atomic on same filesystem)
4. fsync() the containing directory
```

This prevents partial writes from disk-full or power-loss conditions.

### 3.2 Checksum Verification

Critical data files carry embedded checksums:

- System configuration files: SHA-256 stored in file metadata
- User configuration files: Optional checksum
- Snapshots: Merkle tree of all contained files
- Packages: SHA-256 checksum in manifest

### 3.3 Corruption Detection

- Configuration files: Format validation on read
- User files: Silent (Mission OS does not scan user files for corruption)
- System databases: Integrity checks on service startup
- Snapshots: Full checksum verification before restore

---

## 4. Data Recovery Architecture

### 4.1 Recovery Flow

The frozen Recovery-flow model **Choose → Preview → Snapshot → PoNR → Apply → Verify** is the canonical workflow for all destructive operations.

```
┌─────────┐    ┌─────────┐    ┌─────────┐    ┌──────┐    ┌─────────┐    ┌─────────┐
│ Choose   │───→│ Preview │───→│ Snapshot│───→│ PoNR │───→│  Apply  │───→│ Verify  │
└─────────┘    └─────────┘    └─────────┘    └──────┘    └─────────┘    └─────────┘
                                                                              │
                                                                              ▼
                                                                         ┌─────────┐
                                                                         │  Done   │
                                                                         └─────────┘
                                                                              │
                                                                        (on failure)
                                                                              ▼
                                                                         ┌─────────┐
                                                                         │Rollback │
                                                                         └─────────┘
```

**Choose:** User selects operation (update, driver install, setting change, etc.)
**Preview:** System shows what will change
**Snapshot:** State saved before any modification
**PoNR:** Point of No Return — explicit user confirmation
**Apply:** Operation executed
**Verify:** Automatic verification that the operation succeeded
**Rollback:** On failure, snapshot is restored atomically

### 4.2 Snapshots

Snapshots are created at:

- Before system updates (automatic)
- Before driver installations (automatic)
- Before major configuration changes (automatic)
- User request (manual, at any time)

Snapshot contents:
- System configuration files (from /etc/mission/)
- Package state (dpkg database)
- Boot loader configuration
- Selected user configuration
- Snapshot metadata (timestamp, description, Mission OS version)

Snapshots do NOT contain:
- User files in /home/ (these are user data, not system state)
- Temporary files in /tmp/ and /var/tmp/
- Package cache

### 4.3 Rollback

Rollback restores:
- System configuration
- Package state
- Boot loader configuration

Rollback does NOT modify:
- User files in /home/
- User settings (except when explicitly part of a settings change)

Rollback integrity verification:
- All snapshot checksums verified before restore
- Failed checksum = snapshot marked as corrupted, user informed

---

## 5. Backup Architecture

### 5.1 Backup Types

| Type | Contents | Frequency |
|------|----------|-----------|
| Quick Backup | User files (desktop, documents, projects) | User-defined schedule |
| Full Backup | All user data + selected configuration | Weekly (default) |
| System Snapshot | System state (automatic) | Before each system change |
| Application Backup | Application data | Application-defined |

### 5.2 Backup Targets

- External drive (USB, SSD)
- Network share (SMB, NFS, SFTP)
- Recovery media
- Encrypted backup file (portable)

### 5.3 Backup Verification

Every backup includes:
- Integrity verification after creation
- Checksum manifest
- Optional: test restore verification

---

## 6. Update Safety

### 6.1 Update Integrity

Every update follows the atomic flow:

```
1. Download → checksum verify → sign verify
2. Create system snapshot
3. Stage update files
4. Apply update (atomic transaction)
5. Verify installation
6. Update snapshot metadata to indicate success
7. Cleanup
```

### 6.2 Update Failure Recovery

If update fails:
1. System snapshot is restored automatically
2. Previous package state restored
3. User data is untouched
4. Diagnostic log generated
5. User notified of failure cause

### 6.3 Disk-Full Protection

Before update:
1. Check available space against estimated requirement + 10% buffer
2. If insufficient: warn user, offer to clear cache, abort if impossible
3. During update: write accounting to detect ENOSPC early
4. If ENOSPC occurs: rollback immediately

---

## 7. Power Loss Protection

### 7.1 Critical Operations

During critical operations (update, driver install, backup, system change):
1. State machine persists current step to disk before each operation
2. On restart after power loss, state machine continues from last persisted step
3. Idempotent operations restart from beginning
4. Non-idempotent operations skip completed steps

### 7.2 Filesystem Protection

- Journaling filesystem (ext4 or btrfs) for all system partitions
- Atomic rename for all configuration writes
- Explicit fsync() after all critical writes

---

## 8. Version Migration

### 8.1 Migration Rules

- Every release includes a migration script for configuration and data
- Migration scripts are versioned (named by source version → target version)
- Migration is atomic: all or nothing
- Migration failure triggers rollback to pre-migration state
- Migration logs detail every change

### 8.2 Configuration Migration

- Configuration files include version field
- Migration script reads version field and applies deltas
- Old configuration is backed up before migration
- Migration can be skipped (configuration recreated with defaults)

---

## 9. Import/Export

### 9.1 Configuration Export

Exportable items:
- Workspace profiles
- Keyboard shortcuts
- Theme and appearance
- Privacy settings
- Network profiles
- Accessibility settings

Format: JSON or TOML (signed optional)

### 9.2 Configuration Import

Import validation:
- Format validation
- Version compatibility check
- Setting-specific validation
- Preview of changes before apply
- Automatic rollback on failure

---

## 10. Data Deletion

### 10.1 Secure Deletion

- Trash: Standard delete (recoverable)
- Permanent delete: Overwrite with zeros (single pass) + unlink
- Secure delete: Overwrite with random data + zeros + unlink (for SSDs: TRIM after overwrite)
- Full disk sanitization: ATA Secure Erase (SSD) / random overwrite (HDD)

### 10.2 Factory Reset

| Option | Data Removed | Data Preserved |
|--------|-------------|----------------|
| Preserve User Files | System config, apps, packages | /home/ contents |
| Remove All | Everything | Nothing |
| Secure Reset | Everything + overwrite | Nothing |

Each option explains consequences before execution.

---

## 11. Crash Recovery

### 11.1 Application Crash

- Mission OS applications save state periodically to crash-recovery files
- On restart: user is offered to restore previous session
- Crash recovery files are self-expiring (configurable TTL)

### 11.2 System Crash

- Boot integrity check on next startup
- If corruption detected: offer Recovery Center
- Automatic fsck on filesystem errors
- systemd-journald preserves logs across crashes

### 11.3 Desktop Shell Crash

- Shell restart preserves running applications
- Application windows re-managed by new shell instance
- Session state recovered from mission-sessiond

---

## 12. Safe Mode

Safe Mode:
- Loads with failsafe display settings
- Disables third-party services and extensions
- Disables sandboxing (for troubleshooting)
- Provides access to Diagnostics and Recovery Center
- Clearly marked as "Safe Mode"

---

## 13. Data Safety Rules Summary

1. **User data must never be lost.**
2. Every destructive operation must create a recoverable state before proceeding.
3. Atomic writes prevent partial file corruption.
4. Snapshots provide system-level rollback.
5. Backups protect user data.
6. Verification confirms operation success.
7. Power loss must not cause data corruption.
8. Migration is versioned and reversible.
9. Crash recovery preserves user progress where possible.
10. Default behavior is conservative: prefer safety over performance.

---

**End of Document**
