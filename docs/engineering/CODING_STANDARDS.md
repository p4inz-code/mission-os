# Mission OS Coding Standards

**Document ID:** MOS-ENG-CS-001
**Version:** 1.0
**Status:** Draft
**Last Updated:** July 2026

---

## 1. Purpose

This document defines the engineering standards for all Mission OS code. It supersedes the earlier developer/CODING_STANDARDS.md and provides specific, actionable rules.

---

## 2. General Standards

### 2.1 Readability

- Code is written for humans first, computers second.
- Prefer descriptive names over comments that explain bad names.
- Functions should fit on one screen (max ~50 lines).
- Files should have a single clear purpose.

### 2.2 Consistency

- Follow the naming conventions in NAMING_CONVENTIONS.md.
- Follow the established patterns of the surrounding code.
- Use project-wide linting: `cargo fmt`, `clang-format`, `rustfmt`.

### 2.3 Safety

- Unsafe Rust must be minimized, wrapped, and documented.
- C/C++ code must avoid undefined behavior.
- All input from external sources must be validated.
- Memory must be explicitly managed (no leaks).

### 2.4 Documentation

- Every public API has doc comments.
- Every unsafe block has a safety comment explaining why it's safe.
- Complex algorithms have inline comments explaining the approach.
- Every module has a top-level doc comment describing its purpose.

---

## 3. Rust Standards

### 3.1 Formatting

- Use `rustfmt` with project configuration.
- Use `clippy` with project configuration. All warnings must be addressed.

### 3.2 Error Handling

- Use `thiserror` for library error types.
- Use `anyhow` for application-level error handling.
- Never `unwrap()` or `expect()` in production code except in tests.
- Prefer `anyhow::Context` for adding context to errors.

### 3.3 Async

- Use `tokio` as the async runtime for services.
- Use structured concurrency (tokio::select, JoinSet).
- Never `block_on` in async contexts.
- Always handle cancellation correctly (drop = cleanup).

### 3.4 Types

- Prefer domain-specific types over primitives (`struct Username(String)` vs `String`).
- Use `enum` for states, not boolean flags.
- Implement `Display` for user-facing error types.

### 3.5 Safety

- Wrap all FFI calls in safe abstractions.
- All `unsafe` blocks require a `// SAFETY:` comment.
- Use `pin` and `Unpin` correctly for self-referential types.

---

## 4. C/C++ Standards

### 4.1 Formatting

- Use `clang-format` with project configuration.
- Use `clang-tidy` for static analysis.

### 4.2 Memory Safety

- Prefer smart pointers (`std::unique_ptr`, `std::shared_ptr`).
- Raw pointers only for non-owning observer patterns.
- No C-style memory management (malloc/free) in new code.
- RAII for all resource management.

### 4.3 Qt Guidelines

- Use Qt 6 API.
- Prefer signals/slots over direct coupling.
- Use KDE Frameworks conventions where applicable.
- QML components follow the Mission OS design system.

---

## 5. QML Standards

### 5.1 Structure

- One component per file (except inline components).
- Component files named in PascalCase matching the component name.
- Separated into `ui/`, `dialogs/`, `pages/` directories.

### 5.2 Style

- Use Kirigami components where available.
- Use Mission OS design tokens from `org.mission.ui` module.
- No inline JavaScript logic (extract to C++ backend).

### 5.3 Accessibility

- Every interactive element has `Accessible.name` set.
- Every element has a descriptive `Accessible.description`.
- Use semantic components (Button, CheckBox, etc.) over generic Rectangle+MouseArea.

---

## 6. Python Standards (Tooling Only)

- Use Python type hints for all functions.
- Use `black` for formatting.
- Use `ruff` for linting.
- Prefer `pathlib` over `os.path`.
- No Python in production runtime.

---

## 7. Shell Standards

- Use `shellcheck` for all shell scripts.
- Scripts must have `.sh` extension.
- Use `set -euo pipefail` in all new scripts.
- Prefer POSIX sh unless bash is explicitly required.

---

## 8. Error Handling

### 8.1 Library Code

- Return `Result<T, E>` (Rust) or exceptions (C++) with error details.
- Error types implement `std::error::Error` (Rust) or inherit from `std::exception` (C++).
- Include context in all errors (what failed, why, which resource).

### 8.2 Service Code

- Log errors with appropriate severity level.
- Return structured error responses over IPC.
- Never expose internal details in error messages sent over IPC.
- Distinguish between:
  - **User errors**: Invalid input, permission denied (clear user message)
  - **System errors**: Disk full, network down (actionable guidance)
  - **Internal errors**: Bug, unexpected state (log + generic message)

### 8.3 Application Code

- Show user-friendly error messages.
- Include "what to do next" guidance.
- Log technical details separately.
- Never show stack traces to users (Developer Mode can opt in).

---

## 9. Logging

### 9.1 Log Levels

| Level | Usage |
|-------|-------|
| ERROR | Unexpected failures requiring attention |
| WARN | Recoverable issues, deprecated API usage |
| INFO | Notable events (startup, shutdown, update applied) |
| DEBUG | Detailed information for debugging |
| TRACE | Very detailed flow tracing |

### 9.2 Rules

- Use structured logging (fields, not just messages).
- Never log: passwords, encryption keys, personal content, session tokens.
- Include: request ID, component name, correlation ID.
- Log at startup: version, configuration summary (no secrets).
- Log at shutdown: exit status, reason.

---

## 10. Security-Sensitive Code

### 10.1 Handling Secrets

- Zeroize memory after use (`zeroize` crate in Rust, explicit memset in C/C++).
- Use `mlock()` to prevent secrets from being swapped to disk.
- Never pass secrets as command-line arguments.
- Never log secrets.
- Never serialize secrets to disk unencrypted.

### 10.2 Input Validation

- Validate all input at the boundary.
- Reject unexpected input early with a clear error.
- Use allowlists over denylists where possible.
- Validate sizes before allocating.

### 10.3 Privilege

- Drop privileges as early as possible.
- Use `capabilities` over full root.
- Verify authorization before every privileged operation.

---

## 11. Concurrency

- Prefer message passing over shared state.
- Use `Arc<Mutex<T>>` only when necessary (Rust).
- Use atomic types for simple counters/flags.
- Avoid global mutable state.
- Document thread safety guarantees for all public APIs.

---

## 12. Resource Ownership

- Every resource has a clear owner.
- Ownership is documented in comments where not obvious.
- Resources are released in reverse order of acquisition.
- RAII pattern in C++, Drop trait in Rust.

---

## 13. Code Review Requirements

Every pull request must verify:

- [ ] Follows naming conventions
- [ ] Follows formatting rules
- [ ] No unsafe code without justification
- [ ] All new public APIs documented
- [ ] Error handling is complete
- [ ] No sensitive data exposed in logs/errors
- [ ] Tests cover success and failure paths
- [ ] No new dependencies without approval
- [ ] Performance impact assessed
- [ ] Accessibility impact assessed
- [ ] Security impact assessed
- [ ] No TODO without tracking issue

---

## 14. Git Conventions

### 14.1 Commit Messages

Use Conventional Commits:

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `security`
Scope: module name (e.g., `securityd`, `mission-hub`, `core`)

### 14.2 Branch Naming

- `feat/<short-description>` — New features
- `fix/<short-description>` — Bug fixes
- `docs/<short-description>` — Documentation
- `refactor/<short-description>` — Refactoring
- `security/<short-description>` — Security fixes

### 14.3 Pull Requests

- One change per PR.
- PR description explains what and why.
- PR references related issues.
- Large changes are discussed before implementation.

---

**End of Document**
