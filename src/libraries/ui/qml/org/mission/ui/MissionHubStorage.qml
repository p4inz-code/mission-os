// Mission OS — Mission Hub Storage (MOS-HUB-010)
//
// Tenth screen of the Mission Hub family. Implements the source-defined
// Storage structure (docs/design/03_SCREEN_REGISTRY.md MOS-HUB-010
// "Storage", docs/reference/03_MISSION_HUB.md §2 Storage Manager,
// docs/design/01_INFORMATION_ARCHITECTURE.md §5 Mission Hub Structure,
// docs/reference/08_DIAGNOSTICS.md §9 Storage Diagnostics):
//
//   Hosting: a full-screen application within Mission Hub. Place inside
//   MissionWindow content and anchor to fill, e.g.
//   MissionWindow { MissionHubStorage { anchors.fill: parent } }
//   The component sizes to its implicit 1280x720 like Desktop.qml.
//
//   Layout (Master UX Specification §3):
//     Header → Sidebar Navigation → Main Content Area
//
//   Storage Manager (reference §2):
//     Displays: drives, partitions, health, available space, filesystem,
//     encryption status.
//     Warnings include: low storage, failing drive, filesystem issues.
//
//   Storage Diagnostics (reference 08_DIAGNOSTICS.md §9):
//     Checks: SMART, temperature, health percentage, bad sectors,
//     filesystem, free space, read/write errors.
//
// Interpretation notes (documented — no authoritative source specifies
// further detail):
//   - The volume model is host-driven: each entry is
//     { id, name, mountPoint?, filesystem?, capacity?, used?, free?,
//       usagePercent?, encryption?, health? }.
//     health ∈ "ok" | "warning" | "critical" (the three storage
//     warnings in reference §2: low storage, failing drive, filesystem
//     issues). Missing health renders as "Unknown" (defensive).
//     capacity/used/free are display strings supplied by the host; no
//     numeric bytes API is defined anywhere, so none is invented.
//     usagePercent (0–100, optional) drives the visual usage bar only;
//     the bar is hidden when the host does not provide a number.
//   - The Storage Manager documents display only — no cleanup,
//     mount, partition or management operations exist in the
//     authoritative sources, so the screen exposes no such actions and
//     performs no filesystem inspection.
//   - The screen never mutates the model.
//   - Escape is deliberately unmapped.
//   - Offline state shows a neutral message — Mission Hub works fully
//     offline; locally known storage information remains visible.
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

    /// Storage overview:
    /// { totalCapacity (string|null), used (string|null),
    ///   free (string|null), usagePercent (number|null) }
    property var storageOverview: ({})

    /// Storage volumes: [{ id, name, mountPoint?, filesystem?,
    ///                     capacity?, used?, free?, usagePercent?,
    ///                     encryption?, health? }]
    /// health ∈ "ok" | "warning" | "critical"
    property var volumes: []

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
    property string selectedNavId: "storage"

    // ── Signals (host wiring) ──────────────────────────────────────
    /// User activated a navigation item (host opens the screen)
    signal navigationActivated(string navId)

    // Escape is deliberately unmapped: the host owns window-level dismissal.
    // The Storage Manager section (reference §2) documents display only:
    // no cleanup/mount/partition/management actions are exposed and no
    // privileged operations are performed from QML.

    // ── Derived helpers ────────────────────────────────────────────
    /// Total number of volumes
    readonly property int volumeCount: root.volumes.length

    /// Number of healthy volumes
    readonly property int okCount: {
        var c = 0
        for (var i = 0; i < root.volumes.length; i++) {
            if (String(root.volumes[i].health) === "ok") c++
        }
        return c
    }

    /// Number of volumes with warnings
    readonly property int warningCount: {
        var c = 0
        for (var i = 0; i < root.volumes.length; i++) {
            if (String(root.volumes[i].health) === "warning") c++
        }
        return c
    }

    /// Number of volumes with critical health
    readonly property int criticalCount: {
        var c = 0
        for (var i = 0; i < root.volumes.length; i++) {
            if (String(root.volumes[i].health) === "critical") c++
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

    /// Storage health → display label
    function healthLabel(health) {
        switch (String(health)) {
        case "ok":       return qsTr("OK")
        case "warning":  return qsTr("Warning")
        case "critical": return qsTr("Critical")
        default:         return qsTr("Unknown")
        }
    }

    /// Storage health → token color
    function healthColor(health) {
        switch (String(health)) {
        case "ok":       return MissionTheme.success
        case "warning":  return MissionTheme.warning
        case "critical": return MissionTheme.error
        default:         return MissionTheme.textSecondary
        }
    }

    /// Normalize a host-supplied usage percentage for the visual bar.
    /// Returns -1 when the value is not a finite number (bar hidden).
    function validPercent(value) {
        if (typeof value !== "number" || !isFinite(value)) return -1
        return Math.max(0, Math.min(100, value))
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
    property alias volumeRepeater: volumeRepeater
    property alias overviewCard: overviewCard
    property alias overviewUsageBar: overviewUsageBar
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
                Label { text: qsTr("Loading storage information…"); font.pixelSize: Typography.bodySmall.size; color: MissionTheme.textSecondary }
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
                        Label { text: qsTr("Could not load storage information"); font.weight: Typography.weightSemibold; color: Colors.contentOnErrorContainer }
                        Label { text: qsTr("Storage information could not be loaded. Check your system and try again."); font.pixelSize: Typography.bodySmall.size; color: Colors.contentOnErrorContainer; wrapMode: Text.Wrap; Layout.fillWidth: true }
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
                        Label { text: qsTr("Local storage information remains available. Live updates require a system connection."); font.pixelSize: Typography.bodySmall.size; color: MissionTheme.textSecondary; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    }
                }
            }

            // ── Empty state ──
            Column {
                id: emptyHint; objectName: "hubEmpty"
                visible: root.screenState === "empty"
                width: parent.width; spacing: Spacing.gapSmall
                Label { width: parent.width; text: qsTr("No storage information available"); font.pixelSize: Typography.body.size; font.weight: Typography.weightSemibold; color: MissionTheme.textPrimary; wrapMode: Text.WordWrap; Accessible.role: Accessible.StaticText; Accessible.name: text }
                Label { width: parent.width; text: qsTr("Storage details will appear here once the host provides data."); font.pixelSize: Typography.bodySmall.size; color: MissionTheme.textSecondary; wrapMode: Text.WordWrap; Accessible.role: Accessible.StaticText; Accessible.name: text }
            }

            // ══════════════════════════════════════════════════════
            // Normal content
            // ══════════════════════════════════════════════════════
            Column {
                visible: root.screenState === "normal"
                width: parent.width; spacing: Spacing.gapLarge

                // ── Screen title ──
                Label {
                    text: qsTr("Storage")
                    font.pixelSize: Typography.headline.size; font.weight: Typography.headline.weight
                    color: MissionTheme.textPrimary; anchors.leftMargin: Spacing.paddingPage
                    Accessible.role: Accessible.Heading; Accessible.name: text
                }

                // ── Overview card ──
                Rectangle {
                    id: overviewCard
                    width: parent.width - Spacing.paddingPage * 2; anchors.leftMargin: Spacing.paddingPage
                    height: overviewContent.implicitHeight + Spacing.paddingLarge * 2
                    radius: Radii.card; color: MissionTheme.surface
                    border.color: MissionTheme.outlineVariant; border.width: 1

                    Column {
                        id: overviewContent
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: Spacing.paddingLarge }
                        spacing: Spacing.gapMedium

                        RowLayout { spacing: Spacing.gapLarge
                            Column { spacing: Spacing.gapTiny
                                Label { text: qsTr("Total Capacity"); font.pixelSize: Typography.caption.size; color: MissionTheme.textSecondary }
                                Label { text: root.storageOverview.totalCapacity !== undefined && String(root.storageOverview.totalCapacity).length > 0 ? String(root.storageOverview.totalCapacity) : qsTr("—"); font.pixelSize: Typography.body.size; font.weight: Typography.weightSemibold; color: MissionTheme.textPrimary }
                            }
                            Column { spacing: Spacing.gapTiny
                                Label { text: qsTr("Used"); font.pixelSize: Typography.caption.size; color: MissionTheme.textSecondary }
                                Label { text: root.storageOverview.used !== undefined && String(root.storageOverview.used).length > 0 ? String(root.storageOverview.used) : qsTr("—"); font.pixelSize: Typography.body.size; font.weight: Typography.weightSemibold; color: MissionTheme.textPrimary }
                            }
                            Column { spacing: Spacing.gapTiny
                                Label { text: qsTr("Free"); font.pixelSize: Typography.caption.size; color: MissionTheme.textSecondary }
                                Label { text: root.storageOverview.free !== undefined && String(root.storageOverview.free).length > 0 ? String(root.storageOverview.free) : qsTr("—"); font.pixelSize: Typography.body.size; font.weight: Typography.weightSemibold; color: MissionTheme.textPrimary }
                            }
                            Item { Layout.fillWidth: true }
                        }

                        RowLayout {
                            id: overviewUsageBar; objectName: "overviewUsageBar"
                            visible: root.validPercent(root.storageOverview.usagePercent) >= 0
                            spacing: Spacing.gapMedium
                            Rectangle {
                                Layout.fillWidth: true; Layout.preferredHeight: 8; radius: 4
                                color: MissionTheme.surfaceDim
                                Rectangle {
                                    width: parent.width * (root.validPercent(root.storageOverview.usagePercent) / 100)
                                    height: 8; radius: 4
                                    color: MissionTheme.primary
                                }
                            }
                            Label {
                                text: qsTr("%1% used").arg(Math.round(root.validPercent(root.storageOverview.usagePercent)))
                                font.pixelSize: Typography.caption.size; color: MissionTheme.textSecondary
                            }
                        }
                    }
                }

                // ── Health badges ──
                Row { spacing: Spacing.gapMedium; anchors.leftMargin: Spacing.paddingPage
                    Rectangle { width: badge1.implicitWidth + Spacing.paddingMedium * 2; height: Spacing.minimumTouchTarget; radius: Radii.chip; color: MissionTheme.success; Label { id: badge1; anchors.centerIn: parent; text: qsTr("%1 OK").arg(root.okCount); font.pixelSize: Typography.bodySmall.size; font.weight: Typography.weightSemibold; color: "white" } }
                    Rectangle { visible: root.warningCount > 0; width: badge2.implicitWidth + Spacing.paddingMedium * 2; height: Spacing.minimumTouchTarget; radius: Radii.chip; color: MissionTheme.warning; Label { id: badge2; anchors.centerIn: parent; text: qsTr("%1 Warning").arg(root.warningCount); font.pixelSize: Typography.bodySmall.size; font.weight: Typography.weightSemibold; color: "white" } }
                    Rectangle { visible: root.criticalCount > 0; width: badge3.implicitWidth + Spacing.paddingMedium * 2; height: Spacing.minimumTouchTarget; radius: Radii.chip; color: MissionTheme.error; Label { id: badge3; anchors.centerIn: parent; text: qsTr("%1 Critical").arg(root.criticalCount); font.pixelSize: Typography.bodySmall.size; font.weight: Typography.weightSemibold; color: "white" } }
                }

                // ── Volumes list ──
                Column { width: parent.width; spacing: Spacing.gapMedium
                    Label { text: qsTr("Volumes"); font.pixelSize: Typography.subtitle.size; font.weight: Typography.subtitle.weight; color: MissionTheme.textPrimary; anchors.leftMargin: Spacing.paddingPage; Accessible.role: Accessible.Heading; Accessible.name: text }

                    Column {
                        visible: root.volumeCount === 0
                        width: parent.width; spacing: Spacing.gapSmall
                        Label { width: parent.width; text: qsTr("No storage volumes available"); font.pixelSize: Typography.body.size; font.weight: Typography.weightSemibold; color: MissionTheme.textPrimary; anchors.leftMargin: Spacing.paddingPage }
                        Label { width: parent.width; text: qsTr("Drives and partitions will appear here once the host provides storage data."); font.pixelSize: Typography.bodySmall.size; color: MissionTheme.textSecondary; anchors.leftMargin: Spacing.paddingPage }
                    }

                    Repeater {
                        id: volumeRepeater
                        model: root.volumes

                        delegate: Rectangle {
                            required property var modelData

                            id: volRow
                            objectName: "vol_" + modelData.id
                            width: parent.width - Spacing.paddingPage * 2; anchors.leftMargin: Spacing.paddingPage
                            height: volContent.implicitHeight + Spacing.paddingMedium * 2
                            radius: Radii.card
                            color: MissionTheme.surface
                            border.color: MissionTheme.outlineVariant; border.width: 1

                            Column {
                                id: volContent
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: Spacing.paddingMedium }
                                spacing: Spacing.gapSmall

                                RowLayout { spacing: Spacing.gapMedium
                                    Rectangle { Layout.preferredWidth: 8; Layout.preferredHeight: 8; radius: 4; color: root.healthColor(modelData.health) }
                                    Column { Layout.fillWidth: true; spacing: Spacing.gapTiny
                                        Label {
                                            width: parent.width
                                            text: modelData.name !== undefined && String(modelData.name).length > 0 ? String(modelData.name) : String(modelData.id)
                                            font.pixelSize: Typography.body.size; font.weight: Typography.weightSemibold
                                            color: MissionTheme.textPrimary; elide: Text.ElideRight
                                        }
                                        Label {
                                            visible: (modelData.mountPoint !== undefined && String(modelData.mountPoint).length > 0)
                                            text: modelData.mountPoint !== undefined ? String(modelData.mountPoint) : ""
                                            font.pixelSize: Typography.bodySmall.size; color: MissionTheme.textSecondary
                                            wrapMode: Text.Wrap; width: parent.width
                                        }
                                        Label {
                                            visible: (modelData.filesystem !== undefined && String(modelData.filesystem).length > 0)
                                                || (modelData.encryption !== undefined && String(modelData.encryption).length > 0)
                                            text: {
                                                var parts = []
                                                if (modelData.filesystem !== undefined && String(modelData.filesystem).length > 0) parts.push(qsTr("Filesystem: %1").arg(modelData.filesystem))
                                                if (modelData.encryption !== undefined && String(modelData.encryption).length > 0) parts.push(qsTr("Encryption: %1").arg(modelData.encryption))
                                                return parts.join("  ·  ")
                                            }
                                            font.pixelSize: Typography.bodySmall.size; color: MissionTheme.textTertiary
                                            wrapMode: Text.Wrap; width: parent.width
                                        }
                                    }
                                    Column { Layout.alignment: Qt.AlignVCenter; spacing: Spacing.gapTiny
                                        Label {
                                            objectName: "volUsage_" + modelData.id
                                            text: {
                                                var p = root.validPercent(modelData.usagePercent)
                                                if (p >= 0) return qsTr("%1% used").arg(Math.round(p))
                                                if (modelData.used !== undefined && String(modelData.used).length > 0) return String(modelData.used)
                                                return qsTr("—")
                                            }
                                            font.pixelSize: Typography.body.size; font.weight: Typography.weightSemibold
                                            color: root.healthColor(modelData.health)
                                            horizontalAlignment: Text.AlignRight
                                        }
                                        Label {
                                            objectName: "volCapacity_" + modelData.id
                                            visible: (modelData.capacity !== undefined && String(modelData.capacity).length > 0)
                                                || (modelData.free !== undefined && String(modelData.free).length > 0)
                                            text: {
                                                var parts = []
                                                if (modelData.capacity !== undefined && String(modelData.capacity).length > 0) parts.push(String(modelData.capacity))
                                                if (modelData.free !== undefined && String(modelData.free).length > 0) parts.push(qsTr("%1 free").arg(modelData.free))
                                                return parts.join(" · ")
                                            }
                                            font.pixelSize: Typography.caption.size; color: MissionTheme.textSecondary
                                            horizontalAlignment: Text.AlignRight
                                        }
                                    }
                                }

                                RowLayout {
                                    objectName: "usageBar_" + modelData.id
                                    visible: root.validPercent(modelData.usagePercent) >= 0
                                    spacing: Spacing.gapMedium
                                    Rectangle {
                                        Layout.fillWidth: true; Layout.preferredHeight: 8; radius: 4
                                        color: MissionTheme.surfaceDim
                                        Rectangle {
                                            width: parent.width * (root.validPercent(modelData.usagePercent) / 100)
                                            height: 8; radius: 4
                                            color: root.healthColor(modelData.health)
                                        }
                                    }
                                    Label {
                                        text: qsTr("%1% used").arg(Math.round(root.validPercent(modelData.usagePercent)))
                                        font.pixelSize: Typography.caption.size; color: MissionTheme.textSecondary
                                    }
                                }
                            }

                            Accessible.role: Accessible.StaticText
                            Accessible.name: {
                                var n = modelData.name !== undefined && String(modelData.name).length > 0 ? modelData.name : modelData.id
                                var parts = [qsTr("%1 — %2").arg(n).arg(root.healthLabel(modelData.health))]
                                if (modelData.filesystem !== undefined && String(modelData.filesystem).length > 0)
                                    parts.push(String(modelData.filesystem))
                                if (modelData.encryption !== undefined && String(modelData.encryption).length > 0)
                                    parts.push(String(modelData.encryption))
                                if (modelData.capacity !== undefined && String(modelData.capacity).length > 0)
                                    parts.push(String(modelData.capacity))
                                return parts.join(", ")
                            }
                        }
                    }
                }

                // ── Bottom spacer ──
                Item { width: 1; height: Spacing.paddingLarge }
            }
        }
    }
}
