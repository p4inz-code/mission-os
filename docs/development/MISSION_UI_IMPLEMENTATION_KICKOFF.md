# mission-ui Implementation Kickoff — Next-Session Execution Plan

**Prepared:** 2026-08-01 (post-RC6 lock, commit `3ccc8b1`; extends `docs/development/UI_SPRINT_KICKOFF.md`)
**Goal:** Move `mission-ui` (`src/libraries/ui/`, module `org.mission.ui`) from **CANDIDATE → runtime-validated** (smoke test → build/CI → runtime validation), then begin `MOS-INS-001` Installer Welcome.
**Constraints:** No production code modified in the prep session. Do NOT rebuild the ISO. Do NOT modify the design system or invent tokens. No broad repo audit.

---

## 1. Current State (verified 2026-08-01)

**Source present and complete (16 files):**
- `src/libraries/ui/CMakeLists.txt` — Qt6 (Core/Qml/Quick/QuickControls2/Svg) + KF6 (Kirigami/CoreAddons/I18n); `qt6_add_qml_module(mission-ui URI org.mission.ui)`; library target; optional `Qt6QmlTools` block (`qt6_qml_type_registration` / `qt6_generate_qmltypes` guarded by `if(Qt6QmlTools_FOUND)`); install rules.
- `qml/org/mission/ui/` — token singletons `Colors`, `Typography`, `Spacing`, `Radii`, `Elevation`, `Motion`; `MissionTheme` (light/dark via `darkMode`); components `MissionWindow` (Kirigami.ApplicationWindow), `MissionPage`; `SmokeTest.qml`; `qmldir`.
- `src/missionuiplugin.cpp` + `include/mission/missionuiplugin.h` (QQmlEngineExtensionPlugin); `src/version.cpp` + `include/mission/version.h`.

**Build wiring:** root `CMakeLists.txt` has `option(BUILD_TESTING ON)` and `add_subdirectory(src/libraries/ui)`; `Makefile` has `cmake-configure` / `cmake-build` / `cmake-test` (`ctest --output-on-failure`).

**CI:** `.github/workflows/ci.yml` has a `cmake` job (CMake / UI) — installs Qt6/KF6 apt packages, `cmake .. -DBUILD_TESTING=ON`, `cmake --build build`. **It does NOT run ctest, qmlsc, or any QML test.**

**Docs:** `docs/engineering/TESTING_STRATEGY.md` (unit tests: C/C++ → `ctest`, QML → Qt Test framework / `qmltestrunner`); `docs/engineering/BUILD_ARCHITECTURE.md` (unit tests incl. Qt Test).

---

## 2. Verified Gaps (why it is still CANDIDATE)

| # | Gap | Evidence |
|---|-----|----------|
| G1 | **No CTest wiring** — `include(CTest)`/`enable_testing()`/`add_test` absent everywhere; `Makefile cmake-test` passes with **0 tests** | repo grep; root + ui CMakeLists |
| G2 | **SmokeTest.qml is log-only** — prints `[SmokeTest] All valid: …` but has **no pass/fail exit code** and is **not registered as a test**; not usable as a CI gate as-is | SmokeTest.qml (Component.onCompleted console.log only) |
| G3 | **CI apt list missing `qt6-declarative-dev-tools`** → `Qt6QmlTools_FOUND` false → `qmlsc`/`qmlcachegen`/`qmlformat`/`qmltyperegistrar` absent; the `if(Qt6QmlTools_FOUND)` blocks in CMakeLists are skipped silently | ci.yml `cmake` job apt list; research (Ubuntu 24.04: `qt6-declarative-dev-tools` provides qmlsc + Qt6QmlTools CMake) |
| G4 | **CI never executes the UI** — no ctest step, no `qmlsc --verify`, no QML runner; mission-ui is compile-checked only | ci.yml `cmake` job (Configure + Build steps only) |
| G5 | **No runtime validation environment** — Plasma/Wayland session check is Linux/QEMU host-bound (RC6 evidence is host-bound; Windows checkout cannot reproduce) | RC6-REPORT §1/§5; this checkout is Windows |

---

## 3. Next-Session Execution Plan (exact files + order)

### Phase 0 — Toolchain check on the Linux build host (no file changes)
1. Confirm `qmlsc --version`, `qmlcachegen --version`, `qmlformat --version` are on PATH after installing `qt6-declarative-dev-tools`.
2. Confirm a QML runner binary exists: try `qml6` then `qmlscene` (package candidates: `qt6-declarative-tools` / `qml6-toolbox` / `qt6-declarative-dev-tools`). Record which one works.
3. Confirm `cmake .. -DBUILD_TESTING=ON` configures with `Qt6QmlTools_FOUND=TRUE`.

