// Mission OS Design Tokens — Border Radii
//
// Corner radius values for the Mission OS design system.
// All values in pixels (px).

pragma Singleton
import QtQuick

QtObject {
    // ── Radius Scale ───────────────────────────────────────────────
    readonly property int radiusNone:             0
    readonly property int radiusXs:               2
    readonly property int radiusSm:               4
    readonly property int radiusMd:               8
    readonly property int radiusLg:               12
    readonly property int radiusXl:               16
    readonly property int radiusXxl:              20
    readonly property int radiusFull:             9999    // Pill / circular

    // ── Semantic Radii ─────────────────────────────────────────────
    readonly property int button:                 radiusSm      // 4px
    readonly property int card:                   radiusMd      // 8px
    readonly property int dialog:                 radiusLg      // 12px
    readonly property int input:                  radiusSm      // 4px
    readonly property int chip:                   radiusXl      // 16px
    readonly property int sheet:                  radiusXl      // 16px (top corners)
    readonly property int badge:                  radiusFull    // Pill
    readonly property int tooltip:                radiusSm      // 4px
}
