// Mission OS — UI Foundation Smoke Test
//
// Validates that the org.mission.ui module loads correctly, that the
// design token singletons resolve, and that MissionTheme correctly
// maps light/dark tokens.
//
// This is a build-time validation file used by the CI pipeline.
// It is NOT a runtime application.
//
// Usage:
//   qmlsc --verify SmokeTest.qml     # Static verification (compile check)
//   qmlscene SmokeTest.qml           # Runtime smoke test (exit 0 = PASS)
//
// Exit codes:
//   0 — all checks passed
//   1 — one or more checks failed

import QtQuick
import QtQuick.Controls
import org.mission.ui 1.0

Item {
    id: root

    // ── Module Load Validation ─────────────────────────────────────
    // Verify that all design token singletons resolve correctly
    readonly property bool colorsLoaded:        Colors !== undefined
    readonly property bool typographyLoaded:    Typography !== undefined
    readonly property bool spacingLoaded:       Spacing !== undefined
    readonly property bool radiiLoaded:         Radii !== undefined
    readonly property bool elevationLoaded:     Elevation !== undefined
    readonly property bool motionLoaded:        Motion !== undefined
    readonly property bool themeLoaded:         MissionTheme !== undefined

    // ── Token Value Validation ─────────────────────────────────────
    // Validate that key token values are accessible and reasonable
    readonly property bool primaryColorValid:   Qt.colorEqual(Colors.primary, "#2563EB")
    readonly property bool spacingExists:       Spacing.paddingPage > 0
    readonly property bool typographyExists:    Typography.title.size > 0
    readonly property bool radiiExists:         Radii.card > 0
    readonly property bool elevationExists:     Elevation.card > 0
    readonly property bool motionExists:        Motion.fadeIn > 0

    // ── Component Validation ───────────────────────────────────────
    // Verify that foundation components exist (not type errors)
    readonly property bool missionWindowExists: typeof MissionWindow !== 'undefined'
    readonly property bool missionPageExists:   typeof MissionPage !== 'undefined'

    // ── Static Validation ──────────────────────────────────────────
    // Module load + token value checks, evaluated at component creation.
    readonly property bool staticValid: [
        colorsLoaded, typographyLoaded, spacingLoaded,
        radiiLoaded, elevationLoaded, motionLoaded,
        themeLoaded, primaryColorValid, spacingExists,
        typographyExists, radiiExists, elevationExists,
        motionExists, missionWindowExists, missionPageExists
    ].every(v => v === true)

    // ── Theme Validation (runtime, light + dark) ───────────────────
    // MissionTheme.darkMode toggles between light and dark token sets;
    // readonly bindings on MissionTheme re-evaluate when darkMode changes.
    function themeChecksValid() {
        if (!themeLoaded) {
            return false
        }

        // Light theme (default)
        MissionTheme.darkMode = false
        var lightBackground = Qt.colorEqual(MissionTheme.background, Colors.background)
        var lightText       = Qt.colorEqual(MissionTheme.textPrimary, Colors.textPrimary)
        var lightSurface    = Qt.colorEqual(MissionTheme.surface, Colors.surface)

        // Dark theme
        MissionTheme.darkMode = true
        var darkBackground  = Qt.colorEqual(MissionTheme.background, Colors.darkBackground)
        var darkText        = Qt.colorEqual(MissionTheme.textPrimary, Colors.darkTextPrimary)
        var darkSurface     = Qt.colorEqual(MissionTheme.surface, Colors.darkSurface)
        var focusRingValid  = Qt.colorEqual(MissionTheme.focusRing, Colors.focusRing)

        // Restore default theme mode
        MissionTheme.darkMode = false

        console.log("[SmokeTest] Theme light background: " + lightBackground);
        console.log("[SmokeTest] Theme light text: " + lightText);
        console.log("[SmokeTest] Theme light surface: " + lightSurface);
        console.log("[SmokeTest] Theme dark background: " + darkBackground);
        console.log("[SmokeTest] Theme dark text: " + darkText);
        console.log("[SmokeTest] Theme dark surface: " + darkSurface);
        console.log("[SmokeTest] Theme focusRing: " + focusRingValid);

        return lightBackground && lightText && lightSurface &&
               darkBackground && darkText && darkSurface && focusRingValid
    }

    // ── Report ─────────────────────────────────────────────────────
    Component.onCompleted: {
        if (typeof Qt !== 'undefined') {
            console.log("[SmokeTest] Colors loaded: " + colorsLoaded);
            console.log("[SmokeTest] Typography loaded: " + typographyLoaded);
            console.log("[SmokeTest] Spacing loaded: " + spacingLoaded);
            console.log("[SmokeTest] Radii loaded: " + radiiLoaded);
            console.log("[SmokeTest] Elevation loaded: " + elevationLoaded);
            console.log("[SmokeTest] Motion loaded: " + motionLoaded);
            console.log("[SmokeTest] Theme loaded: " + themeLoaded);
            console.log("[SmokeTest] MissionWindow loaded: " + missionWindowExists);
            console.log("[SmokeTest] MissionPage loaded: " + missionPageExists);

            var themeValid = themeChecksValid()
            var allValid   = staticValid && themeValid
            console.log("[SmokeTest] All valid: " + allValid);

            // Non-zero exit on failure makes this usable as a CI gate.
            Qt.exit(allValid ? 0 : 1)
        }
    }
}
