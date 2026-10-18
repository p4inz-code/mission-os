# Mission OS logging

**Document ID:** MOS-ENG-007

## Purpose

Defines logging behavior across Mission OS.

---

# Principles

Logs must be:

- Structured
- Timestamped
- Searchable
- Privacy respecting

---

# Log levels

- Debug
- Info
- Warning
- Error
- Critical

---

# Rules

- Never log passwords.
- Never log encryption keys.
- Never log personal files.
- Rotate logs automatically.
- Support log export.

---

# Definition of done

Logs provide actionable diagnostics without exposing sensitive information.