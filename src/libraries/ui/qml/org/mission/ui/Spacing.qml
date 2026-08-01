// Mission OS Design Tokens — Spacing
//
// Spacing scale following a 4px baseline grid.
// All values in pixels (px).

pragma Singleton
import QtQuick

QtObject {
    // ── Base Spacing Scale (4px grid) ──────────────────────────────
    readonly property int spacingNone:            0
    readonly property int spacingXxs:             2     // 2px
    readonly property int spacingXs:              4     // 4px
    readonly property int spacingSm:              8     // 8px
    readonly property int spacingMd:              12    // 12px
    readonly property int spacingLg:              16    // 16px
    readonly property int spacingXl:              20    // 20px
    readonly property int spacingXxl:             24    // 24px
    readonly property int spacingXxxl:            32    // 32px
    readonly property int spacingXxxxl:           40    // 40px
    readonly property int spacingSection:         48    // 48px
    readonly property int spacingPage:            64    // 64px

    // ── Semantic Spacing ───────────────────────────────────────────
    // Named spacing values for common use cases

    // Inset / padding
    readonly property int paddingTiny:            spacingXs     // 4px
    readonly property int paddingSmall:           spacingSm     // 8px
    readonly property int paddingMedium:          spacingLg     // 16px
    readonly property int paddingLarge:           spacingXxl    // 24px
    readonly property int paddingPage:            spacingXxxl   // 32px

    // Gap / between items
    readonly property int gapTiny:                spacingXs     // 4px
    readonly property int gapSmall:               spacingSm     // 8px
    readonly property int gapMedium:              spacingMd     // 12px
    readonly property int gapLarge:               spacingLg     // 16px
    readonly property int gapSection:             spacingXxl    // 24px

    // Margins
    readonly property int marginPage:             spacingXxl    // 24px
    readonly property int marginCard:             spacingLg     // 16px
    readonly property int marginDialog:           spacingXxl    // 24px

    // ── Layout Sizes ───────────────────────────────────────────────
    readonly property int sidebarWidth:           280
    readonly property int sidebarWidthCompact:    64
    readonly property int headerHeight:           56
    readonly property int toolbarHeight:          48
    readonly property int statusBarHeight:        32
    readonly property int minimumTouchTarget:     44    // Accessibility: minimum 44px
    readonly property int iconSizeSmall:          16
    readonly property int iconSizeMedium:         24
    readonly property int iconSizeLarge:          32
}
