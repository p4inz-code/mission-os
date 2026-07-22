# Mission OS Error Handling

**Document ID:** MOS-DEV-005

## Purpose

Defines the standard approach for detecting, reporting, logging, and recovering from errors throughout Mission OS.

---

# Principles

Errors should be:

- Predictable
- Recoverable
- Informative
- Logged
- Secure

---

# Categories

## User Errors

Examples:

- Invalid input
- Missing file
- Permission denied

Provide clear guidance for resolution.

---

## Application Errors

Examples:

- Failed API call
- Invalid configuration
- Missing dependency

Log internally and expose a user-friendly message.

---

## System Errors

Examples:

- Driver failure
- Service crash
- Disk failure

Attempt recovery before notifying the user.

---

# Error Messages

Every error message should include:

- What happened
- Why it happened (if known)
- Suggested action

Avoid technical jargon unless Developer Mode is enabled.

---

# Logging

Every unexpected error must generate a structured log entry.

Sensitive information must never be written to logs.

---

# Recovery

Where possible, applications should:

- Retry safely
- Restore previous state
- Prevent data loss

---

# Definition of Done

Errors are understandable, recoverable, and consistently logged.