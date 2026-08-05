// Mission OS — UI Foundation Smoke Test (QtTest)
//
// Runtime validation of the org.mission.ui design token foundation.
// Mirrors the assertions in SmokeTest.qml as a proper QtTest TestCase
// so it can be executed by qmltestrunner (per docs/engineering/
// TESTING_STRATEGY.md: QML → Qt Test framework / qmltestrunner).
//
// Coverage:
//   - module + token singleton loading (Colors, Typography, Spacing,
//     Radii, Elevation, Motion, MissionTheme)
//   - token value sanity
//   - foundation components resolve (MissionWindow, MissionPage)
//   - MissionTheme light/dark token mapping + focusRing
//
// Run via qmltestrunner (see CMakeLists.txt CTest registration):
//   qmltestrunner -import <build>/src/libraries/ui/qml \
//                 -input src/libraries/ui/tests/tst_smoke.qml
//
// Exit code: 0 = all checks passed; non-zero = failure (CI gate).

import QtQuick
import QtTest
import org.mission.ui 1.0

TestCase {
    id: root
    name: "MissionUiFoundation"

    // ── Module + token singleton loading ─────────────────────────────
    function test_tokenSingletonsLoad() {
        verify(typeof Colors !== "undefined")
        verify(typeof Typography !== "undefined")
        verify(typeof Spacing !== "undefined")
        verify(typeof Radii !== "undefined")
        verify(typeof Elevation !== "undefined")
        verify(typeof Motion !== "undefined")
        verify(typeof MissionTheme !== "undefined")
    }

    // ── Token value sanity ───────────────────────────────────────────
    function test_tokenValues() {
        verify(Qt.colorEqual(Colors.primary, "#2563EB"))
        verify(Spacing.paddingPage > 0)
        verify(Typography.title.size > 0)
        verify(Radii.card > 0)
        verify(Elevation.card > 0)
        verify(Motion.fadeIn > 0)
        // Easing tokens are nested QtObjects carrying the Easing enum
        // type (+ optional bezier control points).
        verify(Motion.easingStandard.type === Easing.BezierSpline)
        verify(Motion.easingStandard.bezierCurve.length === 4)
        verify(Motion.easingLinear.type === Easing.Linear)
        // The contentOn* tokens (QML-safe names for the Material-style
        // on-<surface> tokens) must resolve to their canonical values.
        verify(Qt.colorEqual(Colors.contentOnPrimary, "#FFFFFF"))
        verify(Qt.colorEqual(Colors.contentOnErrorContainer, "#7F1D1D"))
        // MissionTheme forwards the content-on-semantic tokens so
        // MissionButton's Destructive variant resolves a real text color
        // (audit fix: contentOnError was defined in Colors but not
        // forwarded by MissionTheme).
        verify(Qt.colorEqual(MissionTheme.contentOnError, Colors.contentOnError))
        verify(Qt.colorEqual(MissionTheme.contentOnError, "#FFFFFF"))
    }

    // ── Foundation components resolve ────────────────────────────────
    function test_componentsResolve() {
        verify(typeof MissionWindow !== "undefined")
        verify(typeof MissionPage !== "undefined")
    }

    // ── Foundation components actually instantiate ───────────────────
    // typeof above only resolves the type; instantiating MissionPage
    // proves the component file compiles and its token bindings evaluate
    // to real values (bindings silently yield defaults when the token
    // singletons fail to load).
    function test_missionPageInstantiation() {
        var page = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionPage { pageTitle: 'Smoke' }",
            root, "MissionPageInstance")
        verify(page !== null)
        compare(page.padding, Spacing.paddingPage)
        compare(page.pageTitle, "Smoke")
        page.destroy()
    }

    // ── MissionTheme light mode mapping ──────────────────────────────
    function test_themeLightMode() {
        MissionTheme.darkMode = false
        verify(Qt.colorEqual(MissionTheme.background, Colors.background))
        verify(Qt.colorEqual(MissionTheme.surface, Colors.surface))
        verify(Qt.colorEqual(MissionTheme.textPrimary, Colors.textPrimary))
    }

    // ── MissionTheme dark mode mapping + focusRing ───────────────────
    function test_themeDarkMode() {
        MissionTheme.darkMode = true
        verify(Qt.colorEqual(MissionTheme.background, Colors.darkBackground))
        verify(Qt.colorEqual(MissionTheme.surface, Colors.darkSurface))
        verify(Qt.colorEqual(MissionTheme.textPrimary, Colors.darkTextPrimary))
        verify(Qt.colorEqual(MissionTheme.focusRing, Colors.focusRing))
    }

    // Reset theme mode after each test so tests never leak state.
    function cleanup() {
        MissionTheme.darkMode = false
    }
}
