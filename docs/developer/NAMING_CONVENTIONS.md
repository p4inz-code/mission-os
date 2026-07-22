# Mission OS Naming Conventions

**Document ID:** MOS-DEV-002

## Purpose

Defines consistent naming rules across the entire Mission OS codebase.

---

# General

Names should be:

- Clear
- Predictable
- Searchable
- Unambiguous

Avoid abbreviations unless universally understood.

---

# Files

Examples:

- UpdateManager
- SecurityCenter
- PrivacyCenter
- MissionHub

Use descriptive names.

---

# Classes

Use PascalCase.

Example:

```
UpdateManager
MissionStore
RecoveryService
```

---

# Methods

Use PascalCase.

Method names should start with a verb.

Examples:

```
LoadSettings()
VerifyPackage()
InstallUpdate()
```

---

# Variables

Use camelCase.

Examples:

```
currentUser
selectedPackage
driverVersion
```

---

# Constants

Use PascalCase or project-wide standard consistently.

Constants should clearly communicate intent.

---

# Booleans

Should read naturally.

Examples:

```
isInstalled
hasPermission
canRollback
```

---

# Enums

Use PascalCase.

Avoid numeric prefixes.

---

# Folders

Lowercase with hyphens where appropriate.

Examples:

```
security
file-manager
mission-store
```

---

# UI Components

Names should describe purpose.

Examples:

```
PrimaryButton
SettingsCard
SidebarNavigation
```

---

# Definition of Done

Every identifier should be understandable without requiring surrounding context.