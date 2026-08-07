// Mission OS — Quick Settings (MOS-DES-004)
//
// Fourth screen of the Mission OS desktop family.
// Implements the source-defined Quick Settings structure
// (docs/design/03_SCREEN_REGISTRY.md MOS-DES-004 "Quick Settings",
// docs/wireframes/03_DESKTOP.md component "Quick Settings",
// docs/design/07_DESKTOP_LAYOUT.md §7, docs/reference/02_DESKTOP.md
// §Quick Settings, docs/design/04_USER_FLOWS.md Network Connection +
// VPN flows, docs/engineering/RUNTIME_ARCHITECTURE.md
// `org.mission.plasma.quick-settings`):
//
//   Hosting: an overlay the host shows above the Desktop (MOS-DES-001
//   routes here via quickSettingsRequested; the host's Quick Settings
//   button lives at the right end of the top panel — 07_DESKTOP_LAYOUT
//   §7 "Accessible from the top panel"). Place inside MissionWindow (or
//   MissionPage) content and anchor to fill, e.g.
//   MissionWindow { QuickSettings { anchors.fill: parent } }.
//   The component sizes to its implicit 1280x720 like Desktop.qml.
//
//   Quick Settings (02_DESKTOP.md): "Accessible from the taskbar.
//   Contains configurable tiles such as: Wi-Fi, Bluetooth, Volume,
//   Brightness, Night Light, Airplane Mode, VPN, Focus Mode, Privacy
//   Mode, Screen Recording, Microphone, Camera, Battery Saver. Users
//   can reorder, add, or remove tiles." 07_DESKTOP_LAYOUT §7 adds
//   Power to the tile set.
//
//   User Flows (#Network Connection / #VPN): both journeys begin at
//   Quick Settings and continue into the network surface (Select
//   Connection / Choose Profile). This screen presents the tile grid
//   and emits tileToggled(id) for the chosen tile; opening the network
//   surface is the host's job (the host decides which tile ids route
//   into the network flow).
//
// Interpretation notes (documented — no authoritative source specifies
// further detail):
//   - The panel is anchored top-right (the same overlay treatment as
//     MOS-DES-003, and directly below the top-panel Quick Settings
//     button in Desktop.qml) and floats over a token scrim so it never
//     obscures the desktop it summarizes.
//   - The host drives the `tiles` model; each entry is
//     { id, label?, active? }. The host supplies any of the reference
//     tiles (Wi-Fi, Bluetooth, Night Light, Airplane Mode, VPN, Focus
//     Mode, Privacy Mode, Screen Recording, Microphone, Camera, Battery
//     Saver, Power). Reorder / add / remove (reference: "Users can
//     reorder, add, or remove tiles") are host-side model operations —
//     this screen renders whatever the host provides, exactly like the
//     notifications / workspaces models in the family.
//   - `active` is host state: a tile click emits tileToggled(id) and
//     the host flips the model entry; the screen never mutates the
//     model itself (family contract — WorkspaceSwitcher/Notifications
//     behave the same). The rendered state therefore always reflects
//     the host's model.
//   - Volume and Brightness (reference tiles) are rendered as dedicated
//     continuous slider rows (the established quick-settings pattern for
//     level controls; documented interpretation — the reference lists
//     them among the configurable tiles, and a slider is the minimal
//     faithful surface for a 0-100 level). The host drives `volume` and
//     `brightness`; user interaction emits volumeLevelChanged /
//     brightnessLevelChanged and the host writes the value back.
//   - Escape is deliberately unmapped (same contract as MOS-LCK-001..004
//     and MOS-DES-001/002/003): the panel must not dismiss itself — the
//     host owns overlay dismissal.
//   - Empty tiles model degrades to a neutral hint (defensive).
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
    /// Quick Settings tiles: [{ id, label?, active? }] — host-driven.
    /// id is what tileToggled carries; label is displayed (falls back
    /// to id); active renders the tile's On/Off state (never mutated
    /// here — the host owns the model).
    property var tiles: []

    /// Volume level 0-100 (host-driven; rendered by the Volume slider)
    property int volume: 50
    /// Brightness level 0-100 (host-driven; rendered by the Brightness
    /// slider)
    property int brightness: 80

    /// Reduced motion (accessibility)
    property bool reducedMotion: false

    // ── Signals (host wiring) ──────────────────────────────────────
    /// User activated a tile (the Quick Settings action step; the host
    /// flips the model entry and, for network tiles, routes into the
    /// Network Connection / VPN flows)
    signal tileToggled(string tileId)
    /// User moved the Volume slider to a new 0-100 level.
    /// (Named volumeLevelChanged: `volumeChanged` is reserved by QML
    /// for the property-change signal of `volume`, so the interaction
    /// signal carries the explicit `Level` suffix.)
    signal volumeLevelChanged(int value)
    /// User moved the Brightness slider to a new 0-100 level (see
    /// volumeLevelChanged for the naming note)
    signal brightnessLevelChanged(int value)

    // Escape is deliberately unmapped (see interpretation notes): the
    // panel must not dismiss itself. No Keys.onEscapePressed here.

    // ── Host re-sync (slider contract) ─────────────────────────────
    // The sliders render the host's volume/brightness and emit
    // volumeLevelChanged/brightnessLevelChanged only on user interaction
    // (`moved` never fires for programmatic value changes). These
    // property-change handlers keep the slider following the host when
    // the level changes from elsewhere (e.g. media keys / another
    // surface): they run synchronously on the host property change and
    // write the host value to the slider; the equality guard makes that
    // a no-op whenever the slider already matches. No feedback loop —
    // programmatic value writes never emit `moved`.
    onVolumeChanged: {
        if (Math.abs(volumeSlider.value - root.volume) > 0.01)
            volumeSlider.value = root.volume
    }
    onBrightnessChanged: {
        if (Math.abs(brightnessSlider.value - root.brightness) > 0.01)
            brightnessSlider.value = root.brightness
    }

    // ── Derived helpers ────────────────────────────────────────────
    /// Whether a tile entry is active (host state; false when absent)
    function isActive(entry) {
        return entry !== null && entry !== undefined && entry.active === true
    }

    /// Display label for a tile entry (falls back to the id)
    function labelFor(entry) {
        if (entry === null || entry === undefined)
            return ""
        var l = entry.label !== undefined ? String(entry.label) : ""
        return l.length > 0 ? l : String(entry.id)
    }

    /// On/Off state tag — the text indicator so color is never the
    /// only signal for a tile's state
    function stateLabel(entry) {
        return root.isActive(entry) ? qsTr("On") : qsTr("Off")
    }

    /// Number of tiles in the host model
    readonly property int tileCount: root.tiles.length

    /// Move keyboard focus to a tile (clamped, wraps — 2-column grid:
    /// Left/Right step one, Up/Down step two)
    function focusTile(index) {
        if (root.tiles.length === 0)
            return
        var count = root.tiles.length
        var target = ((index % count) + count) % count
        var item = tileRepeater.itemAt(target)
        if (item !== null)
            item.forceActiveFocus()
    }

    // ── Test hooks (used by tests/tst_quick_settings.qml) ──────────
    property alias backdropScrim: backdropScrim
    property alias quickPanel: quickPanel
    property alias titleLabel: titleLabel
    property alias tileGrid: tileGrid
    property alias tileRepeater: tileRepeater
    property alias emptyHint: emptyHint
    property alias volumeSlider: volumeSlider
    property alias volumeValueLabel: volumeValueLabel
    property alias brightnessSlider: brightnessSlider
    property alias brightnessValueLabel: brightnessValueLabel

    // ── Overlay backdrop (scrim over the desktop) ──────────────────
    // Fades in on presentation (reduced-motion aware): the scrim starts
    // transparent and Component.onCompleted animates it to full so the
    // panel never pops abruptly over the desktop.
    Rectangle {
        id: backdropScrim
        objectName: "qsScrim"
        anchors.fill: parent
        color: Colors.scrim
        opacity: 0.0
        Behavior on opacity {
            enabled: !root.reducedMotion
            animation: NumberAnimation { duration: Motion.fadeIn }
        }
    }

    // ══════════════════════════════════════════════════════════════
    // Quick Settings panel (07_DESKTOP_LAYOUT.md §7 — top panel
    // access; anchored top-right like the Notifications overlay)
    // ══════════════════════════════════════════════════════════════
    Rectangle {
        id: quickPanel
        objectName: "qsPanel"
        anchors {
            top: parent.top
            right: parent.right
            margins: Spacing.paddingLarge
        }
        // Panel trims to the window on narrow layouts
        width: Math.min(380, root.width - Spacing.paddingLarge * 2)
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
                objectName: "qsTitle"
                text: qsTr("Quick Settings")
                font.pixelSize: Typography.title.size
                font.weight: Typography.title.weight
                color: MissionTheme.textPrimary
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }

            // ── Toggle tiles (2-column grid, host model) ──
            // The reference tile set (02_DESKTOP.md / 07_DESKTOP_LAYOUT
            // §7) is host-supplied; this grid renders it as-is. Tile
            // state comes from the model and is never mutated here.
            Grid {
                id: tileGrid
                width: parent.width
                columns: 2
                columnSpacing: Spacing.gapSmall
                rowSpacing: Spacing.gapSmall

                Repeater {
                    id: tileRepeater
                    model: root.tiles

                    delegate: Rectangle {
                        required property var modelData
                        required property int index

                        id: tile
                        objectName: "qsTile" + index
                        width: (tileGrid.width - tileGrid.columnSpacing) / 2
                        height: Spacing.minimumTouchTarget + Spacing.paddingSmall
                        radius: Radii.card
                        // Active tiles get the primary treatment (same
                        // pattern as the WorkspaceSwitcher current row);
                        // inactive tiles hover on pointer entry
                        color: root.isActive(modelData)
                               ? (MissionTheme.darkMode ? MissionTheme.primary
                                                        : MissionTheme.primaryContainer)
                               : (tileMouse.containsMouse ? MissionTheme.surfaceVariant
                                                          : MissionTheme.surfaceDim)
                        border.width: root.isActive(modelData) ? 0 : 1
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
                            visible: tile.activeFocus
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Spacing.paddingMedium
                            anchors.rightMargin: Spacing.paddingMedium
                            spacing: Spacing.gapSmall

                            // Tile label
                            Label {
                                Layout.fillWidth: true
                                text: root.labelFor(modelData)
                                font.pixelSize: Typography.body.size
                                font.weight: root.isActive(modelData)
                                             ? Typography.weightSemibold
                                             : Typography.weightMedium
                                color: root.isActive(modelData)
                                       ? (MissionTheme.darkMode ? MissionTheme.contentOnPrimary
                                                               : MissionTheme.contentOnPrimaryContainer)
                                       : MissionTheme.textPrimary
                                elide: Text.ElideRight
                            }

                            // State dot + On/Off tag (the tag text is
                            // the real indicator; color is never the
                            // only signal for the tile state)
                            Rectangle {
                                Layout.preferredWidth: 6
                                Layout.preferredHeight: 6
                                radius: 3
                                color: root.isActive(modelData)
                                       ? (MissionTheme.darkMode ? MissionTheme.contentOnPrimary
                                                               : MissionTheme.primary)
                                       : MissionTheme.textTertiary
                            }
                            Label {
                                text: root.stateLabel(modelData)
                                font.pixelSize: Typography.caption.size
                                color: root.isActive(modelData)
                                       ? (MissionTheme.darkMode ? MissionTheme.contentOnPrimary
                                                               : MissionTheme.contentOnPrimaryContainer)
                                       : MissionTheme.textSecondary
                            }
                        }

                        MouseArea {
                            id: tileMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                tile.forceActiveFocus()
                                root.tileToggled(String(modelData.id))
                            }
                        }

                        // Keyboard-first: arrows navigate the 2-column
                        // grid, Enter/Space toggle the focused tile
                        Keys.onLeftPressed: root.focusTile(index - 1)
                        Keys.onRightPressed: root.focusTile(index + 1)
                        Keys.onUpPressed: root.focusTile(index - 2)
                        Keys.onDownPressed: root.focusTile(index + 2)
                        Keys.onReturnPressed: root.tileToggled(String(modelData.id))
                        Keys.onSpacePressed: root.tileToggled(String(modelData.id))

                        Accessible.role: Accessible.CheckBox
                        Accessible.name: qsTr("%1, %2")
                            .arg(root.labelFor(modelData))
                            .arg(root.stateLabel(modelData))
                        Accessible.checked: root.isActive(modelData)
                    }
                }

            }

            // ── Empty hint (defensive; see interpretation notes) ──
            Label {
                id: emptyHint
                objectName: "qsEmpty"
                visible: root.tiles.length === 0
                text: qsTr("No quick settings tiles")
                font.pixelSize: Typography.bodySmall.size
                color: MissionTheme.textSecondary
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }

            // ── Volume (continuous level; see interpretation notes) ──
            RowLayout {
                id: volumeRow
                width: parent.width
                spacing: Spacing.gapMedium

                Label {
                    text: qsTr("Volume")
                    Layout.minimumWidth: 80
                    font.pixelSize: Typography.body.size
                    color: MissionTheme.textPrimary
                    verticalAlignment: Text.AlignVCenter
                }

                Slider {
                    id: volumeSlider
                    objectName: "qsVolume"
                    Layout.fillWidth: true
                    Layout.preferredHeight: Spacing.minimumTouchTarget
                    from: 0
                    to: 100
                    stepSize: 1
                    // Host-driven level; `moved` fires only on user
                    // interaction (never on programmatic value changes),
                    // so the host's volume property stays authoritative.
                    value: root.volume
                    onMoved: root.volumeLevelChanged(Math.round(volumeSlider.value))

                    // Token-styled groove + fill
                    background: Rectangle {
                        x: volumeSlider.leftPadding
                        y: volumeSlider.topPadding + volumeSlider.availableHeight / 2 - height / 2
                        width: volumeSlider.availableWidth
                        height: 6
                        radius: 3
                        color: MissionTheme.surfaceDim

                        Rectangle {
                            width: volumeSlider.visualPosition * parent.width
                            height: parent.height
                            radius: 3
                            color: MissionTheme.primary
                        }
                    }

                    // Token-styled handle with a visible focus ring
                    handle: Rectangle {
                        x: volumeSlider.leftPadding +
                           volumeSlider.visualPosition * (volumeSlider.availableWidth - width)
                        y: volumeSlider.topPadding +
                           volumeSlider.availableHeight / 2 - height / 2
                        width: 20
                        height: 20
                        radius: 10
                        color: volumeSlider.pressed ? MissionTheme.primaryDark
                                                    : MissionTheme.primary
                        border.color: MissionTheme.surface
                        border.width: 2

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -4
                            radius: 14
                            color: "transparent"
                            border.color: MissionTheme.focusRing
                            border.width: 2
                            visible: volumeSlider.activeFocus
                        }
                    }

                    Accessible.name: qsTr("Volume")
                }

                Label {
                    id: volumeValueLabel
                    objectName: "qsVolumeValue"
                    text: qsTr("%1%").arg(Math.round(volumeSlider.value))
                    Layout.minimumWidth: 40
                    horizontalAlignment: Text.AlignRight
                    font.pixelSize: Typography.caption.size
                    color: MissionTheme.textSecondary
                    verticalAlignment: Text.AlignVCenter
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }
            }

            // ── Brightness (continuous level; same contract) ──
            RowLayout {
                id: brightnessRow
                width: parent.width
                spacing: Spacing.gapMedium

                Label {
                    text: qsTr("Brightness")
                    Layout.minimumWidth: 80
                    font.pixelSize: Typography.body.size
                    color: MissionTheme.textPrimary
                    verticalAlignment: Text.AlignVCenter
                }

                Slider {
                    id: brightnessSlider
                    objectName: "qsBrightness"
                    Layout.fillWidth: true
                    Layout.preferredHeight: Spacing.minimumTouchTarget
                    from: 0
                    to: 100
                    stepSize: 1
                    value: root.brightness
                    onMoved: root.brightnessLevelChanged(Math.round(brightnessSlider.value))

                    background: Rectangle {
                        x: brightnessSlider.leftPadding
                        y: brightnessSlider.topPadding + brightnessSlider.availableHeight / 2 - height / 2
                        width: brightnessSlider.availableWidth
                        height: 6
                        radius: 3
                        color: MissionTheme.surfaceDim

                        Rectangle {
                            width: brightnessSlider.visualPosition * parent.width
                            height: parent.height
                            radius: 3
                            color: MissionTheme.primary
                        }
                    }

                    handle: Rectangle {
                        x: brightnessSlider.leftPadding +
                           brightnessSlider.visualPosition * (brightnessSlider.availableWidth - width)
                        y: brightnessSlider.topPadding +
                           brightnessSlider.availableHeight / 2 - height / 2
                        width: 20
                        height: 20
                        radius: 10
                        color: brightnessSlider.pressed ? MissionTheme.primaryDark
                                                        : MissionTheme.primary
                        border.color: MissionTheme.surface
                        border.width: 2

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -4
                            radius: 14
                            color: "transparent"
                            border.color: MissionTheme.focusRing
                            border.width: 2
                            visible: brightnessSlider.activeFocus
                        }
                    }

                    Accessible.name: qsTr("Brightness")
                }

                Label {
                    id: brightnessValueLabel
                    objectName: "qsBrightnessValue"
                    text: qsTr("%1%").arg(Math.round(brightnessSlider.value))
                    Layout.minimumWidth: 40
                    horizontalAlignment: Text.AlignRight
                    font.pixelSize: Typography.caption.size
                    color: MissionTheme.textSecondary
                    verticalAlignment: Text.AlignVCenter
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }
            }
        }
    }

    // ── Initial focus (keyboard-first) ─────────────────────────────
    // The root claims focus so keyboard users land in the panel
    // immediately, and the first tile is focused as soon as the panel
    // appears so arrow + Enter works right away (desktop §Keyboard
    // Navigation — Quick Settings is keyboard-operable).
    focus: true

    Component.onCompleted: {
        backdropScrim.opacity = 1.0
        if (root.tiles.length > 0)
            root.focusTile(0)
    }
}
