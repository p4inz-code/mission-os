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

# Allowed methods

- Local sockets
- Named pipes
- Message queues

---

# Forbidden

- Shared mutable globals
- Unauthenticated IPC
- Arbitrary code execution

---

# Definition of done

Processes communicate securely with minimal coupling.