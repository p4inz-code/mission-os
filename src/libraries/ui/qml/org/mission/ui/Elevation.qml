// Mission OS Design Tokens — Elevation
//
// Elevation levels and shadow definitions for the Mission OS design system.
// Follows Material Design elevation scale for consistency.

pragma Singleton
import QtQuick

QtObject {
    // ── Elevation Levels ───────────────────────────────────────────
    // z-depth in pixels (conceptual — actual rendering depends on
    // Qt Quick's GraphicsInfo capabilities)

    readonly property int elevationNone:          0
    readonly property int elevationXxs:           1
    readonly property int elevationXs:            2
    readonly property int elevationSm:            4
    readonly property int elevationMd:            8
    readonly property int elevationLg:            12
    readonly property int elevationXl:            16
    readonly property int elevationXxl:           24

    // ── Semantic Elevation ─────────────────────────────────────────
    readonly property int card:                   elevationXs   // 2dp
    readonly property int dropdown:               elevationSm   // 4dp
    readonly property int dialog:                 elevationXl   // 16dp
    readonly property int modal:                  elevationXxl  // 24dp
    readonly property int snackbar:               elevationMd   // 8dp
    readonly property int fab:                    elevationMd   // 8dp
    readonly property int navigationBar:          elevationSm   // 4dp
    readonly property int header:                 elevationXxs  // 1dp
}
