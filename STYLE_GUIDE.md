# Mission OS Style Guide

This document defines the writing, documentation, and coding style used throughout the Mission OS project.

A consistent style improves readability, maintainability, and collaboration.

---

# General Principles

- Prefer clarity over cleverness.
- Keep documentation concise and accurate.
- Write for both new and experienced contributors.
- Avoid unnecessary complexity.
- Document decisions, not just implementations.

---

# Documentation Style

Documentation should be:

- Clear
- Accurate
- Professional
- Up to date

Use:

- Short paragraphs
- Descriptive headings
- Lists where appropriate
- Proper grammar and spelling

Avoid:

- Marketing language
- Ambiguous wording
- Excessive capitalization
- Emojis (except where intentionally used in GitHub templates)

---

# Code Style

Code should be:

- Readable
- Consistent
- Well documented
- Easy to review

Guidelines:

- Use meaningful names.
- Prefer small, focused functions.
- Avoid duplicated logic.
- Keep modules single-purpose.
- Remove dead code before merging.

---

# Commit Messages

Use Conventional Commits where appropriate.

Examples:

- feat: add Mission Update service
- fix: resolve installer validation issue
- docs: update accessibility guide
- refactor: simplify update pipeline
- test: add diagnostics unit tests

---

# Pull Requests

Every pull request should:

- Solve one problem
- Be easy to review
- Include documentation updates when necessary
- Pass automated checks
- Avoid unrelated changes

---

# Design Philosophy

Mission OS values consistency over novelty.

Interfaces should feel calm, predictable, accessible, and purposeful.

Every design decision should improve usability.

---

# Review Standard

Before merging, ask:

- Is this simpler?
- Is it maintainable?
- Is it documented?
- Is it secure?
- Does it improve the project?

If the answer is "no," reconsider the change.