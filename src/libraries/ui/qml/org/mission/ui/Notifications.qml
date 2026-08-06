// Mission OS — Notifications (MOS-DES-003)
//
// Third screen of the Mission OS desktop family.
// Implements the source-defined Notification Center structure
// (docs/design/03_SCREEN_REGISTRY.md MOS-DES-003 "Notifications",
// docs/wireframes/03_DESKTOP.md component + state "Notifications",
// docs/design/07_DESKTOP_LAYOUT.md §6, docs/reference/02_DESKTOP.md
// §Notification Center, docs/design/05_COMPONENT_LIBRARY.md
// §Notifications, docs/design/04_USER_FLOWS.md #12 Notifications):
//
//   Hosting: an overlay the host shows above the Desktop (MOS-DES-001
//   routes here via notificationsRequested and highlights its
//   Notifications button while overlayState == "notifications").
//   Place inside MissionWindow (or MissionPage) content and anchor to
//   fill, e.g.  MissionWindow { Notifications { anchors.fill: parent } }
//   The component sizes to its implicit 1280x720 like Desktop.qml.
//
//   Notification Center (02_DESKTOP.md): notifications are grouped by
//   application / priority / conversation. Notification levels:
//   Information · Success · Warning · Critical. Users may dismiss,
//   mute, snooze, reply (supported apps), clear groups, clear all.
//   Focus Mode suppresses non-critical notifications.
//
//   Desktop Layout (07_DESKTOP_LAYOUT.md §6): notifications appear in
//   the top-right, grouped by application, non-intrusive by default.
//
//   Component Library (§Notifications): each notification includes an
//   icon, title, description, timestamp and action buttons. No icon
//   assets ship, so the icon slot is a token level-dot (same
//   substitution the family uses for avatars/app initials).
//
//   User Flow (#12): Notification → Expand → Take Action → Dismiss.
//   This screen presents the list and emits activation/dismissal to
//   the host; expanding and acting are the host's job.
//
// Interpretation notes (documented — no authoritative source specifies
// further detail):
//   - The panel is anchored top-right per 07_DESKTOP_LAYOUT.md §6 and
//     floats over a token scrim (the same overlay treatment as
//     MOS-DES-002) so it never obscures the desktop it summarizes.
//   - The host drives the `notifications` model; each entry is
//     { id, app, title, message, time, level? }. `level` uses the four
//     reference levels ("information" | "success" | "warning" |
//     "critical") and falls back to "information" when absent. The
//     component library's richer "types" (error/security/update) map
//     onto these levels by the host (error/security → critical,
//     update → information) — documented interpretation.
//   - Grouping is host-side presentation (the model is flat); the
//     `app` label on every row keeps application grouping visible.
//   - Action buttons are kept minimal and faithful: the row itself is
//     the "Take Action" target (activate → reply/expand for supported
//     apps), each row has a Dismiss button, and the header has Clear
//     all. Mute / snooze / clear-group are host-side operations the
//     host can wire from the same signals (documented interpretation —
//     this screen is the minimal registered surface).
//   - Focus Mode (reference): when `focusMode` is true, non-critical
//     notifications (information, success) are suppressed — they are
//     hidden and a hint line explains why. Critical and warning
//     notifications remain visible.
//   - Escape is deliberately unmapped (same contract as MOS-LCK-001..004
//     and MOS-DES-001/002): the panel must not dismiss itself — the
//     host owns overlay dismissal.
//   - Empty notifications degrade to a neutral hint (defensive).
//
// Design-system compliance:
//   - Tokens only (Colors, Typography, Spacing, Radii, Motion, MissionTheme)
//   - Light + dark themes via MissionTheme (driven by host)
//   - Keyboard navigation with visible focus states; 44px minimum
//     touch targets (Spacing.minimumTouchTarget)
//   - WCAG AA-oriented contrast, reduced-motion aware
//   - Responsive reflow per docs/design/14_RESPONSIVE_RULES.md
//     (the panel trims to the window width on narrow layouts)

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.mission.ui 1.0

