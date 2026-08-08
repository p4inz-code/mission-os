// Mission OS — System Tray (MOS-DES-008)
//
// Eighth and final screen of the Mission OS desktop family.
// Implements the source-defined System Tray structure
// (docs/design/03_SCREEN_REGISTRY.md MOS-DES-008 "System Tray",
// docs/wireframes/03_DESKTOP.md component "System Tray",
// docs/design/01_INFORMATION_ARCHITECTURE.md §4 Desktop structure,
// docs/reference/02_DESKTOP.md §System Tray):
//
//   Hosting: an overlay the host shows above the Desktop, anchored
//   top-right (the established overlay treatment shared with
//   Notifications / Quick Settings / Calendar / Clipboard History).
//   The access point is host-side: the Desktop (MOS-DES-001) renders
//   the collapsed System Status chips in its top panel — "the full
//   System Tray is MOS-DES-008" (Desktop.qml interpretation note) —
//   and the host opens this surface from there, the same way the
//   host opens the Calendar from the taskbar Clock function. The
//   screen is a standalone registry screen like Calendar (MOS-DES-006)
//   and Clipboard History (MOS-DES-007): Desktop.qml needs no routing
//   change (family precedent — the last two family screens were added
//   without touching Desktop.qml).
//   Place inside MissionWindow (or MissionPage) content and anchor to
//   fill, e.g.  MissionWindow { SystemTray { anchors.fill: parent } }
//   The component sizes to its implicit 1280x720 like Desktop.qml.
//
//   System Tray (02_DESKTOP.md): "Displays persistent background
//   services. Examples: Network, Audio, Battery, Clipboard, Updates,
//   VPN, Accessibility, Security Status. Applications should not add
//   tray icons without user consent."
//
//   Desktop Layout (07_DESKTOP_LAYOUT.md §3): the top panel's System
//   Status is the collapsed entry point; this screen is the full
//   tray surface (documented interpretation — no authoritative source
//   specifies the expanded surface beyond the reference section).
//
// Interpretation notes (documented — no authoritative source specifies
// further detail):
//   - The panel is anchored top-right (the same overlay treatment as
//     the Notifications / Quick Settings / Calendar / Clipboard
//     History panels) and floats over a token scrim so it never
//     obscures the desktop it summarizes.
//   - The host drives the `trayItems` model; each entry is
//     { id, label?, status?, level? }. `label` is displayed and falls
//     back to the id (same contract as QuickSettings tiles). `status`
//     is the host's human-readable state text (e.g. "Connected",
//     "100%", "Up to date", "Idle") and is the primary state
//     indicator. `level` ∈ "ok" | "warning" | "critical" (defaults to
//     "ok" when absent — defensive, like Notifications' level default)
//     drives the semantic status dot.
//   - Color is never the only indicator: the level text tag (OK /
//     Warning / Critical) is rendered whenever the level is notable
//     (warning/critical) OR the host supplied no status text (so a
//     state-conveying dot never appears without a non-color
//     indicator), and the Accessible name always carries the level
//     label. The host's status text is always shown verbatim.
//   - Activation (the tray's core interaction — a tray item opens its
//     full status surface, e.g. Network → the network app, Battery →
//     power settings): clicking / Enter / Space on an item emits
//     trayItemActivated(id) and the host opens the corresponding
//     surface. This mirrors the Notifications "Take Action" contract:
//     the screen presents the list, the host owns navigation.
//   - "Applications should not add tray icons without user consent"
//     (reference): rendered as an always-visible privacy caption (the
//     Clipboard History screen's privacy footer pattern); the consent
//     policy itself is host-side.
//   - Escape is deliberately unmapped (same contract as MOS-LCK-001..004
//     and MOS-DES-001/002/003/004/005/006/007): the panel must not
//     dismiss itself — the host owns overlay dismissal.
//   - Empty tray degrades to a neutral hint (defensive).
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
    /// System tray items: [{ id, label?, status?, level? }] —
    /// host-driven. id is what trayItemActivated carries; label is
    /// displayed (falls back to id); status is the host's
    /// human-readable state text; level ∈ "ok" | "warning" |
    /// "critical" (defaults to "ok") drives the semantic status dot.
    /// The screen never mutates the model — the host owns the
    /// services it describes.
    property var trayItems: []

    /// Reduced motion (accessibility)
    property bool reducedMotion: false

    // ── Signals (host wiring) ──────────────────────────────────────
    /// User activated a tray item (the host opens the item's full
    /// status surface — e.g. Network → the network app)
    signal trayItemActivated(string itemId)

    // Escape is deliberately unmapped (see interpretation notes): the
    // panel must not dismiss itself. No Keys.onEscapePressed here.

    // ── Derived helpers ────────────────────────────────────────────
    /// Display label for a tray entry (falls back to the id; empty
    /// when the entry itself is missing — defensive)
    function labelFor(entry) {
        if (entry === null || entry === undefined)
            return ""
        var l = entry.label !== undefined ? String(entry.label) : ""
        return l.length > 0 ? l : String(entry.id)
    }

    /// Host status text for a tray entry ("" when absent — defensive)
    function statusFor(entry) {
        if (entry === null || entry === undefined)
            return ""
        return entry.status !== undefined ? String(entry.status) : ""
    }

    /// Normalized level for a tray entry: "ok" | "warning" | "critical"
    /// (anything unknown or absent falls back to "ok" — matches the
    /// Notifications level-default contract)
    function levelOf(entry) {
        if (entry === null || entry === undefined)
            return "ok"
        var l = String(entry.level)
        if (l !== "ok" && l !== "warning" && l !== "critical")
            return "ok"
        return l
    }

    /// Level → token color (dot; the level text tag + Accessible name
    /// carry the level so color is never the only indicator)
    function levelColor(level) {
        switch (String(level)) {
        case "warning":  return MissionTheme.warning
        case "critical": return MissionTheme.error
        default:         return MissionTheme.success
        }
    }

    /// Level → display label (accessibility + text tag)
    function levelLabel(level) {
        switch (String(level)) {
        case "warning":  return qsTr("Warning")
        case "critical": return qsTr("Critical")
        default:         return qsTr("OK")
        }
    }

    /// Whether the level text tag is rendered on a row: always when
    /// the level is notable (warning/critical), and also when the host
    /// supplied no status text — so a state-conveying dot never
    /// appears without a non-color indicator. OK items with a status
    /// text need no tag (the status text is the indicator).
    function showLevelTag(entry) {
        return root.levelOf(entry) !== "ok" ||
               root.statusFor(entry).length === 0
    }

    /// Accessible name for a tray row: label, then status text (when
    /// present), then the level label — the level is ALWAYS carried so
    /// screen readers never rely on the dot alone.
    function rowName(entry) {
        var name = root.labelFor(entry)
        var status = root.statusFor(entry)
        if (status.length > 0)
            name += qsTr(", %1").arg(status)
        name += qsTr(", %1").arg(root.levelLabel(root.levelOf(entry)))
        return name
    }

    /// Number of tray items in the host model
    readonly property int trayCount: root.trayItems.length

    /// Move keyboard focus to a tray row (clamped, wraps)
    function focusRow(index) {
        if (root.trayItems.length === 0)
            return
        var count = root.trayItems.length
        var target = ((index % count) + count) % count
        var item = trayRows.itemAt(target)
        if (item !== null)
            item.forceActiveFocus()
    }

    // ── Test hooks (used by tests/tst_system_tray.qml) ─────────────
    property alias backdropScrim: backdropScrim
    property alias trayPanel: trayPanel
    property alias titleLabel: titleLabel
    property alias trayRows: trayRows
    property alias emptyHint: emptyHint
    property alias privacyCaption: privacyCaption

    // ── Overlay backdrop (scrim over the desktop) ──────────────────
    // Fades in on presentation (reduced-motion aware): the scrim starts
    // transparent and Component.onCompleted animates it to full so the
    // panel never pops abruptly over the desktop.
    Rectangle {
        id: backdropScrim
        objectName: "trayScrim"
        anchors.fill: parent
        color: Colors.scrim
        opacity: 0.0
        Behavior on opacity {
            enabled: !root.reducedMotion
            animation: NumberAnimation { duration: Motion.fadeIn }
        }
    }

    // ══════════════════════════════════════════════════════════════
    // System Tray panel (02_DESKTOP.md §System Tray — the top-right
    // overlay treatment shared with the family)
    // ══════════════════════════════════════════════════════════════
    Rectangle {
        id: trayPanel
        objectName: "trayPanel"
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

            // ── Header: title ──
            Label {
                id: titleLabel
                objectName: "trayTitle"
                text: qsTr("System Tray")
                font.pixelSize: Typography.title.size
                font.weight: Typography.title.weight
                color: MissionTheme.textPrimary
                elide: Text.ElideRight
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }

            // ── Tray item rows (scrolls when the list overflows) ──
            // The list area gets at least 72px and at most 400px (or
            // the window minus header space); the panel sizes to its
            // content and the list scrolls beyond that.
            Flickable {
                id: scrollArea
                width: parent.width
                height: Math.max(72, Math.min(400,
                                 root.height - Spacing.paddingLarge * 4 - 112))
                clip: true
                interactive: contentHeight > height
                contentHeight: listColumn.implicitHeight

                Column {
                    id: listColumn
                    width: parent.width
                    spacing: Spacing.gapSmall

                    Repeater {
                        id: trayRows
                        model: root.trayItems

                        delegate: Rectangle {
                            required property var modelData
                            required property int index

                            id: trayRow
                            objectName: "trayItem" + index
                            width: parent.width
                            height: Spacing.minimumTouchTarget
                            radius: Radii.card
                            color: trayRowMouse.containsMouse
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
                                visible: trayRow.activeFocus
                            }

                            // Row click = activate the item (the host
                            // opens the item's full status surface).
                            // The row has no interactive children, so
                            // this MouseArea owns all pointer input.
                            MouseArea {
                                id: trayRowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    trayRow.forceActiveFocus()
                                    root.trayItemActivated(String(modelData.id))
                                }
                            }

                            // ── Row content: level dot · level tag ·
                            //    label · status ──
                            RowLayout {
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    top: parent.top
                                    bottom: parent.bottom
                                }
                                anchors.leftMargin: Spacing.paddingMedium
                                anchors.rightMargin: Spacing.paddingMedium
                                spacing: Spacing.gapSmall

                                // Semantic status dot (level-driven;
                                // the tag + Accessible name carry the
                                // level so color is never the only
                                // indicator)
                                Rectangle {
                                    Layout.preferredWidth: 8
                                    Layout.preferredHeight: 8
                                    radius: 4
                                    color: root.levelColor(root.levelOf(modelData))
                                }

                                // Level text tag (rendered when
                                // notable or when the host gave no
                                // status text — see showLevelTag)
                                Label {
                                    visible: root.showLevelTag(modelData)
                                    text: root.levelLabel(root.levelOf(modelData))
                                    font.pixelSize: Typography.caption.size
                                    color: MissionTheme.textSecondary
                                }

                                // Service label (falls back to the id)
                                Label {
                                    Layout.fillWidth: true
                                    text: root.labelFor(modelData)
                                    font.pixelSize: Typography.body.size
                                    font.weight: Typography.weightMedium
                                    color: MissionTheme.textPrimary
                                    elide: Text.ElideRight
                                }

                                // Host status text (the primary state
                                // indicator; right-aligned)
                                Label {
                                    visible: root.statusFor(modelData).length > 0
                                    text: root.statusFor(modelData)
                                    font.pixelSize: Typography.bodySmall.size
                                    color: MissionTheme.textTertiary
                                    elide: Text.ElideRight
                                }
                            }

                            // Keyboard-first: Up/Down move between
                            // rows, Enter/Space activate the focused
                            // item
                            Keys.onUpPressed: root.focusRow(index - 1)
                            Keys.onDownPressed: root.focusRow(index + 1)
                            Keys.onLeftPressed: root.focusRow(index - 1)
                            Keys.onRightPressed: root.focusRow(index + 1)
                            Keys.onReturnPressed:
                                root.trayItemActivated(String(modelData.id))
                            Keys.onSpacePressed:
                                root.trayItemActivated(String(modelData.id))

                            Accessible.role: Accessible.Button
                            Accessible.name: root.rowName(modelData)
                        }
                    }

                    // ── Empty hint (defensive) ──
                    Column {
                        id: emptyHint
                        objectName: "trayEmpty"
                        visible: root.trayCount === 0
                        width: parent.width
                        spacing: Spacing.gapSmall

                        Label {
                            width: parent.width
                            text: qsTr("No system tray items")
                            font.pixelSize: Typography.body.size
                            font.weight: Typography.weightSemibold
                            color: MissionTheme.textPrimary
                            wrapMode: Text.WordWrap
                            Accessible.role: Accessible.StaticText
                            Accessible.name: text
                        }

                        Label {
                            width: parent.width
                            text: qsTr("Indicators for running background services will appear here.")
                            font.pixelSize: Typography.bodySmall.size
                            color: MissionTheme.textSecondary
                            wrapMode: Text.WordWrap
                            Accessible.role: Accessible.StaticText
                            Accessible.name: text
                        }
                    }
                }
            }

            // ── Privacy footer (reference: "Applications should not
            //    add tray icons without user consent") — always
            //    visible on this screen ──
            Label {
                id: privacyCaption
                objectName: "trayPrivacy"
                width: parent.width
                text: qsTr("Applications must request permission before adding items to the system tray")
                font.pixelSize: Typography.caption.size
                color: MissionTheme.textTertiary
                wrapMode: Text.WordWrap
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }
        }
    }

    // ── Initial focus (keyboard-first) ─────────────────────────────
    // The root claims focus so keyboard users land in the panel
    // immediately, and the first tray item is focused as soon as the
    // panel appears so arrow + Enter works right away (desktop §Keyboard
    // Navigation — the System Tray is keyboard-operable).
    focus: true

    Component.onCompleted: {
        backdropScrim.opacity = 1.0
        if (root.trayItems.length > 0)
            root.focusRow(0)
    }
}