### Phase 1 — Make the smoke test a real gate
**Files to touch (production code, done in the implementation session):**
- `src/libraries/ui/qml/org/mission/ui/SmokeTest.qml` — convert to pass/fail:
  - Keep existing singleton/component validation properties (`allValid`).
  - Add **MissionTheme coverage** (currently only existence checks): `MissionTheme.darkMode = false` → assert `background == Colors.background`, `textPrimary == Colors.textPrimary`; `MissionTheme.darkMode = true` → assert `background == Colors.darkBackground`, `textPrimary == Colors.darkTextPrimary`; assert `surface`/`focusRing` resolve; reset `darkMode = false` after.
  - On completion: `Qt.exit(allValid ? 0 : 1)` (or use a QtTest `TestCase` via `qmltestrunner` per TESTING_STRATEGY) so a failed token/theme check fails CI.
- *(Preferred, matches TESTING_STRATEGY.md):* add a QtTest-based smoke test, e.g. `src/libraries/ui/tests/tst_smoke.qml` (or under an existing `tests/` convention) with `TestCase` + `qmltestrunner`; keep `SmokeTest.qml` as the static-verify artifact.

### Phase 2 — Wire CTest
**Files to touch:**
- `CMakeLists.txt` (root) — add `include(CTest)` (honors `BUILD_TESTING`).
- `src/libraries/ui/CMakeLists.txt` — register tests:
  - Static: `add_test(NAME mission-ui-qmlsc COMMAND qmlsc --verify ${CMAKE_CURRENT_SOURCE_DIR}/qml/org/mission/ui/SmokeTest.qml)` (guarded by `Qt6QmlTools_FOUND`).
  - Runtime: `add_test(NAME mission-ui-smoke COMMAND <qml-runner> ${CMAKE_CURRENT_SOURCE_DIR}/qml/org/mission/ui/SmokeTest.qml)` (or `qmltestrunner` for the QtTest variant), with `QT_QML_IMPORT_PATH` set so `org.mission.ui` + Kirigami resolve from the build tree.
- `Makefile` — no change strictly required (`cmake-test` already runs `ctest`); optionally add a `cmake-smoke` convenience target.

### Phase 3 — CI validation
**File to touch:** `.github/workflows/ci.yml` (`cmake` job)
- Add `qt6-declarative-dev-tools` (and the runner package identified in Phase 0) to the apt install list.
- Add after Build: `cd build && ctest --output-on-failure` (and optionally an explicit `qmlsc --verify` step).
- Expected result: the `cmake` job fails if any token/theme assertion breaks — closing G1/G2/G3/G4.

### Phase 4 — Linux Plasma/Wayland runtime validation (host work; no repo change required)
1. On the Linux/QEMU host, build + run the smoke test under a Wayland session (or `weston`/`kwin_wayland` nested) and confirm `[SmokeTest] All valid: true`.
2. Optionally launch a minimal `MissionWindow` app to confirm the module renders (validation of `org.mission.ui` + Kirigami import in a real session).
3. Record evidence (this closes the RC6-REPORT §7.4 "live Plasma session validation" gate).

### Phase 5 — Then begin `MOS-INS-001` Installer Welcome
Per `docs/wireframes/01_INSTALLER.md` + `UI_SPRINT_KICKOFF.md` §7. Do NOT start this until Phases 1–4 are green.

---

## 4. Blockers Discovered (must be resolved before/at implementation)

1. **B1 — CI tooling package missing:** `qt6-declarative-dev-tools` is not in the `cmake` job apt list → `Qt6QmlTools_FOUND` false, `qmlsc` absent. Fix is a one-line apt addition (Phase 3).
2. **B2 — No test infrastructure wired:** zero CTest registration; the `Makefile cmake-test` target is currently a no-op pass. Requires Phase 2 wiring.
3. **B3 — SmokeTest is not a gate:** log-only, no exit code; must gain pass/fail + MissionTheme coverage (Phase 1) before it can guard CI.
4. **B4 — QML runner binary uncertain on ubuntu-latest:** `qml6` vs `qmlscene` package name must be confirmed on the host (Phase 0 step 2).
5. **B5 — Runtime validation is host-bound:** Plasma/Wayland session check cannot run on this Windows checkout; requires the Linux/QEMU build host (same limitation documented in RC6-REPORT §1).

---

**End of Plan**
