// Mission OS — UI Foundation Smoke Test
//
// Validates that the org.mission.ui module loads correctly and
// design tokens / theme components are accessible.
//
// This is a build-time validation file used by the CI pipeline.
// It is NOT a runtime application.
//
// Usage:
//   qmlsc --verify SmokeTest.qml   # Static verification
//   qmlscene SmokeTest.qml          # Runtime smoke test

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
    readonly property bool primaryColorValid:   Colors.primary === "#2563EB"
    readonly property bool spacingExists:       Spacing.paddingPage > 0
    readonly property bool typographyExists:    Typography.title.size > 0
    readonly property bool radiiExists:         Radii.card > 0
    readonly property bool elevationExists:     Elevation.card > 0
    readonly property bool motionExists:        Motion.fadeIn > 0

    // ── Theme Validation ───────────────────────────────────────────
    readonly property bool themeBackground:     MissionTheme.background !== undefined
    readonly property bool themeText:           MissionTheme.textPrimary !== undefined

    // ── Component Validation ───────────────────────────────────────
    // Verify that foundation components exist (not type errors)
    readonly property bool missionWindowExists: typeof MissionWindow !== 'undefined'
    readonly property bool missionPageExists:   typeof MissionPage !== 'undefined'

    // ── Report ─────────────────────────────────────────────────────
    readonly property bool allValid: [
        colorsLoaded, typographyLoaded, spacingLoaded,
        radiiLoaded, elevationLoaded, motionLoaded,
        themeLoaded, primaryColorValid, spacingExists,
        typographyExists, radiiExists, elevationExists,
        motionExists, themeBackground, themeText,
        missionWindowExists, missionPageExists
    ].every(v => v === true)

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
            console.log("[SmokeTest] All valid: " + allValid);
        }
    }
}
