# Mission OS UI/UX Sprint — Kickoff Brief

**Prepared:** 2026-08-01 (post-RC6 lock, commit `3ccc8b1`)
**Scope:** Prepare the UI/design sprint. No UI implementation in this session.
**Source of truth:** The authoritative design docs below. Do NOT redesign Mission OS — translate existing specs into implementation only.

---

## 1. Current Design-System Status

**Authoritative documents (all populated — use these):**

| Area | Docs |
|------|------|
| Design Bible (single source of truth) | `docs/design-bible/MISSION_OS_DESIGN_BIBLE.md` |
| Master UX Specification | `docs/ux/MASTER_UX_SPECIFICATION.md` |
| Design system (numbered) | `docs/design/01_INFORMATION_ARCHITECTURE.md` … `15_CLAUDE_DESIGN_HANDOFF.md` |
| Wireframes | `docs/wireframes/01_INSTALLER.md` … `15_SHARED_COMPONENTS.md` |
| Reference specs | `docs/reference/01_INSTALLER.md` … `15_ACCESSIBILITY.md` |

**⚠️ Empty stubs — do NOT use as source of truth (0-byte placeholders):**
- `design/*.md` (UI_SPRINT.md, DESIGN_SYSTEM.md, UI_PRINCIPLES.md, COMPONENT_INVENTORY.md, DESIGN_CONTEXT.md, DESIGN_DECISIONS.md, DESIGN_REVIEW_LOG.md, README.md)
- `design/ui/*/` per-screen files (requirements.md, wireframe.md, etc.), `design/screens/SCREEN_PROGRESS.md`
- `docs/design/screens/SCREEN_REGISTRY.md`, `docs/design/components/COMPONENT_REGISTRY.md` (use `docs/design/03_SCREEN_REGISTRY.md` + `05_COMPONENT_LIBRARY.md` instead)

**Implementation status — mission-ui (`src/libraries/ui/`, module `org.mission.ui`):**
- ✅ **Implemented (design tokens):** `Colors`, `Typography`, `Spacing`, `Radii`, `Elevation`, `Motion` (QML singletons), `MissionTheme` (light/dark via `darkMode`), `MissionWindow` (Kirigami.ApplicationWindow wrapper), `MissionPage` (page/surface container), `SmokeTest`, `qmldir`, C++ plugin + CMake build.
- ⚠️ **Status: CANDIDATE** (per RC6-REPORT): **0 tests**, not runtime-validated, CI `cmake` job exists (installs Qt6/KF6, configures + builds) but end-to-end green not yet proven.

> **Update (2026-08-09):** The UI sprint described below COMPLETED after this brief was
> written. mission-ui now ships **50 production QML components (+ SmokeTest test
> artifact) and 40 QtTest suites (82 CTest registrations)**, with host-absent
> defaults neutral (no fabricated data — see commit `b07f061`). It remains
> **CANDIDATE**: not runtime-validated in a live Plasma session and with no host
> integration for the Mission Hub / Diagnostics / Recovery screens.
- Next step per RC6-REPORT §7.4: mission-ui CANDIDATE → **implemented** (QML smoke tests, CI cmake job, live Plasma/Wayland validation).

---

## 2. Locked Visual Principles (do not renegotiate)

From `MISSION_OS_DESIGN_BIBLE.md` + `MASTER_UX_SPECIFICATION.md` + `06_DESIGN_SYSTEM.md`:

