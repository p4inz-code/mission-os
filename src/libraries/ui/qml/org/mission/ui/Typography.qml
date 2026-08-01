// Mission OS Design Tokens — Typography
//
// Typography scale and roles for the Mission OS design system.
// All sizes in pixels (px), converted to pt for print where needed.
//
// Font family: System default (Noto Sans on Linux)
// Fallback stack: system-ui, -apple-system, Segoe UI, Roboto, sans-serif

pragma Singleton
import QtQuick

QtObject {
    // ── Font Families ──────────────────────────────────────────────
    readonly property string fontFamily:          "system-ui, -apple-system, 'Segoe UI', Roboto, 'Noto Sans', sans-serif"
    readonly property string fontFamilyMono:      "'JetBrains Mono', 'Fira Code', 'Cascadia Code', 'Consolas', monospace"
    readonly property string fontFamilyDisplay:   "system-ui, -apple-system, 'Segoe UI', Roboto, 'Noto Sans', sans-serif"

    // ── Font Sizes (px) ────────────────────────────────────────────
    readonly property int sizeCaption:            12
    readonly property int sizeBodySmall:          13
    readonly property int sizeBody:               14
    readonly property int sizeBodyLarge:          16
    readonly property int sizeSubtitle:           18
    readonly property int sizeTitle:              20
    readonly property int sizeTitleLarge:         24
    readonly property int sizeHeadline:           28
    readonly property int sizeHeadlineLarge:      32
    readonly property int sizeDisplay:            40
    readonly property int sizeDisplayLarge:       48

    // ── Font Weights ───────────────────────────────────────────────
    readonly property int weightRegular:          Font.Normal
    readonly property int weightMedium:           Font.DemiBold
    readonly property int weightSemibold:         Font.DemiBold
    readonly property int weightBold:             Font.Bold

    // ── Line Heights ───────────────────────────────────────────────
    readonly property real lineHeightTight:       1.15
    readonly property real lineHeightNormal:      1.35
    readonly property real lineHeightRelaxed:     1.5
    readonly property real lineHeightLoose:       1.75

    // ── Letter Spacing ─────────────────────────────────────────────
    readonly property real letterSpacingTight:    -0.02
    readonly property real letterSpacingNormal:   0.0
    readonly property real letterSpacingWide:     0.02
    readonly property real letterSpacingCaps:     0.05

    // ── Typography Roles ───────────────────────────────────────────
    // Named text styles for consistent use across the UI

    // Display
    readonly property QtObject displayLarge: QtObject {
        readonly property string family: "system-ui, -apple-system, 'Segoe UI', Roboto, 'Noto Sans', sans-serif"
        readonly property int size: 48
        readonly property int weight: Font.Bold
        readonly property real lineHeight: 1.15
    }

    readonly property QtObject display: QtObject {
        readonly property string family: "system-ui, -apple-system, 'Segoe UI', Roboto, 'Noto Sans', sans-serif"
        readonly property int size: 40
        readonly property int weight: Font.Bold
        readonly property real lineHeight: 1.15
    }

    // Headlines
    readonly property QtObject headlineLarge: QtObject {
        readonly property string family: "system-ui, -apple-system, 'Segoe UI', Roboto, 'Noto Sans', sans-serif"
        readonly property int size: 32
        readonly property int weight: Font.Bold
        readonly property real lineHeight: 1.2
    }

    readonly property QtObject headline: QtObject {
        readonly property string family: "system-ui, -apple-system, 'Segoe UI', Roboto, 'Noto Sans', sans-serif"
        readonly property int size: 28
        readonly property int weight: Font.Bold
        readonly property real lineHeight: 1.25
    }

    // Titles
    readonly property QtObject titleLarge: QtObject {
        readonly property string family: "system-ui, -apple-system, 'Segoe UI', Roboto, 'Noto Sans', sans-serif"
        readonly property int size: 24
        readonly property int weight: Font.DemiBold
        readonly property real lineHeight: 1.25
    }

    readonly property QtObject title: QtObject {
        readonly property string family: "system-ui, -apple-system, 'Segoe UI', Roboto, 'Noto Sans', sans-serif"
        readonly property int size: 20
        readonly property int weight: Font.DemiBold
        readonly property real lineHeight: 1.3
    }

    readonly property QtObject subtitle: QtObject {
        readonly property string family: "system-ui, -apple-system, 'Segoe UI', Roboto, 'Noto Sans', sans-serif"
        readonly property int size: 18
        readonly property int weight: Font.DemiBold
        readonly property real lineHeight: 1.3
    }

    // Body
    readonly property QtObject bodyLarge: QtObject {
        readonly property string family: "system-ui, -apple-system, 'Segoe UI', Roboto, 'Noto Sans', sans-serif"
        readonly property int size: 16
        readonly property int weight: Font.Normal
        readonly property real lineHeight: 1.5
    }

    readonly property QtObject body: QtObject {
        readonly property string family: "system-ui, -apple-system, 'Segoe UI', Roboto, 'Noto Sans', sans-serif"
        readonly property int size: 14
        readonly property int weight: Font.Normal
        readonly property real lineHeight: 1.5
    }

    readonly property QtObject bodySmall: QtObject {
        readonly property string family: "system-ui, -apple-system, 'Segoe UI', Roboto, 'Noto Sans', sans-serif"
        readonly property int size: 13
        readonly property int weight: Font.Normal
        readonly property real lineHeight: 1.4
    }

    readonly property QtObject caption: QtObject {
        readonly property string family: "system-ui, -apple-system, 'Segoe UI', Roboto, 'Noto Sans', sans-serif"
        readonly property int size: 12
        readonly property int weight: Font.Normal
        readonly property real lineHeight: 1.35
    }

    // Monospace
    readonly property QtObject code: QtObject {
        readonly property string family: "'JetBrains Mono', 'Fira Code', 'Cascadia Code', 'Consolas', monospace"
        readonly property int size: 13
        readonly property int weight: Font.Normal
        readonly property real lineHeight: 1.5
    }
}
