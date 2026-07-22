# Mission OS IPC

**Document ID:** MOS-ENG-003

## Purpose

Defines Inter-Process Communication.

---

# Principles

- Secure
- Authenticated
- Versioned
- Logged

---

# Allowed Methods

- Local sockets
- Named pipes
- Message queues

---

# Forbidden

- Shared mutable globals
- Unauthenticated IPC
- Arbitrary code execution

---

# Definition of Done

Processes communicate securely with minimal coupling.