- **Brand:** Privacy by Default · Security without Fear · Professional Simplicity · Calm Computing · Long-Term Consistency.
- **Visual identity:** Premium, Minimal, Modern, Technical, Calm, Spacious, Purposeful. No visual noise; every element has a reason to exist. "Engineered, not decorated."
- **Design language:** Clean geometry, consistent spacing, rounded corners, soft depth, clear hierarchy, large touch targets, strong readability.
- **Color:** Semantic, not decorative. Neutral surfaces + restrained accents. Light / Dark / High-Contrast themes. WCAG AA minimum (AAA where practical). Color is never the only state indicator.
- **Typography:** Calm, highly legible. Hierarchy via size + weight + spacing. Minimal font variation. System stack (Noto Sans) + monospace for code.
- **Layout:** Alignment, predictability, balance, spaciousness. Standard window anatomy: Title Bar → Toolbar → Navigation → Content → Context Panel (optional) → Status Bar (optional). Max nav depth 4; three-click rule.
- **Motion:** Only to explain / guide / confirm. Fast, subtle, consistent. Reduced-motion support mandatory.
- **Icons:** Simple, geometric, uniform stroke, recognizable. Sizes 16/20/24/32/48/64/128 px.
- **Components:** Reuse over custom. Shared spacing, states, and behavior. Never invent colors/spacing/animations/typography/component styles.
- **Interaction:** Predictable, forgiving, reversible where possible; immediate feedback for significant actions.
- **Accessibility:** Keyboard-first (Tab/Shift+Tab/arrows/Enter/Space/Escape), visible focus mandatory, screen readers, high contrast, reduced motion, text scaling, 44px minimum touch target.
- **Never:** Unnecessary animations, intrusive notifications, hidden settings, misleading dialogs, forced sign-ins, advertising, telemetry without consent, inconsistent UI patterns.

---

## 3. Existing Component Inventory (specified in `05_COMPONENT_LIBRARY.md`)

- **Navigation:** Top Panel, Sidebar, Dock, Breadcrumb, Tabs, Navigation Rail, Pagination, Toolbar, Status Bar
- **Buttons:** Primary, Secondary, Tertiary, Destructive, Icon, FAB, Toggle, Split (states: default/hover/focus/pressed/disabled/loading)
- **Inputs:** Text, Password, Search, Number, TextArea, Date Picker, Time Picker, Dropdown, ComboBox, File Picker
- **Selection:** Checkbox, Radio, Toggle Switch, Segmented Control, Multi Select, Chip
- **Cards:** Information, Application, Statistics, Recommendation, Device, Update, Dashboard
- **Lists:** Standard, Compact, Detailed, Tree, Grid, Table
- **Dialogs:** Confirmation, Warning, Error, Success, Information, Progress, Authentication (nesting prohibited)
- **Feedback:** Toast, Banner, Alert, Progress Bar, Progress Ring, Spinner, Skeleton Loader
- **Overlays:** Notification Center, Quick Settings, Search Overlay, Command Palette, Clipboard Manager, Screenshot Overlay, Workspace Switcher, Volume/Brightness overlays
- **Empty/Error/Loading states:** required patterns defined (illustration/icon + explanation + primary action).

**Implemented in QML today:** tokens + MissionTheme + MissionWindow + MissionPage + SmokeTest only.
**Not yet implemented:** the button/input/card/list/dialog component library, icons, overlays.

---

## 4. Planned Screen / Flow Order (from `03_SCREEN_REGISTRY.md` + wireframes)

1. **Installer** — MOS-INS-001 Welcome → 002 Language → 003 Keyboard → 004 Network → 005 Privacy → 006 Disk → 007 Partition → 008 User → 009 Encryption → 010 Summary → 011 Installation → 012 Completion
2. **Lock Screen** — MOS-LCK-001..004 (Lock, Login, PIN, Recovery)
3. **Desktop** — MOS-DES-001..008
4. **Mission Hub** — MOS-HUB-001..010
5. **Settings** — MOS-SET-001..016
6. **Privacy Center** — MOS-PRI-001..006
7. **Security Center** — MOS-SEC-001..007
8. **Recovery Center** — MOS-REC-001..006
9. **Diagnostics** — MOS-DIA-001..008
10. **Mission Store** — MOS-STR-001..007 (registry order; wireframe file numbering lists File Manager 10th instead — resolve this discrepancy when scheduling)
11. **File Manager** — MOS-FIL-001..006
12. **Update Manager** — MOS-UPD-001..005
13. **Driver Manager** — MOS-DRV-001..005
14. **Network** — MOS-NET-001..006
15. **Accessibility** — MOS-ACC-001..006
16. **Shared Components + Global Overlays** — throughout

