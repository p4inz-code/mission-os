# Mission OS — Documentation Index

Mission OS documentation is organized into the directories below. The top-level
[`README.md`](../README.md) covers the project overview, current status, build
and contribution guidance.

## Where to start

| Need | Start here |
|------|------------|
| What is Mission OS? | [`core/`](core/) — VISION, MISSION_PHILOSOPHY, PRINCIPLES, MISSION_OS_MASTER_SPEC |
| Current status / release state | [`development/IMPLEMENTATION_STATUS.md`](development/IMPLEMENTATION_STATUS.md), [`development/KNOWN_ISSUES.md`](development/KNOWN_ISSUES.md), [`development/BETA_RELEASE_REPORT.md`](development/BETA_RELEASE_REPORT.md) |
| Build the ISO / run tests | [`../BUILD.md`](../BUILD.md) |
| System architecture | [`engineering/`](engineering/) — ARCHITECTURE, MODULE_MAP, SECURITY_ARCHITECTURE, RUNTIME_ARCHITECTURE |
| Design language & UI | [`design-bible/MISSION_OS_DESIGN_BIBLE.md`](design-bible/MISSION_OS_DESIGN_BIBLE.md), [`design/`](design/), [`wireframes/`](wireframes/), [`ux/`](ux/) |
| Product plans | [`product/`](product/) — ROADMAP, MILESTONES, RELEASE_STRATEGY |
| QA checklists | [`qa/`](qa/) — RELEASE_CHECKLIST, UI_CHECKLIST, SECURITY_CHECKLIST |
| Developer guides | [`developer/`](developer/) — CODING_STANDARDS, TESTING_GUIDELINES, UI_ARCHITECTURE |

## Directory map

- **`core/`** — Mission OS vision, philosophy, principles, master specification, glossary.
- **`engineering/`** — Architecture, module map (25 modules), security, runtime, build, IPC, testing strategy, engineering gates.
- **`design/`** — Numbered design system documents (information architecture → design handoff).
- **`design-bible/`** — The single source of truth for the Mission OS design language.
- **`ux/`** — Master UX specification.
- **`wireframes/`** — Per-screen wireframes (installer → accessibility, shared components).
- **`reference/`** — Per-feature reference specifications (01 installer → 15 accessibility).
- **`product/`** — Roadmap, milestones, release strategy, supported hardware, audit report.
- **`qa/`** — Release, UI, security and performance checklists, bug report template.
- **`developer/`** — Coding standards, error handling, state management, testing, UI architecture, security.
- **`development/`** — Implementation status, known issues, technical debt, module audit, RC6 report, test plan. (The P15/P16 evidence report lives in [`build/p15-p16-report.md`](../build/p15-p16-report.md).)
- **`templates/`** — ADR, architecture, design, spec and troubleshooting templates.
- **`specifications/`** — Linked specification index (`README.md`).

## Evidence & reports

- [`development/BETA_RELEASE_REPORT.md`](development/BETA_RELEASE_REPORT.md) — **Open Beta release report (2026-08-09)** — release status, ISO filename/size/SHA256, validation performed, tester workflow.
- [`../build/p15-p16-report.md`](../build/p15-p16-report.md) — P15/P16 installed-system boot + offline install verification (2026-08-09).
- [`development/RC6-REPORT.md`](development/RC6-REPORT.md) — RC6 release report (2026-08-01; partially superseded, see its update note).
- [`development/25-MODULE-AUDIT.md`](development/25-MODULE-AUDIT.md) — per-module implementation audit.
