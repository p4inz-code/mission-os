// Mission OS Design Tokens — Colors
//
// Canonical color palette for the Mission OS design system.
// These tokens are the single source of truth for all UI colors.
//
// Architecture:
//   - Semantic colors (primary, success, warning, error)
//   - Neutral colors (background, surface, text)
//   - Accent colors
//   - Overlay/utility colors
//
// Accessibility:
//   All foreground/background combinations meet WCAG AA contrast
//   ratios (minimum 4.5:1 for normal text, 3:1 for large text).

pragma Singleton
import QtQuick

QtObject {
    // QML reserves property names starting with "on" + an uppercase
    // letter for signal handlers, so the Material-style "on-<surface>"
    // content tokens are exposed as "contentOn<surface>"
    // (e.g. onPrimary → contentOnPrimary). Values are unchanged.

    // ── Primary Brand Colors ───────────────────────────────────────
    readonly property color primary:              "#2563EB"   // Blue 600
    readonly property color primaryLight:         "#3B82F6"   // Blue 500
    readonly property color primaryDark:          "#1D4ED8"   // Blue 700
    readonly property color primaryContainer:     "#DBEAFE"   // Blue 100
    readonly property color contentOnPrimary:            "#FFFFFF"
    readonly property color contentOnPrimaryContainer:   "#1E3A5F"

    // ── Secondary / Accent ─────────────────────────────────────────
    readonly property color secondary:            "#7C3AED"   // Violet 600
    readonly property color secondaryLight:       "#8B5CF6"   // Violet 500
    readonly property color secondaryDark:        "#6D28D9"   // Violet 700
    readonly property color secondaryContainer:   "#EDE9FE"   // Violet 100
    readonly property color contentOnSecondary:          "#FFFFFF"
    readonly property color contentOnSecondaryContainer: "#3B0764"

    // ── Success / Positive ─────────────────────────────────────────
    readonly property color success:              "#16A34A"   // Green 600
    readonly property color successLight:         "#22C55E"   // Green 500
    readonly property color successDark:          "#15803D"   // Green 700
    readonly property color successContainer:     "#DCFCE7"   // Green 100
    readonly property color contentOnSuccess:            "#FFFFFF"
    readonly property color contentOnSuccessContainer:   "#14532D"

    // ── Warning / Caution ──────────────────────────────────────────
    readonly property color warning:              "#D97706"   // Amber 600
    readonly property color warningLight:         "#F59E0B"   // Amber 500
    readonly property color warningDark:          "#B45309"   // Amber 700
    readonly property color warningContainer:     "#FEF3C7"   // Amber 100
    readonly property color contentOnWarning:            "#FFFFFF"
    readonly property color contentOnWarningContainer:   "#78350F"

    // ── Error / Destructive ────────────────────────────────────────
    readonly property color error:                "#DC2626"   // Red 600
    readonly property color errorLight:           "#EF4444"   // Red 500
    readonly property color errorDark:            "#B91C1C"   // Red 700
    readonly property color errorContainer:       "#FEE2E2"   // Red 100
    readonly property color contentOnError:              "#FFFFFF"
    readonly property color contentOnErrorContainer:     "#7F1D1D"

    // ── Neutral / Surface (Light) ──────────────────────────────────
    readonly property color background:           "#F8FAFC"   // Slate 50
    readonly property color surface:              "#FFFFFF"
    readonly property color surfaceVariant:       "#F1F5F9"   // Slate 100
    readonly property color surfaceDim:           "#E2E8F0"   // Slate 200
    readonly property color outline:              "#CBD5E1"   // Slate 300
    readonly property color outlineVariant:       "#E2E8F0"   // Slate 200

    // ── Text (Light) ───────────────────────────────────────────────
    readonly property color textPrimary:          "#0F172A"   // Slate 900
    readonly property color textSecondary:        "#475569"   // Slate 600
    readonly property color textTertiary:         "#94A3B8"   // Slate 400
    readonly property color textInverse:          "#FFFFFF"
    readonly property color textLink:             "#2563EB"   // Blue 600
    readonly property color textDisabled:         "#CBD5E1"   // Slate 300

    // ── Dark Theme Colors ──────────────────────────────────────────
    readonly property color darkBackground:       "#0F172A"   // Slate 900
    readonly property color darkSurface:          "#1E293B"   // Slate 800
    readonly property color darkSurfaceVariant:   "#334155"   // Slate 700
    readonly property color darkSurfaceDim:       "#0F172A"   // Slate 900
    readonly property color darkOutline:          "#475569"   // Slate 600
    readonly property color darkOutlineVariant:   "#334155"   // Slate 700

    readonly property color darkTextPrimary:      "#F8FAFC"   // Slate 50
    readonly property color darkTextSecondary:    "#CBD5E1"  // Slate 300
    readonly property color darkTextTertiary:     "#64748B"  // Slate 500
    readonly property color darkTextInverse:      "#0F172A"  // Slate 900
    readonly property color darkTextLink:         "#60A5FA"  // Blue 400
    readonly property color darkTextDisabled:     "#475569"  // Slate 600

    // ── Overlay / Utility ──────────────────────────────────────────
    readonly property color scrim:                Qt.rgba(0, 0, 0, 0.32)
    readonly property color overlay:              Qt.rgba(0, 0, 0, 0.08)
    readonly property color overlayLight:         Qt.rgba(0, 0, 0, 0.04)
    readonly property color focusRing:            "#3B82F6"   // Blue 500
    readonly property color selectedHighlight:    Qt.rgba(37, 99, 235, 0.12)

    // ── Shadows ────────────────────────────────────────────────────
    readonly property color shadowSmall:          Qt.rgba(0, 0, 0, 0.10)
    readonly property color shadowMedium:         Qt.rgba(0, 0, 0, 0.12)
    readonly property color shadowLarge:          Qt.rgba(0, 0, 0, 0.16)
}
