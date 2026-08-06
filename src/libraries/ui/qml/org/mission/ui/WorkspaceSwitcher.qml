// Mission OS — Workspace Switcher (MOS-DES-002)
//
// Second screen of the Mission OS desktop family.
// Implements the source-defined Workspace Switcher structure
// (docs/design/03_SCREEN_REGISTRY.md MOS-DES-002 "Workspace Switcher",
// docs/wireframes/03_DESKTOP.md component "Workspace Switcher",
// docs/reference/02_DESKTOP.md §Virtual Workspaces + §Keyboard
// Navigation, docs/design/04_USER_FLOWS.md Workspace Flow):
//
//   Hosting: an overlay the host shows above the Desktop (MOS-DES-001
//   routes here via workspaceSwitchRequested and highlights its
//   Workspace Indicator while overlayState == "workspaceSwitching").
//   Place inside MissionWindow (or MissionPage) content and anchor to
//   fill, e.g.  MissionWindow { WorkspaceSwitcher { anchors.fill: parent } }
//   The component sizes to its implicit 1280x720 like Desktop.qml.
//
//   Workspace Flow (04_USER_FLOWS.md): Desktop → Workspace Switcher →
//   Choose Workspace → Restore Session. This screen implements the
//   "Choose Workspace" step: it presents the workspace list and emits
//   workspaceSelected(id); session restoration is the host's job.
//
//   Virtual Workspaces (02_DESKTOP.md): each workspace remembers open
//   applications, window positions, wallpaper, widgets, pinned
//   applications and notification state — all host-side state, so the
//   host drives the `workspaces` model ({ id, name, windowCount? }).
//   The management operations listed there (create, rename, reorder,
//   delete, duplicate) belong to the host's Workspace Manager; this
//   screen only chooses (documented interpretation — the registered
//   screen is the switcher, not the manager).
//
// Interpretation notes (documented — no authoritative source specifies
// further detail):
//   - Overlay treatment: a token scrim over the desktop with a centered
//     card, so the switcher never obscures the desktop it switches.
//   - The current workspace is host-driven (currentWorkspace index,
//     same contract as Desktop.qml); the switcher highlights it but
//     never mutates it. Keyboard arrows move focus between rows; Enter
//     / Space (or click) emits workspaceSelected for the focused row —
//     the host then switches and updates currentWorkspace.
//   - Selecting the current workspace again emits workspaceSelected
//     too; the host decides whether that is a no-op or a refresh.
//   - Workspace names/window counts come from the host model; window
//     count is optional and hidden when absent or zero.
//   - Escape is deliberately unmapped (same contract as MOS-LCK-001..004
//     and MOS-DES-001): the switcher must not dismiss itself — the host
//     owns overlay dismissal.
//   - Empty workspaces list degrades to a neutral hint (defensive; a
//     desktop always has at least one workspace in practice).
//
// Design-system compliance:
//   - Tokens only (Colors, Typography, Spacing, Radii, Motion, MissionTheme)
//   - Light + dark themes via MissionTheme (driven by host)
//   - Keyboard navigation with visible focus states; 44px minimum
//     touch targets (Spacing.minimumTouchTarget)
//   - WCAG AA-oriented contrast, reduced-motion aware
//   - Responsive reflow per docs/design/14_RESPONSIVE_RULES.md
//     (the card trims to the window width on narrow layouts)

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.mission.ui 1.0

