# Mission OS service architecture

**Document ID:** MOS-ENG-002

## Purpose

Defines background service organization.

---

# Service types

- System
- Security
- Networking
- Updates
- Storage
- UI

---

# Rules

Services must:

- Start independently
- Recover automatically
- Log failures
- Minimize resource usage

---

# Communication

Services communicate through defined IPC channels only.

---

# Definition of done

Services remain modular, isolated, and fault tolerant.