FocusScope {
    id: root

    implicitWidth: 1280
    implicitHeight: 720

    // ── Public API ─────────────────────────────────────────────────
    /// Notifications: [{ id, app, title, message, time, level? }] —
    /// host-driven. id is what the signals carry; app/title/message/
    /// time are displayed; level ∈ information | success | warning |
    /// critical (defaults to information).
    property var notifications: []

    /// Focus Mode (reference: suppresses non-critical notifications).
    /// When true, information/success notifications are hidden behind
    /// a hint; critical/warning remain visible.
    property bool focusMode: false

    /// Reduced motion (accessibility)
    property bool reducedMotion: false

    // ── Signals (host wiring) ──────────────────────────────────────
    /// User activated a notification (the "Take Action" step of the
    /// Notifications flow — expand/reply for supported apps)
    signal notificationActivated(string notificationId)
    /// User dismissed a single notification
    signal notificationDismissed(string notificationId)
    /// User chose "Clear all"
    signal clearAllRequested()

    // Escape is deliberately unmapped (see interpretation notes): the
    // panel must not dismiss itself. No Keys.onEscapePressed here.

    // ── Derived helpers ────────────────────────────────────────────
    /// Level → token color (dot; color is never the only indicator —
    /// the Accessible name and a text tag carry the level too)
    function levelColor(level) {
        switch (String(level)) {
        case "success":  return MissionTheme.success
        case "warning":  return MissionTheme.warning
        case "critical": return MissionTheme.error
        default:         return MissionTheme.primary
        }
    }

    /// Level → display label (accessibility + text tag)
    function levelLabel(level) {
        switch (String(level)) {
        case "success":  return qsTr("Success")
        case "warning":  return qsTr("Warning")
        case "critical": return qsTr("Critical")
        default:         return qsTr("Information")
        }
    }

    /// Whether a notification is suppressed by Focus Mode
    /// (non-critical = information + success). The level is normalized
    /// exactly like levelLabel/levelColor: anything that is not one of
    /// the four reference levels falls back to "information" — so an
    /// entry without a `level` property is treated as information and
    /// suppressed in Focus Mode (matches the documented default).
    function isSuppressed(level) {
        if (!root.focusMode)
            return false
        var l = String(level)
        if (l !== "information" && l !== "success" &&
            l !== "warning" && l !== "critical")
            l = "information"
        return l === "information" || l === "success"
    }

    /// Number of notifications (visible or not) — header badge
    readonly property int notificationCount: root.notifications.length

    /// Whether any notification is currently visible (not suppressed)
    readonly property bool hasVisibleNotifications: {
        for (var i = 0; i < root.notifications.length; ++i) {
            if (!root.isSuppressed(root.notifications[i].level))
                return true
        }
        return false
    }

    /// Move keyboard focus to a notification row (clamped, wraps).
    /// Suppressed (Focus Mode hidden) rows are skipped so keyboard
    /// users never land on an invisible row.
    function focusRow(index) {
        if (root.notifications.length === 0)
            return
        var count = root.notifications.length
        var target = ((index % count) + count) % count
        for (var step = 0; step < count; ++step) {
            var item = notificationRows.itemAt(target)
            if (item !== null && !root.isSuppressed(root.notifications[target].level)) {
                item.forceActiveFocus()
                return
            }
            target = (target + 1) % count
        }
    }

    // ── Test hooks (used by tests/tst_notifications.qml) ───────────
    property alias backdropScrim: backdropScrim
    property alias notificationPanel: notificationPanel
    property alias titleLabel: titleLabel
    property alias clearAllButton: clearAllButton
    property alias focusHint: focusHint
    property alias notificationRows: notificationRows
    property alias emptyHint: emptyHint

    // ── Overlay backdrop (scrim over the desktop) ──────────────────
    // Fades in on presentation (reduced-motion aware): the scrim starts
    // transparent and Component.onCompleted animates it to full so the
    // panel never pops abruptly over the desktop.
    Rectangle {
        id: backdropScrim
        objectName: "notifScrim"
        anchors.fill: parent
        color: Colors.scrim
        opacity: 0.0
        Behavior on opacity {
            enabled: !root.reducedMotion
            animation: NumberAnimation { duration: Motion.fadeIn }
        }
    }

    // ══════════════════════════════════════════════════════════════
    // Notification Center panel (07_DESKTOP_LAYOUT.md §6 — top-right)
    // ══════════════════════════════════════════════════════════════
    Rectangle {
        id: notificationPanel
        objectName: "notifPanel"
        anchors {
            top: parent.top
            right: parent.right
            margins: Spacing.paddingLarge
        }
        // Panel trims to the window on narrow layouts
        width: Math.min(400, root.width - Spacing.paddingLarge * 2)
        // Content-driven height clamped to the window
        height: Math.min(panelColumn.height + Spacing.paddingLarge * 2,
                         root.height - Spacing.paddingLarge * 2)
        radius: Radii.dialog
        color: MissionTheme.surface
        border.color: MissionTheme.outline
        border.width: 1

        Column {
            id: panelColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
            }
            anchors.margins: Spacing.paddingLarge
            spacing: Spacing.gapMedium

            // ── Header: title + Clear all ──
            RowLayout {
                width: parent.width
                spacing: Spacing.gapSmall

                Label {
                    id: titleLabel
                    objectName: "notifTitle"
                    Layout.fillWidth: true
                    text: qsTr("Notifications")
                    font.pixelSize: Typography.title.size
                    font.weight: Typography.title.weight
                    color: MissionTheme.textPrimary
                    elide: Text.ElideRight
                    Accessible.role: Accessible.Heading
                    Accessible.name: text
                }

                MissionButton {
                    id: clearAllButton
                    objectName: "notifClearAll"
                    variant: MissionButton.Variant.Tertiary
                    compact: true
                    text: qsTr("Clear all")
                    enabled: root.notificationCount > 0
                    onClicked: root.clearAllRequested()
                    Accessible.description: qsTr("Dismiss all notifications")
                }
            }

            // ── Focus Mode hint (reference: suppresses non-critical) ──
            Label {
                id: focusHint
                objectName: "notifFocusHint"
                visible: root.focusMode
                text: qsTr("Focus Mode is on — non-critical notifications are hidden")
                font.pixelSize: Typography.bodySmall.size
                color: MissionTheme.textSecondary
                wrapMode: Text.WordWrap
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }

            // ── Notification rows (scrolls when the list overflows) ──
            // The list area gets at least 72px and at most 400px (or the
            // window minus header space); the panel sizes to its content
            // and the list scrolls beyond that.
            Flickable {
                id: scrollArea
                width: parent.width
                height: Math.max(72, Math.min(400,
                                 root.height - Spacing.paddingLarge * 4 - 96))
                clip: true
                interactive: contentHeight > height
                contentHeight: listColumn.implicitHeight

                Column {
                    id: listColumn
                    width: parent.width
                    spacing: Spacing.gapSmall

                    Repeater {
                        id: notificationRows
                        model: root.notifications

                        delegate: Rectangle {
                            required property var modelData
                            required property int index

                            id: notifRow
                            objectName: "notifRow" + index
                            width: parent.width
                            height: notifColumn.implicitHeight + Spacing.paddingMedium * 2
                            radius: Radii.card
                            // Suppressed by Focus Mode: hidden entirely
                            // (the hint explains why)
                            visible: !root.isSuppressed(modelData.level)
                            color: notifRowMouse.containsMouse
                                   ? MissionTheme.surfaceVariant : MissionTheme.surfaceDim
                            border.width: 1
                            border.color: MissionTheme.outlineVariant
                            activeFocusOnTab: true

                            Behavior on color {
                                enabled: !root.reducedMotion
                                animation: ColorAnimation { duration: Motion.colorChange }
                            }

                            // Visible focus ring (keyboard navigation)
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: -2
                                radius: Radii.card + 2
                                color: "transparent"
                                border.color: MissionTheme.focusRing
                                border.width: 2
                                visible: notifRow.activeFocus
                            }

                            // Row click = "Take Action" (expand/reply).
                            // Declared BEFORE the content so interactive
                            // children (the Dismiss button, declared
                            // later = on top) receive their own clicks;
                            // clicks on non-interactive content fall
                            // through to this MouseArea.
                            MouseArea {
                                id: notifRowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    notifRow.forceActiveFocus()
                                    root.notificationActivated(String(modelData.id))
                                }
                            }

                            Column {
                                id: notifColumn
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    top: parent.top
                                }
                                anchors.leftMargin: Spacing.paddingMedium
                                anchors.rightMargin: Spacing.paddingMedium
                                anchors.topMargin: Spacing.paddingMedium
                                spacing: Spacing.gapTiny

                                // ── Meta line: level tag · app · time ──
                                RowLayout {
                                    width: parent.width
                                    spacing: Spacing.gapSmall

                                    // Level tag: dot + text (color is
                                    // never the only indicator)
                                    Rectangle {
                                        Layout.preferredWidth: 8
                                        Layout.preferredHeight: 8
                                        radius: 4
                                        color: root.levelColor(modelData.level)
                                    }
                                    Label {
                                        text: root.levelLabel(modelData.level)
                                        font.pixelSize: Typography.caption.size
                                        color: MissionTheme.textSecondary
                                    }
                                    Label {
                                        Layout.fillWidth: true
                                        text: modelData.app !== undefined
                                              ? String(modelData.app) : ""
                                        font.pixelSize: Typography.caption.size
                                        font.weight: Typography.weightMedium
                                        color: MissionTheme.textPrimary
                                        elide: Text.ElideRight
                                    }
                                    Label {
                                        text: modelData.time !== undefined
                                              ? String(modelData.time) : ""
                                        font.pixelSize: Typography.caption.size
                                        color: MissionTheme.textTertiary
                                    }
                                }

                                // ── Title ──
                                Label {
                                    width: parent.width
                                    text: modelData.title !== undefined
                                          ? String(modelData.title) : ""
                                    font.pixelSize: Typography.body.size
                                    font.weight: Typography.weightSemibold
                                    color: MissionTheme.textPrimary
                                    elide: Text.ElideRight
                                }

                                // ── Message ──
                                Label {
                                    width: parent.width
                                    text: modelData.message !== undefined
                                          ? String(modelData.message) : ""
                                    font.pixelSize: Typography.bodySmall.size
                                    color: MissionTheme.textSecondary
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }

                                // ── Action: Dismiss ──
                                RowLayout {
                                    width: parent.width
                                    spacing: Spacing.gapSmall

                                    Item { Layout.fillWidth: true }

                                    MissionButton {
                                        objectName: "notifDismiss" + index
                                        variant: MissionButton.Variant.Tertiary
                                        compact: true
                                        text: qsTr("Dismiss")
                                        onClicked: root.notificationDismissed(
                                                       String(modelData.id))
                                        Accessible.description: qsTr("Dismiss this notification")
                                    }
                                }
                            }

                            // Keyboard-first: Up/Down move between rows,
                            // Enter/Space take action (the Dismiss
                            // button gets focus via Tab)
                            Keys.onUpPressed: root.focusRow(index - 1)
                            Keys.onDownPressed: root.focusRow(index + 1)
                            Keys.onLeftPressed: root.focusRow(index - 1)
                            Keys.onRightPressed: root.focusRow(index + 1)
                            Keys.onReturnPressed:
                                root.notificationActivated(String(modelData.id))
                            Keys.onSpacePressed:
                                root.notificationActivated(String(modelData.id))

                            Accessible.role: Accessible.Button
                            Accessible.name: qsTr("%1: %2, %3, %4")
                                .arg(modelData.app !== undefined ? String(modelData.app) : "")
                                .arg(modelData.title !== undefined ? String(modelData.title) : "")
                                .arg(root.levelLabel(modelData.level))
                                .arg(modelData.time !== undefined ? String(modelData.time) : "")
                        }
                    }

                    // ── Empty hint (defensive) ──
                    Label {
                        id: emptyHint
                        objectName: "notifEmpty"
                        visible: root.notificationCount === 0
                        width: parent.width
                        text: qsTr("No notifications")
                        font.pixelSize: Typography.bodySmall.size
                        color: MissionTheme.textSecondary
                        Accessible.role: Accessible.StaticText
                        Accessible.name: text
                    }
                }
            }
        }
    }

    // ── Initial focus (keyboard-first) ─────────────────────────────
    // The root claims focus so keyboard users land in the panel
    // immediately, and the first visible notification row is focused
    // as soon as the panel appears (desktop §Keyboard Navigation —
    // Notification Center is keyboard-operable).
    focus: true

    Component.onCompleted: {
        backdropScrim.opacity = 1.0
        if (root.notifications.length > 0)
            root.focusRow(0)
    }
}