FocusScope {
    id: root

    implicitWidth: 1280
    implicitHeight: 720

    // ── Public API ─────────────────────────────────────────────────
    /// Workspaces: [{ id, name, windowCount? }] — host-driven. id is
    /// what workspaceSelected carries; name is displayed; windowCount
    /// is an optional "N windows" summary (hidden when absent or zero).
    property var workspaces: []

    /// Index of the current workspace within `workspaces` (host-driven;
    /// derived helpers clamp out-of-range values)
    property int currentWorkspace: 0

    /// Reduced motion (accessibility)
    property bool reducedMotion: false

    // ── Signals (host wiring) ──────────────────────────────────────
    /// User chose a workspace (the "Choose Workspace" step of the
    /// Workspace Flow); the host switches and restores the session
    signal workspaceSelected(string workspaceId)

    // Escape is deliberately unmapped (see interpretation notes): the
    // switcher must not dismiss itself. No Keys.onEscapePressed here.

    // ── Derived helpers ────────────────────────────────────────────
    /// Current workspace index clamped into the list (host-proof)
    readonly property int clampedCurrent: root.workspaces.length > 0
                                          ? Math.max(0, Math.min(root.currentWorkspace,
                                                                 root.workspaces.length - 1))
                                          : 0

    /// The current workspace entry (null when the list is empty)
    readonly property var currentWorkspaceEntry: root.workspaces.length > 0
                                                 ? root.workspaces[root.clampedCurrent] : null

    /// Current workspace name ("" when the list is empty)
    readonly property string currentWorkspaceName: root.currentWorkspaceEntry !== null
                                                   ? String(root.currentWorkspaceEntry.name) : ""

    /// Whether a workspace entry is the current one
    function isCurrent(index) {
        return root.workspaces.length > 0 && index === root.clampedCurrent
    }

    /// Display name for a workspace entry (falls back to the id)
    function displayNameFor(entry) {
        if (entry === null || entry === undefined)
            return ""
        var n = entry.name !== undefined ? String(entry.name) : ""
        return n.length > 0 ? n : String(entry.id)
    }

    /// Window-count summary for a workspace entry ("" when absent/zero)
    function windowCountFor(entry) {
        if (entry === null || entry === undefined)
            return ""
        var c = entry.windowCount !== undefined ? Number(entry.windowCount) : 0
        return c > 0 ? qsTr("%1 windows").arg(c) : ""
    }

    /// Move keyboard focus to a workspace row (clamped, wraps)
    function focusRow(index) {
        if (root.workspaces.length === 0)
            return
        var count = root.workspaces.length
        var target = ((index % count) + count) % count
        var item = workspaceRows.itemAt(target)
        if (item !== null)
            item.forceActiveFocus()
    }

    // ── Test hooks (used by tests/tst_workspace_switcher.qml) ──────
    property alias backdropScrim: backdropScrim
    property alias switcherCard: switcherCard
    property alias titleLabel: titleLabel
    property alias workspaceRows: workspaceRows
    property alias emptyHint: emptyHint

    // ── Overlay backdrop (scrim over the desktop) ──────────────────
    // Fades in on presentation (reduced-motion aware): the scrim starts
    // transparent and Component.onCompleted animates it to full so the
    // switcher never pops abruptly over the desktop.
    Rectangle {
        id: backdropScrim
        objectName: "wsScrim"
        anchors.fill: parent
        color: Colors.scrim
        opacity: 0.0
        Behavior on opacity {
            enabled: !root.reducedMotion
            animation: NumberAnimation { duration: Motion.fadeIn }
        }
    }

    // ══════════════════════════════════════════════════════════════
    // Centered switcher card
    // ══════════════════════════════════════════════════════════════
    Rectangle {
        id: switcherCard
        objectName: "wsCard"
        anchors.centerIn: parent
        width: Math.min(480, root.width - Spacing.paddingLarge * 2)
        // Explicit height from content (the proven pattern — a plain
        // layout would otherwise collapse the card).
        height: cardColumn.height + Spacing.paddingLarge * 2
        radius: Radii.dialog
        color: MissionTheme.surface
        border.color: MissionTheme.outline
        border.width: 1

        Column {
            id: cardColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
            }
            anchors.margins: Spacing.paddingLarge
            spacing: Spacing.gapMedium

            // ── Title ──
            Label {
                id: titleLabel
                objectName: "wsTitle"
                text: qsTr("Workspaces")
                font.pixelSize: Typography.title.size
                font.weight: Typography.title.weight
                color: MissionTheme.textPrimary
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }

            // ── Workspace rows ──
            Repeater {
                id: workspaceRows
                model: root.workspaces

                delegate: Rectangle {
                    required property var modelData
                    required property int index

                    id: wsRow
                    objectName: "wsRow" + index
                    width: parent.width
                    height: Spacing.minimumTouchTarget + Spacing.paddingSmall
                    radius: Radii.card
                    // Current workspace gets the primary treatment; all
                    // rows hover on pointer entry (Login chip pattern)
                    color: root.isCurrent(index)
                           ? (MissionTheme.darkMode ? MissionTheme.primary
                                                    : MissionTheme.primaryContainer)
                           : (wsRowMouse.containsMouse ? MissionTheme.surfaceVariant
                                                       : MissionTheme.surfaceDim)
                    border.width: root.isCurrent(index) ? 0 : 1
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
                        visible: wsRow.activeFocus
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Spacing.paddingMedium
                        anchors.rightMargin: Spacing.paddingMedium
                        spacing: Spacing.gapMedium

                        // Workspace name
                        Label {
                            Layout.fillWidth: true
                            text: root.displayNameFor(modelData)
                            font.pixelSize: Typography.body.size
                            font.weight: root.isCurrent(index)
                                         ? Typography.weightSemibold : Typography.weightRegular
                            color: root.isCurrent(index)
                                   ? (MissionTheme.darkMode ? MissionTheme.contentOnPrimary
                                                           : MissionTheme.contentOnPrimaryContainer)
                                   : MissionTheme.textPrimary
                            elide: Text.ElideRight
                        }

                        // Optional window count (host model)
                        Label {
                            text: root.windowCountFor(modelData)
                            visible: text.length > 0
                            font.pixelSize: Typography.caption.size
                            color: root.isCurrent(index)
                                   ? (MissionTheme.darkMode ? MissionTheme.contentOnPrimary
                                                           : MissionTheme.contentOnPrimaryContainer)
                                   : MissionTheme.textSecondary
                        }

                        // Current marker (dot + text; color is never the
                        // only indicator — the Accessible name carries it)
                        Rectangle {
                            visible: root.isCurrent(index)
                            Layout.preferredWidth: 8
                            Layout.preferredHeight: 8
                            radius: 4
                            color: MissionTheme.darkMode ? MissionTheme.contentOnPrimary
                                                         : MissionTheme.primary
                        }
                    }

                    MouseArea {
                        id: wsRowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            wsRow.forceActiveFocus()
                            root.workspaceSelected(String(modelData.id))
                        }
                    }

                    // Keyboard-first: Up/Down move between rows, Enter/
                    // Space choose the focused workspace
                    Keys.onUpPressed: root.focusRow(index - 1)
                    Keys.onDownPressed: root.focusRow(index + 1)
                    Keys.onLeftPressed: root.focusRow(index - 1)
                    Keys.onRightPressed: root.focusRow(index + 1)
                    Keys.onReturnPressed: root.workspaceSelected(String(modelData.id))
                    Keys.onSpacePressed: root.workspaceSelected(String(modelData.id))

                    Accessible.role: Accessible.RadioButton
                    Accessible.name: root.isCurrent(index)
                                     ? qsTr("Workspace %1 of %2: %3 (current)")
                                         .arg(index + 1).arg(root.workspaces.length)
                                         .arg(root.displayNameFor(modelData))
                                     : qsTr("Workspace %1 of %2: %3")
                                         .arg(index + 1).arg(root.workspaces.length)
                                         .arg(root.displayNameFor(modelData))
                    Accessible.checked: root.isCurrent(index)
                }
            }

            // ── Empty hint (defensive; see interpretation notes) ──
            Label {
                id: emptyHint
                objectName: "wsEmpty"
                visible: root.workspaces.length === 0
                text: qsTr("No workspaces")
                font.pixelSize: Typography.bodySmall.size
                color: MissionTheme.textSecondary
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }
        }
    }

    // ── Initial focus (keyboard-first) ─────────────────────────────
    // The root claims focus so keyboard users land in the switcher
    // immediately, and the current workspace row is focused as soon as
    // the switcher appears so arrow + Enter works right away (Workspace
    // Flow is keyboard-operable per 02_DESKTOP.md §Keyboard Navigation).
    focus: true

    Component.onCompleted: {
        backdropScrim.opacity = 1.0
        if (root.workspaces.length > 0)
            root.focusRow(root.clampedCurrent)
    }
}