**First-boot flow** (`04_USER_FLOWS.md`): Power On → Installer (Language→Keyboard→Network→Privacy→Disk→User→Encryption→Install) → Restart → Login → Desktop.

---

## 5. First Implementation Target

**🟢 Mission Installer — Welcome screen `MOS-INS-001`** (with mission-ui stabilization as prerequisite).

- **Why:** (a) it is screen #1 in the registry and wireframe order; (b) it has the richest supporting spec (`docs/wireframes/01_INSTALLER.md`, `docs/reference/01_INSTALLER.md`, `design/prompts/INSTALLER_DESIGN_PROMPT.md`); (c) the RC6-REPORT gates the sprint on first hardening mission-ui, which the Installer will then exercise.
- **Prerequisite (do first):** mission-ui CANDIDATE → implemented — add QML smoke test for the tokens/theme, prove the CI `cmake` job green, runtime-check in a Plasma/Wayland session (Linux/QEMU host).
- **Approach:** Build `MOS-INS-001` as a QML screen on `org.mission.ui` per the installer wireframe layout: Header → Stepper Navigation → Main Content → Help Panel (optional) → Back/Continue. Linear workflow, validation before continue, back always available, destructive actions confirm.

---

## 6. Dependencies / Blockers

| # | Item | Impact |
|---|------|--------|
| 1 | mission-ui has **0 tests** and is CANDIDATE | Must add smoke tests + green CI cmake job before screens can be trusted |
| 2 | No runtime Plasma/Wayland validation possible on this Windows checkout | Live validation requires Linux/QEMU build host (RC6 evidence is host-bound) |
| 3 | Component library (buttons, inputs, cards, dialogs) **not yet implemented in QML** | First screens must build minimal shared components from the token layer |
| 4 | `desktop/sddm/sddm.conf` + `org.mission.plasma.desktop` deployment unresolved (KNOWN_ISSUES #13) | Affects desktop/session screens later; not blocking Installer |
| 5 | `design/` root stubs + `design/ui/*` are empty | Do not reference them; stick to `docs/design/*` / `docs/ux` / `docs/design-bible` / `docs/wireframes` / `docs/reference` |
| 6 | Icon set / SDDM theme / GRUB theme still default Breeze | Out of scope for first screen; tracked for later sprint steps |

---

## 7. Acceptance Criteria — First Screen (Installer Welcome, MOS-INS-001)

Derived from `docs/wireframes/01_INSTALLER.md`, `MASTER_UX_SPECIFICATION.md`, `06_DESIGN_SYSTEM.md`, and RC6-REPORT.

1. **Layout** matches the installer wireframe: Header → Stepper Navigation → Main Content → Help Panel (optional) → Back/Continue; linear workflow with validation before Continue and always-available Back.
2. **Design-system compliance:** uses only `org.mission.ui` tokens (Colors, Typography, Spacing, Radii, Elevation, Motion, MissionTheme); no invented colors/spacing/typography/animation values.
3. **Theme support:** renders correctly in light and dark modes (`MissionTheme.darkMode`); state never conveyed by color alone.
4. **Accessibility:** WCAG AA contrast; fully keyboard operable (Tab/Shift+Tab/Enter/Escape); visible focus indicators; screen-reader labels; reduced-motion respected; 44px touch targets.
5. **States:** all five installer states — empty/loading/error/success/offline — handled per `docs/wireframes/01_INSTALLER.md` and `05_COMPONENT_LIBRARY.md`; non-blocking loading (no spinner-only).
6. **Consistency:** uses only registered components (or adds new ones through the design-review path); global layout anatomy per `MASTER_UX_SPECIFICATION.md` §3.
7. **Runtime validation:** loads in a Plasma/Wayland session (Linux host) and/or `qmlscene` smoke run; QML smoke test added; CI `cmake` job green.
8. **Registry alignment:** screen ID `MOS-INS-001` matches `docs/design/03_SCREEN_REGISTRY.md`; flow matches `04_USER_FLOWS.md` first-boot journey.
9. **No scope creep:** no Beta claims, no unrelated RC6 fixes, no ISO rebuilds.

---

**End of Brief**
