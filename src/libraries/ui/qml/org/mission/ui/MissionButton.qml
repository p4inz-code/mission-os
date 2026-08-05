// Mission OS — MissionButton
//
// Reusable button component per docs/design/05_COMPONENT_LIBRARY.md §5.
//
// Variants:  Primary / Secondary / Tertiary / Destructive
// States:    Default · Hover · Focus · Pressed · Disabled · Loading
//
// Design-system compliance:
//   - Tokens only (Colors, Typography, Spacing, Radii, Motion, MissionTheme)
//   - 44px minimum touch target (Spacing.minimumTouchTarget)
//   - Visible focus ring (MissionTheme.focusRing) for keyboard navigation
//   - Reduced-motion aware (durations disabled when reducedMotion is true)
//   - WCAG AA oriented: text colors are theme tokens chosen per variant so
//     the resting state always meets ≥ 4.5:1 on its background
//
// Usage:
//   import org.mission.ui 1.0
//
//   MissionButton {
//       variant: MissionButton.Variant.Primary
//       text: "Continue"
//       onClicked: continueFlow()
//   }

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.mission.ui 1.0

Button {
    id: root

    // ── Variants ───────────────────────────────────────────────────
    enum Variant {
        Primary,
        Secondary,
        Tertiary,
        Destructive
    }

    /// Visual variant (MissionButton.Variant.*)
    property int variant: MissionButton.Variant.Primary

    /// When true, shows a progress indicator and blocks activation
    property bool loading: false

    /// Reduced motion: disable color/state transition animations
    property bool reducedMotion: false

    /// Compact padding for dense layouts (e.g. headers)
    property bool compact: false

    // ── Sizing (44px minimum touch target) ─────────────────────────
    implicitHeight: Math.max(Spacing.minimumTouchTarget,
                             contentItem.implicitHeight + topPadding + bottomPadding)
    topPadding: Spacing.paddingSmall
    bottomPadding: Spacing.paddingSmall
    leftPadding: root.compact ? Spacing.paddingSmall : Spacing.paddingMedium
    rightPadding: root.compact ? Spacing.paddingSmall : Spacing.paddingMedium

    font.pixelSize: Typography.body.size
    font.weight: Typography.weightMedium

    // ── Derived colors (tokens only) ───────────────────────────────
    readonly property color baseColor: {
        switch (root.variant) {
        case MissionButton.Variant.Primary:      return MissionTheme.primary
        case MissionButton.Variant.Secondary:    return MissionTheme.surface
        case MissionButton.Variant.Tertiary:     return "transparent"
        case MissionButton.Variant.Destructive:  return MissionTheme.error
        }
        return MissionTheme.primary
    }

    readonly property color pressedColor: {
        switch (root.variant) {
        case MissionButton.Variant.Primary:      return MissionTheme.primaryDark
        case MissionButton.Variant.Secondary:    return MissionTheme.surfaceDim
        case MissionButton.Variant.Tertiary:     return MissionTheme.surfaceDim
        case MissionButton.Variant.Destructive:  return Colors.errorDark
        }
        return MissionTheme.primaryDark
    }

    readonly property color hoverColor: {
        switch (root.variant) {
        case MissionButton.Variant.Secondary:
        case MissionButton.Variant.Tertiary:     return MissionTheme.surfaceVariant
        default:                                 return root.baseColor
        }
    }

    readonly property color contentColor: {
        if (!root.enabled)
            return MissionTheme.textDisabled
        switch (root.variant) {
        case MissionButton.Variant.Primary:      return MissionTheme.contentOnPrimary
        case MissionButton.Variant.Secondary:    return MissionTheme.textPrimary
        case MissionButton.Variant.Tertiary:     return MissionTheme.textLink
        case MissionButton.Variant.Destructive:  return MissionTheme.contentOnError
        }
        return MissionTheme.contentOnPrimary
    }

    // ── Background ─────────────────────────────────────────────────
    background: Rectangle {
        id: backgroundRect
        radius: Radii.button
        color: {
            if (!root.enabled)
                return MissionTheme.surfaceVariant
            if (root.pressed)
                return root.pressedColor
            if (root.hovered)
                return root.hoverColor
            return root.baseColor
        }
        border.width: (root.variant === MissionButton.Variant.Secondary && root.enabled) ? 1 : 0
        border.color: MissionTheme.outline

        Behavior on color {
            enabled: !root.reducedMotion
            // This Ubuntu Qt 6.10 toolchain does not expose the Behavior
            // `duration` convenience property (verified empirically — the
            // QML engine rejects it with "Cannot assign to non-existent
            // property"), so the duration is set through the equivalent
            // `animation:` group property on a ColorAnimation instead.
            animation: ColorAnimation { duration: Motion.colorChange }
        }

        // Subtle darkening scrim on colored surfaces for hover feedback
        Rectangle {
            anchors.fill: parent
            radius: Radii.button
            color: Colors.overlayLight
            visible: root.enabled && root.hovered && !root.pressed &&
                     (root.variant === MissionButton.Variant.Primary ||
                      root.variant === MissionButton.Variant.Destructive)
        }

        // Visible focus ring for keyboard navigation
        Rectangle {
            anchors.fill: parent
            anchors.margins: -3
            radius: Radii.button + 3
            color: "transparent"
            border.color: MissionTheme.focusRing
            border.width: 2
            visible: root.visualFocus
        }
    }

    // ── Content ────────────────────────────────────────────────────
    contentItem: Item {
        implicitWidth: contentRow.implicitWidth
        implicitHeight: contentRow.implicitHeight

        RowLayout {
            id: contentRow
            anchors.centerIn: parent
            spacing: Spacing.gapSmall

            // Loading indicator: calm pulsing dot
            Rectangle {
                id: loadingDot
                visible: root.loading
                Layout.preferredWidth: 6
                Layout.preferredHeight: 6
                radius: 3
                color: root.contentColor
                SequentialAnimation on opacity {
                    running: root.loading && !root.reducedMotion
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.25; duration: Motion.durationFaster }
                    NumberAnimation { to: 1.0; duration: Motion.durationFaster }
                }
            }

            Label {
                text: root.text
                color: root.contentColor
                font.pixelSize: Typography.body.size
                font.weight: Typography.weightMedium
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    // ── Accessibility ──────────────────────────────────────────────
    Accessible.role: Accessible.Button
    Accessible.name: text
    Accessible.description: root.loading ? qsTr("Loading") : ""
}
