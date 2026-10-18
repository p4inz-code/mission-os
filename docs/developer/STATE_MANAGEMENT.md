# Mission OS state management

**Document ID:** MOS-DEV-004

## Purpose

Defines how application state is managed throughout Mission OS.

---

# Principles

State should be:

- Predictable
- Observable
- Minimal
- Recoverable

---

# Categories

## Local state

Temporary UI values.

Examples:

- Dialog visibility
- Selected tab
- Input values

---

## Screen state

Data shared within one screen.

Examples:

- Loaded settings
- Search results
- Current filters

---

## Application state

Shared across applications.

Examples:

- User profile
- Theme
- Accessibility preferences

---

## System state

Provided by Mission OS.

Examples:

- Network
- Battery
- Updates
- Security status

---

# Rules

Avoid duplicate state.

Use a single source of truth.

Never mutate shared state unpredictably.

---

# Persistence

Persist only necessary data.

Examples:

- Preferences
- Workspace layouts
- Installed packages

Temporary state should not survive restarts.

---

# Error recovery

State restoration should occur after:

- Crash
- Restart
- Update
- Recovery

---

# Definition of done

Application state remains deterministic, recoverable, and easy to debug.