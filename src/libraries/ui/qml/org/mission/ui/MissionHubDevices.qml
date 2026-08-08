// Mission OS — Mission Hub Devices (MOS-HUB-009)
//
// Ninth screen of the Mission Hub family. Implements the source-defined
// Devices structure (docs/design/03_SCREEN_REGISTRY.md MOS-HUB-009
// "Devices", docs/reference/03_MISSION_HUB.md §2 Device Manager,
// docs/design/01_INFORMATION_ARCHITECTURE.md §5 Mission Hub Structure,
// docs/design/04_USER_FLOWS.md §5 Launch Application):
//
//   Hosting: a full-screen application within Mission Hub. Place inside
//   MissionWindow content and anchor to fill, e.g.
//   MissionWindow { MissionHubDevices { anchors.fill: parent } }
//   The component sizes to its implicit 1280x720 like Desktop.qml.
//
//   Layout (Master UX Specification §3):
//     Header → Sidebar Navigation → Main Content Area
//
//   Device Manager (reference §2):
//     Displays connected: USB devices, Displays, Audio devices,
//     Bluetooth devices, Network adapters, Storage devices, Input
//     devices.
//     "Users may: refresh, identify, disable (where supported),
//     troubleshoot."
//
// Interpretation notes (documented — no authoritative source specifies
// further detail):
//   - The device model is host-driven: each entry is
//     { id, name, type?, status?, description?, details?,
//       disableSupported? }.
//     type ∈ "usb" | "display" | "audio" | "bluetooth" | "network" |
//     "storage" | "input" (the seven categories listed by reference §2).
//     status ∈ "connected" | "disabled" | "unknown" — "unknown" is the
//     defensive fallback when the host omits status.
//     disableSupported (bool, default true) implements the "(where
//     supported)" qualifier for the disable action.
//   - The screen never performs hardware operations and never mutates
//     the model: refresh, identify, disable and troubleshoot all emit
//     host-facing signals; the host (device daemon) performs the real
//     operation.
//   - The overview shows Connected/Disabled/Total counts derived from
//     the model (Dashboard shows "Connected Devices" with a "3 connected"
//     status — reference §5).
//   - Escape is deliberately unmapped.
//   - Offline state shows a neutral message — Mission Hub works fully
//     offline; previously detected devices remain visible.
//
// Design-system compliance:
//   - Tokens only (Colors, Typography, Spacing, Radii, Motion, MissionTheme)
//   - Light + dark themes via MissionTheme (driven by host)
//   - Keyboard navigation with visible focus states; 44px minimum touch
//     targets (Spacing.minimumTouchTarget)
//   - WCAG AA-oriented contrast, reduced-motion aware
//   - Responsive reflow per docs/design/14_RESPONSIVE_RULES.md

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.mission.ui 1.0

