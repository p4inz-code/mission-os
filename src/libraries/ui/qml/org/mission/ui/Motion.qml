// Mission OS Design Tokens — Motion
//
// Animation durations and easing curves for the Mission OS design system.
// Follows Material Design motion guidelines for consistency.

pragma Singleton
import QtQuick

QtObject {
    // ── Duration Tokens (milliseconds) ─────────────────────────────
    readonly property int durationInstant:        0
    readonly property int durationFastest:        50
    readonly property int durationFaster:         100
    readonly property int durationFast:           200
    readonly property int durationNormal:         300
    readonly property int durationSlow:           400
    readonly property int durationSlower:         500
    readonly property int durationSlowest:        700

    // ── Semantic Durations ─────────────────────────────────────────
    readonly property int fadeIn:                 durationFast    // 200ms
    readonly property int fadeOut:                durationFast    // 200ms
    readonly property int slideIn:                durationNormal  // 300ms
    readonly property int slideOut:               durationNormal  // 300ms
    readonly property int scaleIn:                durationFast    // 200ms
    readonly property int scaleOut:               durationFaster  // 100ms
    readonly property int rotate:                 durationNormal  // 300ms
    readonly property int colorChange:            durationFast    // 200ms
    readonly property int pageTransition:         durationSlow    // 400ms
    readonly property int dialogEnter:            durationFast    // 200ms
    readonly property int dialogExit:             durationFaster  // 100ms

    // ── Easing Curves ──────────────────────────────────────────────
    readonly property EasingCurve easingStandard:  EasingCurve { type: Easing.BezierSpline;  bezierCurve: [0.4, 0.0, 0.2, 1.0] }
    readonly property EasingCurve easingDecelerate: EasingCurve { type: Easing.BezierSpline; bezierCurve: [0.0, 0.0, 0.2, 1.0] }
    readonly property EasingCurve easingAccelerate: EasingCurve { type: Easing.BezierSpline; bezierCurve: [0.4, 0.0, 1.0, 1.0] }
    readonly property EasingCurve easingSharp:     EasingCurve { type: Easing.BezierSpline;  bezierCurve: [0.4, 0.0, 0.6, 1.0] }
    readonly property EasingCurve easingLinear:    Easing.Linear
    readonly property EasingCurve easingOutBack:   Easing.OutBack
    readonly property EasingCurve easingOutCubic:  Easing.OutCubic
}
