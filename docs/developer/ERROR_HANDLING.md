# Mission OS error handling

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

## User errors

Examples:

- Invalid input
- Missing file
- Permission denied

Provide clear guidance for resolution.

---

## Application errors

Examples:

- Failed API call
- Invalid configuration
- Missing dependency

Log internally and expose a user-friendly message.

---

## System errors

Examples:

- Driver failure
- Service crash
- Disk failure

Attempt recovery before notifying the user.

---

# Error messages

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

# Definition of done

Errors are understandable, recoverable, and consistently logged.