FocusScope {
    id: root

    implicitWidth: 1280
    implicitHeight: 720

    // ── Public API ─────────────────────────────────────────────────
    /// Screen state: "normal" | "loading" | "empty" | "offline" | "error"
    property string screenState: "normal"

    /// Mission OS version string
    property string version: "0.1.0"

    /// Build channel: Stable | Beta | Nightly
    property string buildType: "Nightly"

    /// Reduced motion (accessibility)
    property bool reducedMotion: false

    /// Connected devices: [{ id, name, type?, status?, description?,
    ///                       details?, disableSupported? }]
    /// type ∈ "usb" | "display" | "audio" | "bluetooth" | "network" |
    ///       "storage" | "input"
    /// status ∈ "connected" | "disabled" | "unknown"
    property var devices: []

    /// Navigation items: [{ id, label, icon? }]
    property var navigationItems: [
        { id: "dashboard",   label: "Dashboard" },
        { id: "security",    label: "Security" },
        { id: "privacy",     label: "Privacy" },
        { id: "updates",     label: "Updates" },
        { id: "recovery",    label: "Recovery" },
        { id: "diagnostics", label: "Diagnostics" },
        { id: "drivers",     label: "Drivers" },
        { id: "storage",     label: "Storage" },
        { id: "devices",     label: "Devices" },
        { id: "workspaces",  label: "Workspaces" },
        { id: "settings",    label: "Settings" }
    ]

    /// Currently selected navigation item id
    property string selectedNavId: "devices"

    // ── Signals (host wiring) ──────────────────────────────────────
    /// User requested a device list refresh
    signal refreshDevices()
    /// User requested to identify a device (host flashes/locates it)
    signal identifyDevice(string deviceId)
    /// User requested to disable a device (host applies where supported)
    signal disableDevice(string deviceId)
    /// User requested troubleshooting for a device (host opens tooling)
    signal troubleshootDevice(string deviceId)
    /// User activated a navigation item (host opens the screen)
    signal navigationActivated(string navId)

    // Escape is deliberately unmapped: the host owns window-level dismissal.

    // ── Derived helpers ────────────────────────────────────────────
    /// Total number of devices
    readonly property int deviceCount: root.devices.length

    /// Number of connected devices
    readonly property int connectedCount: {
        var c = 0
        for (var i = 0; i < root.devices.length; i++) {
            if (String(root.devices[i].status) === "connected") c++
        }
        return c
    }

    /// Number of disabled devices
    readonly property int disabledCount: {
        var c = 0
        for (var i = 0; i < root.devices.length; i++) {
            if (String(root.devices[i].status) === "disabled") c++
        }
        return c
    }

    /// Number of navigation items
    readonly property int navCount: root.navigationItems.length

    /// Whether the sidebar is expanded (wide layout)
    readonly property bool sidebarExpanded: root.width >= 768

    /// Display label for a navigation item (falls back to id)
    function navLabel(item) {
        if (item === null || item === undefined) return ""
        var l = item.label !== undefined ? String(item.label) : ""
        return l.length > 0 ? l : String(item.id)
    }

    /// Device type → display label
    function deviceTypeLabel(type) {
        switch (String(type)) {
        case "usb":       return qsTr("USB")
        case "display":   return qsTr("Display")
        case "audio":     return qsTr("Audio")
        case "bluetooth": return qsTr("Bluetooth")
        case "network":   return qsTr("Network Adapter")
        case "storage":   return qsTr("Storage")
        case "input":     return qsTr("Input")
        default:          return qsTr("Unknown")
        }
    }

    /// Device status → display label
    function deviceStatusLabel(status) {
        switch (String(status)) {
        case "connected": return qsTr("Connected")
        case "disabled":  return qsTr("Disabled")
        default:          return qsTr("Unknown")
        }
    }

    /// Device status → token color
    function deviceStatusColor(status) {
        switch (String(status)) {
        case "connected": return MissionTheme.success
        case "disabled":  return MissionTheme.textSecondary
        default:          return MissionTheme.textSecondary
        }
    }

    /// Whether the disable action is supported for a device
    /// (implements the "(where supported)" qualifier in reference §2)
    function disableSupported(value) {
        return value !== false
    }

    /// Move keyboard focus to a navigation item
    function focusNavItem(index) {
        if (root.navigationItems.length === 0) return
        var count = root.navigationItems.length
        var target = ((index % count) + count) % count
        var item = navRepeater.itemAt(target)
        if (item !== null) item.forceActiveFocus()
    }

    // ── Test hooks ──
    property alias headerBar: headerBar
    property alias titleLabel: titleLabel
    property alias sidebar: sidebar
    property alias navRepeater: navRepeater
    property alias mainContent: mainContent
    property alias deviceRepeater: deviceRepeater
    property alias refreshButton: refreshButton
    property alias loadingIndicator: loadingIndicator
    property alias errorBanner: errorBanner
    property alias offlineBanner: offlineBanner
    property alias emptyHint: emptyHint

    // ══════════════════════════════════════════════════════════════
    // Background
    // ══════════════════════════════════════════════════════════════
    Rectangle {
        anchors.fill: parent
        color: MissionTheme.background
    }

    // ══════════════════════════════════════════════════════════════
    // Header
    // ══════════════════════════════════════════════════════════════
    Rectangle {
        id: headerBar
        objectName: "hubHeader"
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: Spacing.headerHeight
        color: MissionTheme.surface
        z: 2

        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 1
            color: MissionTheme.outline
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Spacing.paddingPage
            anchors.rightMargin: Spacing.paddingPage
            spacing: Spacing.gapMedium

            Rectangle {
                Layout.preferredWidth: 32; Layout.preferredHeight: 32
                Layout.alignment: Qt.AlignVCenter
                radius: Radii.radiusMd; color: MissionTheme.primary
                Rectangle {
                    anchors.centerIn: parent; width: 14; height: 14; radius: 7
                    color: "transparent"; border.width: 2; border.color: MissionTheme.contentOnPrimary
                }
                Accessible.role: Accessible.Graphic; Accessible.name: qsTr("Mission Hub logo")
            }

            Column {
                Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter; spacing: 0
                Label {
                    id: titleLabel; objectName: "hubTitle"
                    text: qsTr("Mission Hub")
                    font.pixelSize: Typography.title.size; font.weight: Typography.title.weight
                    color: MissionTheme.textPrimary; elide: Text.ElideRight
                    Accessible.role: Accessible.Heading; Accessible.name: text
                }
                Label {
                    text: qsTr("Version %1 · %2").arg(root.version).arg(root.buildType)
                    font.pixelSize: Typography.caption.size; color: MissionTheme.textSecondary
                }
            }

            Label {
                id: stateLabel; objectName: "hubState"
                text: root.screenState === "normal" ? "" :
                      root.screenState === "loading" ? qsTr("Loading…") :
                      root.screenState === "offline" ? qsTr("Offline") :
                      root.screenState === "error" ? qsTr("Error") : ""
                visible: text.length > 0
                font.pixelSize: Typography.bodySmall.size; color: MissionTheme.textSecondary
                Accessible.role: Accessible.StaticText; Accessible.name: text
            }
        }
    }

    // ══════════════════════════════════════════════════════════════
    // Sidebar navigation
    // ══════════════════════════════════════════════════════════════
    Rectangle {
        id: sidebar
        objectName: "hubSidebar"
        anchors { left: parent.left; top: headerBar.bottom; bottom: parent.bottom }
        width: root.sidebarExpanded ? Spacing.sidebarWidth : 56
        color: MissionTheme.surface; z: 1

        Rectangle {
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            width: 1; color: MissionTheme.outline
        }

        Behavior on width {
            enabled: !root.reducedMotion
            animation: NumberAnimation { duration: Motion.durationFast }
        }

        Column {
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Spacing.gapSmall }
            spacing: Spacing.gapTiny

            Repeater {
                id: navRepeater
                model: root.navigationItems

                delegate: Rectangle {
                    required property var modelData
                    required property int index

                    id: navItem
                    objectName: "navItem_" + modelData.id
                    width: parent.width; height: Spacing.minimumTouchTarget
                    radius: Radii.card
                    color: navItemMouse.containsMouse ? MissionTheme.surfaceVariant
                           : (modelData.id === root.selectedNavId ? MissionTheme.surfaceVariant : "transparent")
                    activeFocusOnTab: true

                    Behavior on color {
                        enabled: !root.reducedMotion
                        animation: ColorAnimation { duration: Motion.colorChange }
                    }

                    Rectangle {
                        anchors.fill: parent; anchors.margins: -2
                        radius: Radii.card + 2; color: "transparent"
                        border.color: MissionTheme.focusRing; border.width: 2
                        visible: navItem.activeFocus
                    }

                    MouseArea {
                        id: navItemMouse; anchors.fill: parent; hoverEnabled: true
                        onClicked: {
                            navItem.forceActiveFocus()
                            root.selectedNavId = modelData.id
                            root.navigationActivated(modelData.id)
                        }
                    }

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left; anchors.leftMargin: Spacing.paddingMedium
                        spacing: Spacing.gapSmall
                        Rectangle {
                            width: 3; height: navItem.height * 0.5; radius: 1.5
                            color: modelData.id === root.selectedNavId ? MissionTheme.primary : "transparent"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Label {
                            text: root.navLabel(modelData)
                            font.pixelSize: Typography.body.size
                            font.weight: modelData.id === root.selectedNavId ? Typography.weightSemibold : Typography.weightRegular
                            color: modelData.id === root.selectedNavId ? MissionTheme.textPrimary : MissionTheme.textSecondary
                            elide: Text.ElideRight; visible: root.sidebarExpanded
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Accessible.role: Accessible.Button
                    Accessible.name: root.navLabel(modelData)
                    Accessible.selected: modelData.id === root.selectedNavId

                    Keys.onUpPressed: root.focusNavItem(index - 1)
                    Keys.onDownPressed: root.focusNavItem(index + 1)
                    Keys.onReturnPressed: { root.selectedNavId = modelData.id; root.navigationActivated(modelData.id) }
                    Keys.onSpacePressed: { root.selectedNavId = modelData.id; root.navigationActivated(modelData.id) }
                }
            }
        }
    }

    // ══════════════════════════════════════════════════════════════
    // Main content area
    // ══════════════════════════════════════════════════════════════
    Flickable {
        id: mainContent
        objectName: "hubMainContent"
        anchors { left: sidebar.right; right: parent.right; top: headerBar.bottom; bottom: parent.bottom }
        clip: true; contentHeight: contentColumn.implicitHeight; interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar {}

        Column {
            id: contentColumn
            width: mainContent.width; spacing: Spacing.gapLarge

            // ── Loading state ──
            RowLayout {
                id: loadingIndicator; objectName: "hubLoading"
                visible: root.screenState === "loading"
                width: parent.width; spacing: Spacing.gapMedium
                Item { width: Spacing.paddingPage; height: 1 }
                Label { text: qsTr("Loading devices…"); font.pixelSize: Typography.bodySmall.size; color: MissionTheme.textSecondary }
                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: 4; radius: 2; color: MissionTheme.surfaceDim
                    Rectangle {
                        width: 96; height: 4; radius: 2; color: MissionTheme.primary; x: -96
                        NumberAnimation on x {
                            running: root.screenState === "loading" && !root.reducedMotion
                            from: -96; to: loadingIndicator.width
                            duration: Motion.durationSlow; loops: Animation.Infinite
                        }
                    }
                }
            }

            // ── Error state ──
            Rectangle {
                id: errorBanner; objectName: "hubError"
                visible: root.screenState === "error"
                width: parent.width - Spacing.paddingPage * 2; anchors.leftMargin: Spacing.paddingPage
                height: errorLayout.implicitHeight + Spacing.paddingMedium * 2
                radius: Radii.card; color: Colors.errorContainer
                RowLayout {
                    id: errorLayout; anchors.fill: parent; anchors.margins: Spacing.paddingMedium; spacing: Spacing.gapMedium
                    Rectangle { Layout.preferredWidth: 12; Layout.preferredHeight: 12; radius: 6; color: MissionTheme.error }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: Spacing.gapTiny
                        Label { text: qsTr("Could not load devices"); font.weight: Typography.weightSemibold; color: Colors.contentOnErrorContainer }
                        Label { text: qsTr("Device information could not be loaded. Check your system and try again."); font.pixelSize: Typography.bodySmall.size; color: Colors.contentOnErrorContainer; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    }
                }
            }

            // ── Offline state ──
            Rectangle {
                id: offlineBanner; objectName: "hubOffline"
                visible: root.screenState === "offline"
                width: parent.width - Spacing.paddingPage * 2; anchors.leftMargin: Spacing.paddingPage
                height: offlineLayout.implicitHeight + Spacing.paddingMedium * 2
                radius: Radii.card; color: MissionTheme.surfaceVariant
                RowLayout {
                    id: offlineLayout; anchors.fill: parent; anchors.margins: Spacing.paddingMedium; spacing: Spacing.gapMedium
                    Rectangle { Layout.preferredWidth: 12; Layout.preferredHeight: 12; radius: 6; color: MissionTheme.textSecondary }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: Spacing.gapTiny
                        Label { text: qsTr("You're offline"); font.weight: Typography.weightSemibold; color: MissionTheme.textPrimary }
                        Label { text: qsTr("Previously detected devices remain available. Refreshing the device list requires a system connection."); font.pixelSize: Typography.bodySmall.size; color: MissionTheme.textSecondary; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    }
                }
            }

            // ── Empty state ──
            Column {
                id: emptyHint; objectName: "hubEmpty"
                visible: root.screenState === "empty"
                width: parent.width; spacing: Spacing.gapSmall
                Label { width: parent.width; text: qsTr("No devices available"); font.pixelSize: Typography.body.size; font.weight: Typography.weightSemibold; color: MissionTheme.textPrimary; wrapMode: Text.WordWrap; Accessible.role: Accessible.StaticText; Accessible.name: text }
                Label { width: parent.width; text: qsTr("Connected devices will appear here once the host provides device data."); font.pixelSize: Typography.bodySmall.size; color: MissionTheme.textSecondary; wrapMode: Text.WordWrap; Accessible.role: Accessible.StaticText; Accessible.name: text }
            }

            // ══════════════════════════════════════════════════════
            // Normal content
            // ══════════════════════════════════════════════════════
            Column {
                visible: root.screenState === "normal"
                width: parent.width; spacing: Spacing.gapLarge

                // ── Screen title ──
                Label {
                    text: qsTr("Devices")
                    font.pixelSize: Typography.headline.size; font.weight: Typography.headline.weight
                    color: MissionTheme.textPrimary; anchors.leftMargin: Spacing.paddingPage
                    Accessible.role: Accessible.Heading; Accessible.name: text
                }

                // ── Overview card ──
                Rectangle {
                    width: parent.width - Spacing.paddingPage * 2; anchors.leftMargin: Spacing.paddingPage
                    height: overviewRow.implicitHeight + Spacing.paddingLarge * 2
                    radius: Radii.card; color: MissionTheme.surface
                    border.color: MissionTheme.outlineVariant; border.width: 1
                    RowLayout {
                        id: overviewRow; anchors { left: parent.left; right: parent.right; top: parent.top; margins: Spacing.paddingLarge }; spacing: Spacing.gapLarge
                        Column { spacing: Spacing.gapTiny
                            Label { text: qsTr("Connected"); font.pixelSize: Typography.caption.size; color: MissionTheme.textSecondary }
                            Label { text: String(root.connectedCount); font.pixelSize: Typography.body.size; font.weight: Typography.weightSemibold; color: MissionTheme.textPrimary }
                        }
                        Column { spacing: Spacing.gapTiny
                            Label { text: qsTr("Disabled"); font.pixelSize: Typography.caption.size; color: MissionTheme.textSecondary }
                            Label { text: String(root.disabledCount); font.pixelSize: Typography.body.size; font.weight: Typography.weightSemibold; color: MissionTheme.textPrimary }
                        }
                        Column { spacing: Spacing.gapTiny
                            Label { text: qsTr("Total"); font.pixelSize: Typography.caption.size; color: MissionTheme.textSecondary }
                            Label { text: String(root.deviceCount); font.pixelSize: Typography.body.size; font.weight: Typography.weightSemibold; color: MissionTheme.textPrimary }
                        }
                        Item { Layout.fillWidth: true }
                        MissionButton {
                            id: refreshButton; objectName: "refreshDevices"
                            variant: MissionButton.Variant.Secondary; compact: true
                            text: qsTr("Refresh")
                            onClicked: root.refreshDevices()
                        }
                    }
                }

                // ── Device list ──
                Column { width: parent.width; spacing: Spacing.gapMedium
                    Label { text: qsTr("Devices"); font.pixelSize: Typography.subtitle.size; font.weight: Typography.subtitle.weight; color: MissionTheme.textPrimary; anchors.leftMargin: Spacing.paddingPage; Accessible.role: Accessible.Heading; Accessible.name: text }

                    Column {
                        visible: root.deviceCount === 0
                        width: parent.width; spacing: Spacing.gapSmall
                        Label { width: parent.width; text: qsTr("No devices detected"); font.pixelSize: Typography.body.size; font.weight: Typography.weightSemibold; color: MissionTheme.textPrimary; anchors.leftMargin: Spacing.paddingPage }
                        Label { width: parent.width; text: qsTr("Devices connected to this system will appear here."); font.pixelSize: Typography.bodySmall.size; color: MissionTheme.textSecondary; anchors.leftMargin: Spacing.paddingPage }
                    }

                    Repeater {
                        id: deviceRepeater
                        model: root.devices

                        delegate: Rectangle {
                            required property var modelData

                            id: devRow
                            objectName: "dev_" + modelData.id
                            width: parent.width - Spacing.paddingPage * 2; anchors.leftMargin: Spacing.paddingPage
                            height: Math.max(Spacing.minimumTouchTarget, devContent.implicitHeight + Spacing.paddingMedium * 2)
                            radius: Radii.card
                            color: MissionTheme.surface
                            border.color: MissionTheme.outlineVariant; border.width: 1

                            RowLayout {
                                id: devContent
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: Spacing.paddingMedium }
                                spacing: Spacing.gapMedium

                                Rectangle {
                                    Layout.preferredWidth: 8; Layout.preferredHeight: 8; radius: 4
                                    color: root.deviceStatusColor(modelData.status)
                                }

                                Column {
                                    Layout.fillWidth: true; spacing: Spacing.gapTiny
                                    RowLayout { spacing: Spacing.gapSmall; width: parent.width
                                        Label {
                                            Layout.fillWidth: true
                                            text: modelData.name !== undefined && String(modelData.name).length > 0 ? String(modelData.name) : String(modelData.id)
                                            font.pixelSize: Typography.body.size; font.weight: Typography.weightSemibold
                                            color: MissionTheme.textPrimary; elide: Text.ElideRight
                                        }
                                        Label {
                                            text: root.deviceTypeLabel(modelData.type)
                                            font.pixelSize: Typography.bodySmall.size; color: MissionTheme.textSecondary
                                        }
                                    }
                                    Label {
                                        visible: modelData.description !== undefined && String(modelData.description).length > 0
                                        text: modelData.description !== undefined ? String(modelData.description) : ""
                                        font.pixelSize: Typography.bodySmall.size; color: MissionTheme.textSecondary
                                        wrapMode: Text.Wrap; width: parent.width
                                    }
                                    Label {
                                        visible: modelData.details !== undefined && String(modelData.details).length > 0
                                        text: modelData.details !== undefined ? String(modelData.details) : ""
                                        font.pixelSize: Typography.bodySmall.size; color: MissionTheme.textTertiary
                                        wrapMode: Text.Wrap; width: parent.width
                                    }
                                }

                                Rectangle {
                                    Layout.preferredWidth: statusLbl.implicitWidth + Spacing.paddingMedium * 2
                                    Layout.preferredHeight: Spacing.gapMedium; radius: Radii.chip
                                    color: MissionTheme.surfaceVariant
                                    Label {
                                        id: statusLbl; anchors.centerIn: parent
                                        text: root.deviceStatusLabel(modelData.status)
                                        font.pixelSize: Typography.caption.size
                                        color: root.deviceStatusColor(modelData.status)
                                    }
                                }

                                Column {
                                    Layout.alignment: Qt.AlignVCenter; spacing: Spacing.gapTiny
                                    MissionButton {
                                        objectName: "devIdentify_" + modelData.id
                                        variant: MissionButton.Variant.Secondary; compact: true
                                        text: qsTr("Identify")
                                        onClicked: root.identifyDevice(String(modelData.id))
                                    }
                                    MissionButton {
                                        objectName: "devTroubleshoot_" + modelData.id
                                        variant: MissionButton.Variant.Secondary; compact: true
                                        text: qsTr("Troubleshoot")
                                        onClicked: root.troubleshootDevice(String(modelData.id))
                                    }
                                }

                                MissionButton {
                                    objectName: "devDisable_" + modelData.id
                                    visible: root.disableSupported(modelData.disableSupported)
                                    Layout.alignment: Qt.AlignVCenter
                                    variant: MissionButton.Variant.Secondary; compact: true
                                    text: qsTr("Disable")
                                    onClicked: root.disableDevice(String(modelData.id))
                                }
                            }

                            Accessible.role: Accessible.StaticText
                            Accessible.name: qsTr("%1 — %2, %3").arg(
                                modelData.name !== undefined && String(modelData.name).length > 0 ? modelData.name : modelData.id
                            ).arg(root.deviceTypeLabel(modelData.type)).arg(root.deviceStatusLabel(modelData.status))
                        }
                    }
                }

                // ── Bottom spacer ──
                Item { width: 1; height: Spacing.paddingLarge }
            }
        }
    }
}
