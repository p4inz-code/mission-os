# MOS-INS-003 — Keyboard: Kickoff / Handoff Plan

**Prepared:** 2026-08-01 (extends `UI_SPRINT_KICKOFF.md`; follows the `MISSION_UI_IMPLEMENTATION_KICKOFF.md` pattern)
**Scope:** Preparation ONLY. No implementation, no QML/CMake/CI/token/test changes, no authoritative-doc edits, no MOS-INS-004.
**Status of predecessor screens:** MOS-INS-001 Welcome ✅ PASS (14/14), MOS-INS-002 Language ✅ PASS (17/17), CTest 4/4 green, 10 WSLg captures.

---

## 1. Authoritative Sources (read this session)

| Source | What it specifies for MOS-INS-003 |
|---|---|
| `docs/design/03_SCREEN_REGISTRY.md` | `MOS-INS-003 = Keyboard` (installer step 3 of 12) |
| `docs/wireframes/01_INSTALLER.md` | Screen order (#3 Keyboard); layout = Header → Stepper Navigation → Main Content → Help Panel (optional) → Back/Continue; UX rules = linear workflow, back always available, validation before continuing; states = empty/loading/error/success/offline |
| `docs/reference/01_INSTALLER.md` § Screen 09 — Keyboard & Input | Purpose: configure keyboard layout + platform familiarity; layout examples US / UK / German / French / Japanese / Indian / Custom; **users can test their keyboard before continuing**; platform presets **Linux (Default) / Windows / macOS** (Win: copy/paste, window mgmt, File Explorer behavior, modifier keys; macOS: Command key, Finder-style shortcuts, trackpad gestures, modifier remapping); presets switchable after install; keyboard layout + platform preset appear in the Configuration Summary |
| `MISSION_OS_DESIGN_BIBLE.md` / `MASTER_UX_SPECIFICATION.md` | Tokens-only, WCAG AA, keyboard-first, visible focus, reduced motion, calm/minimal, states anatomy |
| `05_COMPONENT_LIBRARY.md` / `06_DESIGN_SYSTEM.md` | Reuse over custom; never invent colors/spacing/animations/typography/components; Segmented Control specified but not yet implemented |
| `14_RESPONSIVE_RULES.md` | Reflow, collapse secondary panels, preserve navigation |
| `docs/development/UI_SPRINT_KICKOFF.md` | Locked visual principles + acceptance-criteria template reused for every installer screen |

**Note:** the reference doc numbers this screen "09" in its own flow; the registry/wireframe place Keyboard at **step 3** (MOS-INS-003, `totalSteps = 12`). Registry wins.

---

## 2. Exact Requirements for the Keyboard Screen

### Layout (same installer shell as 001/002)
Header (logo + wordmark + version) → Stepper ("Step 3 of 12 · Keyboard" + 12 segments) → Main Content → Help Panel (optional, wide only) → Back / Continue action bar.

### Components / content
1. **Keyboard layout list** — US, UK, German, French, Japanese, Indian, Custom. Single-select list; selected row highlighted; visible focus ring; Enter/Space/click selects. **No search/filter** (not specified for this screen — do not invent; only Screen 08 specified search).
2. **Keyboard test area** — reference: "Users can test their keyboard before continuing." A focused key-capture field that shows what the user types; must not trap focus (Escape exits/clears); screen-reader labeled.
3. **Platform preset selector** — Linux (Default) / Windows / macOS. Chip/radio group reusing the LanguageSelection region-chip pattern (Segmented Control not implemented — reuse inline chips, do NOT register a new component). Caption/help-panel note: presets can be changed at any time after installation (reference Screen 09).

### States (per wireframe)
empty · loading · error · success · offline — same banners/behavior as 001/002 (non-blocking loading; Continue disabled while loading/error; error banner + Retry).

### Signals / host wiring
- `continueRequested()`, `backRequested()`, `retryRequested()` — same as 001/002
- **`keyboardLayoutChangeRequested(string code)`** — e.g. `us`, `uk`, `de`, `fr`, `ja`, `in`, `custom`
- **`platformPresetChangeRequested(string preset)`** — `linux` | `windows` | `macos`
- Preselect first layout (US) + Linux preset **without emitting** on load (matches 002 contract).
- **Escape precedence** (same parent-vs-child rule as 002's search field): while the key-capture test area is focused, Escape clears/exits the test area (must not trap focus); elsewhere, root Escape → `backRequested()`.

### Accessibility
Keyboard-first (Tab/Shift+Tab/arrows/Enter/Space/Escape); visible focus ring (`MissionTheme.focusRing`); `Accessible` roles/names on list, test area, preset chips; 44px touch targets (`Spacing.minimumTouchTarget`); reduced-motion gating on all `Behavior`/loading animations; focus never trapped in the test area.

### Light/dark
`MissionTheme.darkMode` bindings only (same as 001/002 — verified by theme test).

### Responsive
`wideLayout = width >= 760` (help panel visible), `compactLayout = width < 640` — identical breakpoints to 001/002.

### Reduced motion
All color transitions and the loading animation gated on `!reducedMotion` (Behavior `animation:` group pattern, Qt 6.10-safe).

---

## 3. Existing Components / Tokens to Reuse (from 001/002)

| Asset | Reuse as |
|---|---|
| `LanguageSelection.qml` | **Structural template** — stepper, state banners, list delegate pattern (`objectName: "keyboardItem"+index`, focus ring, selected styling), selection caption, help panel, action bar, test-hook aliases. (The search/empty-overlay piece does **not** apply — Keyboard has no search.) |
| Region-chip pattern (regionItem) | Platform preset chips (`presetItem0..2`) |
| `MissionButton` | Back / Continue / Retry / Clear buttons |
| `MissionPage`, `MissionWindow` | Integration tests |
| Tokens: `Colors, Typography, Spacing, Radii, Elevation, Motion, MissionTheme` | Everything — no new values |
| `tst_language.qml` | Test template (`createScreenAt`, hosted Window, SignalSpy, keyboard-focus walk, state transitions, theme, responsive, reduced-motion) |

---

## 4. Dependencies / Blockers

1. **No new components required** — the key-capture area uses stock `TextField`-style behavior inline; presets reuse inline chips. No library registration needed. ✅
2. **Keyboard layout catalog is a static fixture** (like `languages` in 002); host service (xkbcommon) applies the real layout on signal — UI component is host-agnostic. ✅
3. **Focus-trapping risk in the test area** — must handle Escape + not swallow Tab. Implementation detail, not a blocker.
4. **qmlsc remains explicitly SKIPPED** on Ubuntu toolchain (honest, unchanged).
5. **No blocker from 001/002** — their patterns and tokens are proven and green.
6. "Custom" layout = list entry only; a full custom-layout editor is future work (not specified for this screen).

---

## 5. Implementation Order (tomorrow)

1. `src/libraries/ui/qml/org/mission/ui/KeyboardSelection.qml` — full screen (list + test area + presets + state banners + action bar + signals).
2. Register in `src/libraries/ui/qml/org/mission/ui/qmldir` + `MISSION_UI_QML_FILES` in `src/libraries/ui/CMakeLists.txt`.
3. `src/libraries/ui/tests/tst_keyboard.qml` — mirror `tst_language.qml` coverage (load, layout selection signal, test area, preset signal, signals, states, Continue-blocked, keyboard focus, arrows/Enter, responsive, integration, reduced motion, no-signal-on-load).
4. Register `mission-ui-installer-keyboard` in CTest (both runner branches) + CI count assertion **4 → 5** and add to the runtime loop in `.github/workflows/ci.yml`.
5. Build in WSL + full CTest (expect 5/5, qmlsc explicit SKIP).
6. WSLg visual captures (light/dark, preset selected, test area active, loading/error/offline, compact 480px, reduced motion).
7. Code review + final diff review; STOP (do NOT start MOS-INS-004).

---

## 6. First Coding Task (exact)

**Create `KeyboardSelection.qml`** (FocusScope, `implicitWidth: 1024`, `implicitHeight: 768`, `step: 3`, `totalSteps: 12`) with:
- `property var layouts: [us, uk, de, fr, ja, in, custom]` (label + code), preselect `us` non-emitting;
- `property var presets: [linux (default), windows, macos]`, preselect `linux` non-emitting;
- ListView of layouts (delegate objectName `keyboardItem<index>`, selected + focus-ring styling);
- key-capture test area (labeled, Escape-exits);
- preset chips (`presetItem<index>`, ActiveFocusOnTab);
- signals `keyboardLayoutChangeRequested(code)` + `platformPresetChangeRequested(preset)` + continue/back/retry;
- all five state banners, help panel (wide), Back/Continue action bar, Escape → backRequested;
- test-hook aliases for the suite.

---

**End of Plan**
