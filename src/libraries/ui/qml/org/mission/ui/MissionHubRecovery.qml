// Mission OS — Mission Hub Recovery (MOS-HUB-007)
//
// Seventh screen of the Mission Hub family. Implements the source-defined
// Recovery structure (docs/design/03_SCREEN_REGISTRY.md MOS-HUB-007
// "Recovery", docs/reference/03_MISSION_HUB.md §4 Recovery Center
// Integration, Backup Overview, §2 Recovery Summary,
// docs/design/01_INFORMATION_ARCHITECTURE.md §5 Mission Hub Structure,
// §9 Recovery Structure, docs/design/04_USER_FLOWS.md §10 Recovery):
//
//   Hosting: a full-screen application within Mission Hub. Place inside
//   MissionWindow content and anchor to fill, e.g.
//   MissionWindow { MissionHubRecovery { anchors.fill: parent } }
//   The component sizes to its implicit 1280x720 like Desktop.qml.
//
//   Layout (Master UX Specification §3):
//     Header → Sidebar Navigation → Main Content Area
//
//   Recovery Center Integration (reference §4):
//     Direct access to: Recovery Partition, Recovery USB, Restore Points,
//     Factory Reset, System Repair, Boot Repair.
//     "Users should never need terminal commands for common recovery tasks."
//
//   Backup Overview (reference §4):
//     Displays: latest backup, backup destination, backup size,
//     encryption status, scheduled backups. Users may: create backup,
//     verify backup, restore backup, delete backup.
//
//   Recovery Summary (reference §2):
//     Displays: recovery partition status, recovery USB status,
//     latest backup, restore point availability.
//     "Users should immediately know whether recovery is possible."
//
//   User Flow §10 (Recovery):
//     Mission Hub → Recovery → Select Recovery Option → Confirmation →
//     Execute → Report
//
//   Recovery Structure (information architecture §9):
//     Startup Repair, Boot Repair, Restore Points, Recovery USB,
//     Backup Restore, Factory Reset, Recovery Reports, Advanced Recovery
//
// Interpretation notes (documented — no authoritative source specifies
// further detail):
//   - Recovery status is host-driven: { recoveryPartition (bool|null),
//     recoveryUsb (bool|null), latestBackup (string|null),
//     backupDestination (string|null), backupSize (string|null),
//     backupEncrypted (bool|null), restorePointsAvailable (bool|null),
//     scheduledBackups (number|null) }.
//   - Recovery options are host-driven: each entry is
//     { id, name, description?, destructive?, available? }.
//     destructive ∈ boolean. The screen never mutates the model.
//   - All recovery actions emit host-facing signals rather than
//     performing privileged/backend operations inside QML.
//   - Destructive actions present a clear warning before signaling.
//   - Escape is deliberately unmapped.
//   - Offline state shows a neutral message.
//
// Design-system compliance:
//   - Tokens only (Colors, Typography, Spacing, Radii, Motion, MissionTheme)
//   - Light + dark themes via MissionTheme
//   - Keyboard navigation with visible focus states; 44px minimum touch targets
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
    property string screenState: "normal"
    property string version: "0.1.0"
    property string buildType: "Nightly"
    property bool reducedMotion: false

    /// Recovery status: { recoveryPartition, recoveryUsb, latestBackup,
    ///   backupDestination, backupSize, backupEncrypted,
    ///   restorePointsAvailable, scheduledBackups }
    /// All fields optional; missing data handled defensively.
    property var recoveryStatus: ({})

    /// Recovery options: [{ id, name, description?, destructive?, available? }]
    property var recoveryOptions: []

    /// Navigation items
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

    property string selectedNavId: "recovery"

    // ── Signals ────────────────────────────────────────────────────
    /// User activated a recovery option (host opens confirmation/execution)
    signal optionActivated(string optionId)
    /// User requested a backup
    signal backupRequested()
    /// User activated a navigation item
    signal navigationActivated(string navId)

    // ── Derived helpers ────────────────────────────────────────────
    readonly property int optionCount: root.recoveryOptions.length
    readonly property int navCount: root.navigationItems.length
    readonly property bool sidebarExpanded: root.width >= 768

    function navLabel(item) {
        if (item === null || item === undefined) return ""
        var l = item.label !== undefined ? String(item.label) : ""
        return l.length > 0 ? l : String(item.id)
    }

    function statusLabel(value) {
        if (value === true) return qsTr("Available")
        if (value === false) return qsTr("Unavailable")
        return qsTr("Unknown")
    }

    function statusColor(value) {
        if (value === true) return MissionTheme.success
        if (value === false) return MissionTheme.error
        return MissionTheme.textSecondary
    }

    function focusNavItem(index) {
        if (root.navigationItems.length === 0) return
        var count = root.navigationItems.length
        var target = ((index % count) + count) % count
        var item = navRepeater.itemAt(target)
        if (item !== null) item.forceActiveFocus()
    }

    function focusOption(index) {
        if (root.recoveryOptions.length === 0) return
        var count = root.recoveryOptions.length
        var target = ((index % count) + count) % count
        var item = optionRepeater.itemAt(target)
        if (item !== null) item.forceActiveFocus()
    }

    // ── Test hooks ──
    property alias headerBar: headerBar
    property alias titleLabel: titleLabel
    property alias sidebar: sidebar
    property alias navRepeater: navRepeater
    property alias mainContent: mainContent
    property alias optionRepeater: optionRepeater
    property alias loadingIndicator: loadingIndicator
    property alias errorBanner: errorBanner
    property alias offlineBanner: offlineBanner
    property alias emptyHint: emptyHint

    // ══════════════════════════════════════════════════════════════
    // Background
    // ══════════════════════════════════════════════════════════════
    Rectangle { anchors.fill: parent; color: MissionTheme.background }

    // ══════════════════════════════════════════════════════════════
    // Header
    // ══════════════════════════════════════════════════════════════
    Rectangle {
        id: headerBar; objectName: "hubHeader"
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: Spacing.headerHeight; color: MissionTheme.surface; z: 2
        Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 1; color: MissionTheme.outline }
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: Spacing.paddingPage; anchors.rightMargin: Spacing.paddingPage; spacing: Spacing.gapMedium
            Rectangle {
                Layout.preferredWidth: 32; Layout.preferredHeight: 32; Layout.alignment: Qt.AlignVCenter
                radius: Radii.radiusMd; color: MissionTheme.primary
                Rectangle { anchors.centerIn: parent; width: 14; height: 14; radius: 7; color: "transparent"; border.width: 2; border.color: MissionTheme.contentOnPrimary }
                Accessible.role: Accessible.Graphic; Accessible.name: qsTr("Mission Hub logo")
            }
            Column {
                Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter; spacing: 0
                Label { id: titleLabel; objectName: "hubTitle"; text: qsTr("Mission Hub"); font.pixelSize: Typography.title.size; font.weight: Typography.title.weight; color: MissionTheme.textPrimary; elide: Text.ElideRight; Accessible.role: Accessible.Heading; Accessible.name: text }
                Label { text: qsTr("Version %1 · %2").arg(root.version).arg(root.buildType); font.pixelSize: Typography.caption.size; color: MissionTheme.textSecondary }
            }
            Label {
                id: stateLabel; objectName: "hubState"
                text: root.screenState === "normal" ? "" : root.screenState === "loading" ? qsTr("Loading…") : root.screenState === "offline" ? qsTr("Offline") : root.screenState === "error" ? qsTr("Error") : ""
                visible: text.length > 0; font.pixelSize: Typography.bodySmall.size; color: MissionTheme.textSecondary
                Accessible.role: Accessible.StaticText; Accessible.name: text
            }
        }
    }

    // ══════════════════════════════════════════════════════════════
    // Sidebar
    // ══════════════════════════════════════════════════════════════
    Rectangle {
        id: sidebar; objectName: "hubSidebar"
        anchors { left: parent.left; top: headerBar.bottom; bottom: parent.bottom }
        width: root.sidebarExpanded ? Spacing.sidebarWidth : 56; color: MissionTheme.surface; z: 1
        Rectangle { anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
        width: 1; color: MissionTheme.outline }
        Behavior on width { enabled: !root.reducedMotion; animation: NumberAnimation { duration: Motion.durationFast } }
        Column {
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Spacing.gapSmall }
            spacing: Spacing.gapTiny
            Repeater {
                id: navRepeater; model: root.navigationItems
                delegate: Rectangle {
                    required property var modelData; required property int index
                    id: navItem; objectName: "navItem_" + modelData.id
                    width: parent.width; height: Spacing.minimumTouchTarget; radius: Radii.card
                    color: navItemMouse.containsMouse ? MissionTheme.surfaceVariant : (modelData.id === root.selectedNavId ? MissionTheme.surfaceVariant : "transparent")
                    activeFocusOnTab: true
                    Behavior on color { enabled: !root.reducedMotion; animation: ColorAnimation { duration: Motion.colorChange } }
                    Rectangle { anchors.fill: parent; anchors.margins: -2; radius: Radii.card + 2; color: "transparent"; border.color: MissionTheme.focusRing; border.width: 2; visible: navItem.activeFocus }
                    MouseArea { id: navItemMouse; anchors.fill: parent; hoverEnabled: true; onClicked: { navItem.forceActiveFocus(); root.selectedNavId = modelData.id; root.navigationActivated(modelData.id) } }
                    Row {
                        anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: Spacing.paddingMedium; spacing: Spacing.gapSmall
                        Rectangle { width: 3; height: navItem.height * 0.5; radius: 1.5; color: modelData.id === root.selectedNavId ? MissionTheme.primary : "transparent"; anchors.verticalCenter: parent.verticalCenter }
                        Label { text: root.navLabel(modelData); font.pixelSize: Typography.body.size; font.weight: modelData.id === root.selectedNavId ? Typography.weightSemibold : Typography.weightRegular; color: modelData.id === root.selectedNavId ? MissionTheme.textPrimary : MissionTheme.textSecondary; elide: Text.ElideRight; visible: root.sidebarExpanded; anchors.verticalCenter: parent.verticalCenter }
                    }
                    Accessible.role: Accessible.Button; Accessible.name: root.navLabel(modelData); Accessible.selected: modelData.id === root.selectedNavId
                    Keys.onUpPressed: root.focusNavItem(index - 1); Keys.onDownPressed: root.focusNavItem(index + 1)
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
        id: mainContent; objectName: "hubMainContent"
        anchors { left: sidebar.right; right: parent.right; top: headerBar.bottom; bottom: parent.bottom }
        clip: true; contentHeight: contentColumn.implicitHeight; interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar {}

        Column { id: contentColumn; width: mainContent.width; spacing: Spacing.gapLarge

            // Loading
            RowLayout { id: loadingIndicator; objectName: "hubLoading"; visible: root.screenState === "loading"; width: parent.width; spacing: Spacing.gapMedium; Item { width: Spacing.paddingPage; height: 1 }
            Label { text: qsTr("Loading recovery information…"); font.pixelSize: Typography.bodySmall.size; color: MissionTheme.textSecondary }
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 4; radius: 2; color: MissionTheme.surfaceDim; Rectangle { width: 96; height: 4; radius: 2; color: MissionTheme.primary; x: -96; NumberAnimation on x { running: root.screenState === "loading" && !root.reducedMotion; from: -96; to: loadingIndicator.width; duration: Motion.durationSlow; loops: Animation.Infinite } } } }

            // Error
            Rectangle { id: errorBanner; objectName: "hubError"; visible: root.screenState === "error"; width: parent.width - Spacing.paddingPage * 2; anchors.leftMargin: Spacing.paddingPage; height: errorLayout.implicitHeight + Spacing.paddingMedium * 2; radius: Radii.card; color: Colors.errorContainer; RowLayout { id: errorLayout; anchors.fill: parent; anchors.margins: Spacing.paddingMedium; spacing: Spacing.gapMedium; Rectangle { Layout.preferredWidth: 12; Layout.preferredHeight: 12; radius: 6; color: MissionTheme.error }
            ColumnLayout { Layout.fillWidth: true; spacing: Spacing.gapTiny; Label { text: qsTr("Could not load recovery information"); font.weight: Typography.weightSemibold; color: Colors.contentOnErrorContainer }
            Label { text: qsTr("Recovery status could not be loaded. Check your system and try again."); font.pixelSize: Typography.bodySmall.size; color: Colors.contentOnErrorContainer; wrapMode: Text.Wrap; Layout.fillWidth: true } } } }

            // Offline
            Rectangle { id: offlineBanner; objectName: "hubOffline"; visible: root.screenState === "offline"; width: parent.width - Spacing.paddingPage * 2; anchors.leftMargin: Spacing.paddingPage; height: offlineLayout.implicitHeight + Spacing.paddingMedium * 2; radius: Radii.card; color: MissionTheme.surfaceVariant; RowLayout { id: offlineLayout; anchors.fill: parent; anchors.margins: Spacing.paddingMedium; spacing: Spacing.gapMedium; Rectangle { Layout.preferredWidth: 12; Layout.preferredHeight: 12; radius: 6; color: MissionTheme.textSecondary }
            ColumnLayout { Layout.fillWidth: true; spacing: Spacing.gapTiny; Label { text: qsTr("You're offline"); font.weight: Typography.weightSemibold; color: MissionTheme.textPrimary }
            Label { text: qsTr("Local recovery status is still available. Some features may require an internet connection."); font.pixelSize: Typography.bodySmall.size; color: MissionTheme.textSecondary; wrapMode: Text.Wrap; Layout.fillWidth: true } } } }

            // Empty
            Column { id: emptyHint; objectName: "hubEmpty"; visible: root.screenState === "empty"; width: parent.width; spacing: Spacing.gapSmall; Label { width: parent.width; text: qsTr("No recovery information available"); font.pixelSize: Typography.body.size; font.weight: Typography.weightSemibold; color: MissionTheme.textPrimary; wrapMode: Text.WordWrap; Accessible.role: Accessible.StaticText; Accessible.name: text }
            Label { width: parent.width; text: qsTr("Recovery status will appear here once the host provides data."); font.pixelSize: Typography.bodySmall.size; color: MissionTheme.textSecondary; wrapMode: Text.WordWrap; Accessible.role: Accessible.StaticText; Accessible.name: text } }

            // ══════════════════════════════════════════════════════
            // Normal content
            // ══════════════════════════════════════════════════════
            Column { visible: root.screenState === "normal"; width: parent.width; spacing: Spacing.gapLarge

                Label { text: qsTr("Recovery"); font.pixelSize: Typography.headline.size; font.weight: Typography.headline.weight; color: MissionTheme.textPrimary; anchors.leftMargin: Spacing.paddingPage; Accessible.role: Accessible.Heading; Accessible.name: text }

                // ── Recovery Status card ──
                Column { width: parent.width; spacing: Spacing.gapMedium
                    Label { text: qsTr("Recovery Status"); font.pixelSize: Typography.subtitle.size; font.weight: Typography.subtitle.weight; color: MissionTheme.textPrimary; anchors.leftMargin: Spacing.paddingPage; Accessible.role: Accessible.Heading; Accessible.name: text }
                    Rectangle {
                        width: parent.width - Spacing.paddingPage * 2; anchors.leftMargin: Spacing.paddingPage
                        height: statusGrid.implicitHeight + Spacing.paddingLarge * 2
                        radius: Radii.card; color: MissionTheme.surface; border.color: MissionTheme.outlineVariant; border.width: 1
                        Grid {
                            id: statusGrid; anchors { left: parent.left; right: parent.right; top: parent.top; margins: Spacing.paddingLarge }
                            columns: root.width >= 960 ? 4 : (root.width >= 640 ? 2 : 1); spacing: Spacing.gapMedium
                            Repeater {
                                model: [
                                    { key: "recoveryPartition", label: qsTr("Recovery Partition") },
                                    { key: "recoveryUsb", label: qsTr("Recovery USB") },
                                    { key: "restorePointsAvailable", label: qsTr("Restore Points") },
                                    { key: "backupEncrypted", label: qsTr("Backup Encrypted") }
                                ]
                                delegate: Column {
                                    required property var modelData; spacing: Spacing.gapTiny
                                    Row { spacing: Spacing.gapSmall; Rectangle { width: 8; height: 8; radius: 4; color: root.statusColor(root.recoveryStatus[modelData.key]); anchors.verticalCenter: parent.verticalCenter }
                                    Label { text: modelData.label; font.pixelSize: Typography.body.size; font.weight: Typography.weightSemibold; color: MissionTheme.textPrimary } }
                                    Label { text: root.statusLabel(root.recoveryStatus[modelData.key]); font.pixelSize: Typography.caption.size; color: root.statusColor(root.recoveryStatus[modelData.key]) }
                                    Accessible.role: Accessible.StaticText; Accessible.name: qsTr("%1: %2").arg(modelData.label).arg(root.statusLabel(root.recoveryStatus[modelData.key]))
                                }
                            }
                        }
                    }
                }

                // ── Backup info ──
                Column { width: parent.width; spacing: Spacing.gapMedium
                    Label { text: qsTr("Backup"); font.pixelSize: Typography.subtitle.size; font.weight: Typography.subtitle.weight; color: MissionTheme.textPrimary; anchors.leftMargin: Spacing.paddingPage; Accessible.role: Accessible.Heading; Accessible.name: text }
                    Rectangle {
                        width: parent.width - Spacing.paddingPage * 2; anchors.leftMargin: Spacing.paddingPage
                        height: backupCol.implicitHeight + Spacing.paddingLarge * 2
                        radius: Radii.card; color: MissionTheme.surface; border.color: MissionTheme.outlineVariant; border.width: 1
                        Column { id: backupCol; anchors { left: parent.left; right: parent.right; top: parent.top; margins: Spacing.paddingLarge }
                        spacing: Spacing.gapSmall
                            Row { spacing: Spacing.gapMedium
                                Column { spacing: Spacing.gapTiny; Label { text: qsTr("Latest Backup"); font.pixelSize: Typography.caption.size; color: MissionTheme.textSecondary }
                                Label { text: root.recoveryStatus.latestBackup !== undefined && String(root.recoveryStatus.latestBackup).length > 0 ? String(root.recoveryStatus.latestBackup) : qsTr("None"); font.pixelSize: Typography.body.size; font.weight: Typography.weightSemibold; color: MissionTheme.textPrimary } }
                                Column { visible: root.recoveryStatus.backupDestination !== undefined && String(root.recoveryStatus.backupDestination).length > 0; spacing: Spacing.gapTiny; Label { text: qsTr("Destination"); font.pixelSize: Typography.caption.size; color: MissionTheme.textSecondary }
                                Label { text: root.recoveryStatus.backupDestination !== undefined ? String(root.recoveryStatus.backupDestination) : ""; font.pixelSize: Typography.body.size; font.weight: Typography.weightSemibold; color: MissionTheme.textPrimary } }
                                Column { visible: root.recoveryStatus.backupSize !== undefined && String(root.recoveryStatus.backupSize).length > 0; spacing: Spacing.gapTiny; Label { text: qsTr("Size"); font.pixelSize: Typography.caption.size; color: MissionTheme.textSecondary }
                                Label { text: root.recoveryStatus.backupSize !== undefined ? String(root.recoveryStatus.backupSize) : ""; font.pixelSize: Typography.body.size; font.weight: Typography.weightSemibold; color: MissionTheme.textPrimary } }
                            }
                            MissionButton { variant: MissionButton.Variant.Secondary; text: qsTr("Create Backup"); onClicked: root.backupRequested() }
                        }
                    }
                }

                // ── Recovery Options ──
                Column { width: parent.width; spacing: Spacing.gapMedium
                    Label { text: qsTr("Recovery Options"); font.pixelSize: Typography.subtitle.size; font.weight: Typography.subtitle.weight; color: MissionTheme.textPrimary; anchors.leftMargin: Spacing.paddingPage; Accessible.role: Accessible.Heading; Accessible.name: text }

                    Column { visible: root.optionCount === 0; width: parent.width; spacing: Spacing.gapSmall; Label { width: parent.width; text: qsTr("No recovery options available"); font.pixelSize: Typography.body.size; font.weight: Typography.weightSemibold; color: MissionTheme.textPrimary; anchors.leftMargin: Spacing.paddingPage }
                    Label { width: parent.width; text: qsTr("Recovery options will appear here once the host provides data."); font.pixelSize: Typography.bodySmall.size; color: MissionTheme.textSecondary; anchors.leftMargin: Spacing.paddingPage } }

                    Repeater {
                        id: optionRepeater; model: root.recoveryOptions
                        delegate: Rectangle {
                            required property var modelData; required property int index
                            id: optRow; objectName: "opt_" + modelData.id
                            width: parent.width - Spacing.paddingPage * 2; anchors.leftMargin: Spacing.paddingPage
                            height: Math.max(Spacing.minimumTouchTarget, optContent.implicitHeight + Spacing.paddingMedium * 2)
                            radius: Radii.card; color: optMouse.containsMouse ? MissionTheme.surfaceVariant : MissionTheme.surface
                            border.color: modelData.destructive === true ? MissionTheme.error : MissionTheme.outlineVariant; border.width: 1
                            activeFocusOnTab: true
                            Behavior on color { enabled: !root.reducedMotion; animation: ColorAnimation { duration: Motion.colorChange } }
                            Rectangle { anchors.fill: parent; anchors.margins: -2; radius: Radii.card + 2; color: "transparent"; border.color: MissionTheme.focusRing; border.width: 2; visible: optRow.activeFocus }
                            MouseArea { id: optMouse; anchors.fill: parent; hoverEnabled: true; onClicked: { optRow.forceActiveFocus(); root.optionActivated(String(modelData.id)) } }
                            RowLayout {
                                id: optContent; anchors { left: parent.left; right: parent.right; top: parent.top; margins: Spacing.paddingMedium }
                                spacing: Spacing.gapMedium
                                Rectangle { visible: modelData.destructive === true; Layout.preferredWidth: 8; Layout.preferredHeight: 8; radius: 4; color: MissionTheme.error }
                                Column { Layout.fillWidth: true; spacing: Spacing.gapTiny
                                    Label { text: modelData.name !== undefined ? String(modelData.name) : String(modelData.id); font.pixelSize: Typography.body.size; font.weight: Typography.weightSemibold; color: MissionTheme.textPrimary; elide: Text.ElideRight; width: parent.width }
                                    Label { visible: modelData.description !== undefined && String(modelData.description).length > 0; text: modelData.description !== undefined ? String(modelData.description) : ""; font.pixelSize: Typography.bodySmall.size; color: MissionTheme.textSecondary; wrapMode: Text.Wrap; width: parent.width }
                                }
                                Rectangle { visible: modelData.destructive === true; width: warnLbl.implicitWidth + Spacing.paddingMedium * 2; height: Spacing.gapMedium; radius: Radii.chip; color: MissionTheme.error; Label { id: warnLbl; anchors.centerIn: parent; text: qsTr("Destructive"); font.pixelSize: Typography.caption.size; font.weight: Typography.weightSemibold; color: "white" } }
                            }
                            Accessible.role: Accessible.Button; Accessible.name: qsTr("Recovery option: %1%2").arg(modelData.name !== undefined ? modelData.name : modelData.id).arg(modelData.destructive === true ? " — destructive" : "")
                            Keys.onUpPressed: root.focusOption(index - 1); Keys.onDownPressed: root.focusOption(index + 1)
                            Keys.onReturnPressed: root.optionActivated(String(modelData.id)); Keys.onSpacePressed: root.optionActivated(String(modelData.id))
                        }
                    }
                }

                Item { width: 1; height: Spacing.paddingLarge }
            }
        }
    }
}
