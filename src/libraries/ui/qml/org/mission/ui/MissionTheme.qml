// Mission OS Theme Foundation
//
// Central theme singleton that provides semantic theme values
// (light/dark mode support via the Colors singleton).
//
// Usage in QML:
//   import org.mission.ui 1.0
//   color: MissionTheme.backgroundColor
//
// Architecture:
//   - Provides a single access point for all themed values
//   - Light and dark modes are handled via the Colors singleton
//   - Future: system-wide theme switching via mission-settingsd

pragma Singleton
import QtQuick
import org.mission.ui 1.0

QtObject {
    // ── Theme Mode ─────────────────────────────────────────────────
    // true = dark mode, false = light mode
    // Future: connect to mission-settingsd for system-wide toggling
    property bool darkMode: false

    // ── Background / Surface ───────────────────────────────────────
    readonly property color background:           darkMode ? Colors.darkBackground       : Colors.background
    readonly property color surface:              darkMode ? Colors.darkSurface          : Colors.surface
    readonly property color surfaceVariant:       darkMode ? Colors.darkSurfaceVariant   : Colors.surfaceVariant
    readonly property color surfaceDim:           darkMode ? Colors.darkSurfaceDim       : Colors.surfaceDim
    readonly property color outline:              darkMode ? Colors.darkOutline           : Colors.outline
    readonly property color outlineVariant:       darkMode ? Colors.darkOutlineVariant    : Colors.outlineVariant

    // ── Text ───────────────────────────────────────────────────────
    readonly property color textPrimary:          darkMode ? Colors.darkTextPrimary      : Colors.textPrimary
    readonly property color textSecondary:        darkMode ? Colors.darkTextSecondary    : Colors.textSecondary
    readonly property color textTertiary:         darkMode ? Colors.darkTextTertiary     : Colors.textTertiary
    readonly property color textInverse:          darkMode ? Colors.darkTextInverse      : Colors.textInverse
    readonly property color textLink:             darkMode ? Colors.darkTextLink         : Colors.textLink
    readonly property color textDisabled:         darkMode ? Colors.darkTextDisabled     : Colors.textDisabled

    // ── Primary ────────────────────────────────────────────────────
    readonly property color primary:              Colors.primary
    readonly property color primaryLight:         Colors.primaryLight
    readonly property color primaryDark:          Colors.primaryDark
    readonly property color primaryContainer:     Colors.primaryContainer
    readonly property color contentOnPrimary:            Colors.contentOnPrimary
    readonly property color contentOnPrimaryContainer:   Colors.contentOnPrimaryContainer

    // ── Secondary ──────────────────────────────────────────────────
    readonly property color secondary:            Colors.secondary
    readonly property color secondaryLight:       Colors.secondaryLight
    readonly property color secondaryDark:        Colors.secondaryDark
    readonly property color secondaryContainer:   Colors.secondaryContainer
    readonly property color contentOnSecondary:          Colors.contentOnSecondary
    readonly property color contentOnSecondaryContainer: Colors.contentOnSecondaryContainer

    // ── Semantic Colors ────────────────────────────────────────────
    readonly property color success:              Colors.success
    readonly property color successLight:         Colors.successLight
    readonly property color warning:              Colors.warning
    readonly property color warningLight:         Colors.warningLight
    readonly property color error:                Colors.error
    readonly property color errorLight:           Colors.errorLight
    // Content-on-semantic tokens. MissionButton's Destructive variant
    // renders its label with MissionTheme.contentOnError; without this
    // forwarding the variant's text color binding would resolve to
    // undefined (audit finding: Colors exposes contentOnError but
    // MissionTheme did not forward it).
    readonly property color contentOnError:       Colors.contentOnError

    // ── Focus Ring ─────────────────────────────────────────────────
    readonly property color focusRing:            Colors.focusRing
}
