// Mission OS — Mission Hub Diagnostics (MOS-HUB-008)
//
// Eighth screen of the Mission Hub family. Implements the source-defined
// Diagnostics structure (docs/design/03_SCREEN_REGISTRY.md MOS-HUB-008
// "Diagnostics", docs/reference/03_MISSION_HUB.md §4 Diagnostics Center,
// §2 Diagnostics Summary,
// docs/design/01_INFORMATION_ARCHITECTURE.md §5 Mission Hub Structure,
// §10 Diagnostics Structure, docs/design/04_USER_FLOWS.md §10 Recovery):
//
//   Hosting: a full-screen application within Mission Hub. Place inside
//   MissionWindow content and anchor to fill, e.g.
//   MissionWindow { MissionHubDiagnostics { anchors.fill: parent } }
//   The component sizes to its implicit 1280x720 like Desktop.qml.
//
//   Layout (Master UX Specification §3):
//     Header → Sidebar Navigation → Main Content Area
//
//   Diagnostics Center (reference §4):
//     Performs diagnostics for: CPU, RAM, GPU, Storage, Network, Battery,
//     Audio, Display, Boot process. Each diagnostic returns: Pass, Warning,
//     Failed. Every failure includes recommended actions.
//
//   Diagnostics Summary (reference §2):
//     Shows: last scan, hardware issues, software issues,
//     recommended actions. "Users may launch diagnostics directly."
//
//   Diagnostics Structure (information architecture §10):
//     Dashboard, Hardware, CPU, GPU, Memory, Storage, Network, Drivers,
//     Security, Reports
//
// Interpretation notes (documented — no authoritative source specifies
// further detail):
//   - Diagnostics overview is host-driven: { lastScan (string|null),
//     hardwareIssues (number|null), softwareIssues (number|null) }.
//   - Diagnostic results are host-driven: each entry is
//     { id, category, status, description?, recommendation? }.
//     category ∈ "cpu" | "ram" | "gpu" | "storage" | "network" |
//     "battery" | "audio" | "display" | "boot".
//     status ∈ "pass" | "warning" | "failed".
//   - The screen never mutates the model — run diagnostics emits
//     a signal; the host performs the actual scan.
//   - All diagnostic actions emit host-facing signals rather than
//     performing hardware inspection inside QML.
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

    /// Diagnostics overview: { lastScan, hardwareIssues, softwareIssues }
    property var diagnosticsOverview: ({})

    /// Diagnostic results: [{ id, category, status, description?, recommendation? }]
    /// category ∈ "cpu" | "ram" | "gpu" | "storage" | "network" | "battery" | "audio" | "display" | "boot"
    /// status ∈ "pass" | "warning" | "failed"
    property var diagnosticResults: []

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

    property string selectedNavId: "diagnostics"

    // ── Signals ────────────────────────────────────────────────────
    /// User requested a diagnostics scan
    signal runDiagnostics()
    /// User activated a diagnostic result (host opens detail)
    signal resultActivated(string resultId)
    /// User activated a navigation item
    signal navigationActivated(string navId)

    // ── Derived helpers ────────────────────────────────────────────
    readonly property int resultCount: root.diagnosticResults.length
    readonly property int navCount: root.navigationItems.length
    readonly property bool sidebarExpanded: root.width >= 768

    /// Count of failed results
    readonly property int failedCount: {
        var c = 0
        for (var i = 0; i < root.diagnosticResults.length; i++) {
            if (root.diagnosticResults[i].status === "failed") c++
        }
        return c
    }

    /// Count of warning results
    readonly property int warningCount: {
        var c = 0
        for (var i = 0; i < root.diagnosticResults.length; i++) {
            if (root.diagnosticResults[i].status === "warning") c++
        }
        return c
    }

    /// Count of passed results
    readonly property int passedCount: {
        var c = 0
        for (var i = 0; i < root.diagnosticResults.length; i++) {
            if (root.diagnosticResults[i].status === "pass") c++
        }
        return c
    }

    function navLabel(item) {
        if (item === null || item === undefined) return ""
        var l = item.label !== undefined ? String(item.label) : ""
        return l.length > 0 ? l : String(item.id)
    }

    function statusLabel(status) {
        switch (String(status)) {
        case "pass":    return qsTr("Pass")
        case "warning": return qsTr("Warning")
        case "failed":  return qsTr("Failed")
        default:        return qsTr("Unknown")
        }
    }

    function statusColor(status) {
        switch (String(status)) {
        case "pass":    return MissionTheme.success
        case "warning": return MissionTheme.warning
        case "failed":  return MissionTheme.error
        default:        return MissionTheme.textSecondary
        }
    }

    function categoryLabel(category) {
        switch (String(category)) {
        case "cpu":     return qsTr("CPU")
        case "ram":     return qsTr("Memory")
        case "gpu":     return qsTr("GPU")
        case "storage": return qsTr("Storage")
        case "network": return qsTr("Network")
        case "battery": return qsTr("Battery")
        case "audio":   return qsTr("Audio")
        case "display": return qsTr("Display")
        case "boot":    return qsTr("Boot")
        default:        return qsTr("Unknown")
        }
    }

    function focusNavItem(index) {
        if (root.navigationItems.length === 0) return
        var count = root.navigationItems.length
        var target = ((index % count) + count) % count
        var item = navRepeater.itemAt(target)
        if (item !== null) item.forceActiveFocus()
    }

    function focusResult(index) {
        if (root.diagnosticResults.length === 0) return
        var count = root.diagnosticResults.length
        var target = ((index % count) + count) % count
        var item = resultRepeater.itemAt(target)
        if (item !== null) item.forceActiveFocus()
    }

    // ── Test hooks ──
    property alias headerBar: headerBar
    property alias titleLabel: titleLabel
    property alias sidebar: sidebar
    property alias navRepeater: navRepeater
    property alias mainContent: mainContent
    property alias resultRepeater: resultRepeater
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
            Label { text: qsTr("Running diagnostics…"); font.pixelSize: Typography.bodySmall.size; color: MissionTheme.textSecondary }
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 4; radius: 2; color: MissionTheme.surfaceDim; Rectangle { width: 96; height: 4; radius: 2; color: MissionTheme.primary; x: -96; NumberAnimation on x { running: root.screenState === "loading" && !root.reducedMotion; from: -96; to: loadingIndicator.width; duration: Motion.durationSlow; loops: Animation.Infinite } } } }

            // Error
            Rectangle { id: errorBanner; objectName: "hubError"; visible: root.screenState === "error"; width: parent.width - Spacing.paddingPage * 2; anchors.leftMargin: Spacing.paddingPage; height: errorLayout.implicitHeight + Spacing.paddingMedium * 2; radius: Radii.card; color: Colors.errorContainer; RowLayout { id: errorLayout; anchors.fill: parent; anchors.margins: Spacing.paddingMedium; spacing: Spacing.gapMedium; Rectangle { Layout.preferredWidth: 12; Layout.preferredHeight: 12; radius: 6; color: MissionTheme.error }
            ColumnLayout { Layout.fillWidth: true; spacing: Spacing.gapTiny; Label { text: qsTr("Could not load diagnostics"); font.weight: Typography.weightSemibold; color: Colors.contentOnErrorContainer }
            Label { text: qsTr("Diagnostics information could not be loaded. Check your system and try again."); font.pixelSize: Typography.bodySmall.size; color: Colors.contentOnErrorContainer; wrapMode: Text.Wrap; Layout.fillWidth: true } } } }

            // Offline
            Rectangle { id: offlineBanner; objectName: "hubOffline"; visible: root.screenState === "offline"; width: parent.width - Spacing.paddingPage * 2; anchors.leftMargin: Spacing.paddingPage; height: offlineLayout.implicitHeight + Spacing.paddingMedium * 2; radius: Radii.card; color: MissionTheme.surfaceVariant; RowLayout { id: offlineLayout; anchors.fill: parent; anchors.margins: Spacing.paddingMedium; spacing: Spacing.gapMedium; Rectangle { Layout.preferredWidth: 12; Layout.preferredHeight: 12; radius: 6; color: MissionTheme.textSecondary }
            ColumnLayout { Layout.fillWidth: true; spacing: Spacing.gapTiny; Label { text: qsTr("You're offline"); font.weight: Typography.weightSemibold; color: MissionTheme.textPrimary }
            Label { text: qsTr("Previous diagnostics results are available. Running new diagnostics requires a system connection."); font.pixelSize: Typography.bodySmall.size; color: MissionTheme.textSecondary; wrapMode: Text.Wrap; Layout.fillWidth: true } } } }

            // Empty
            Column { id: emptyHint; objectName: "hubEmpty"; visible: root.screenState === "empty"; width: parent.width; spacing: Spacing.gapSmall; Label { width: parent.width; text: qsTr("No diagnostics information available"); font.pixelSize: Typography.body.size; font.weight: Typography.weightSemibold; color: MissionTheme.textPrimary; wrapMode: Text.WordWrap; Accessible.role: Accessible.StaticText; Accessible.name: text }
            Label { width: parent.width; text: qsTr("Diagnostics results will appear here once the host provides data."); font.pixelSize: Typography.bodySmall.size; color: MissionTheme.textSecondary; wrapMode: Text.WordWrap; Accessible.role: Accessible.StaticText; Accessible.name: text } }

            // ══════════════════════════════════════════════════════
            // Normal content
            // ══════════════════════════════════════════════════════
            Column { visible: root.screenState === "normal"; width: parent.width; spacing: Spacing.gapLarge

                Label { text: qsTr("Diagnostics"); font.pixelSize: Typography.headline.size; font.weight: Typography.headline.weight; color: MissionTheme.textPrimary; anchors.leftMargin: Spacing.paddingPage; Accessible.role: Accessible.Heading; Accessible.name: text }

                // ── Overview card ──
                Rectangle {
                    width: parent.width - Spacing.paddingPage * 2; anchors.leftMargin: Spacing.paddingPage
                    height: overviewRow.implicitHeight + Spacing.paddingLarge * 2
                    radius: Radii.card; color: MissionTheme.surface; border.color: MissionTheme.outlineVariant; border.width: 1
                    RowLayout {
                        id: overviewRow; anchors { left: parent.left; right: parent.right; top: parent.top; margins: Spacing.paddingLarge }
                        spacing: Spacing.gapLarge
                        Column { spacing: Spacing.gapTiny
                            Label { text: qsTr("Last Scan"); font.pixelSize: Typography.caption.size; color: MissionTheme.textSecondary }
                            Label { text: root.diagnosticsOverview.lastScan !== undefined && String(root.diagnosticsOverview.lastScan).length > 0 ? String(root.diagnosticsOverview.lastScan) : qsTr("Never"); font.pixelSize: Typography.body.size; font.weight: Typography.weightSemibold; color: MissionTheme.textPrimary }
                        }
                        Column { spacing: Spacing.gapTiny
                            Label { text: qsTr("Hardware Issues"); font.pixelSize: Typography.caption.size; color: MissionTheme.textSecondary }
                            Label { text: root.diagnosticsOverview.hardwareIssues !== undefined ? String(root.diagnosticsOverview.hardwareIssues) : "0"; font.pixelSize: Typography.body.size; font.weight: Typography.weightSemibold; color: MissionTheme.textPrimary }
                        }
                        Column { spacing: Spacing.gapTiny
                            Label { text: qsTr("Software Issues"); font.pixelSize: Typography.caption.size; color: MissionTheme.textSecondary }
                            Label { text: root.diagnosticsOverview.softwareIssues !== undefined ? String(root.diagnosticsOverview.softwareIssues) : "0"; font.pixelSize: Typography.body.size; font.weight: Typography.weightSemibold; color: MissionTheme.textPrimary }
                        }
                        Item { Layout.fillWidth: true }
                        MissionButton { variant: MissionButton.Variant.Secondary; text: qsTr("Run Diagnostics"); onClicked: root.runDiagnostics() }
                    }
                }

                // ── Summary badges ──
                Row { spacing: Spacing.gapMedium; anchors.leftMargin: Spacing.paddingPage
                    Rectangle { width: badge1.implicitWidth + Spacing.paddingMedium * 2; height: Spacing.minimumTouchTarget; radius: Radii.chip; color: MissionTheme.success; Label { id: badge1; anchors.centerIn: parent; text: qsTr("%1 Passed").arg(root.passedCount); font.pixelSize: Typography.bodySmall.size; font.weight: Typography.weightSemibold; color: "white" } }
                    Rectangle { visible: root.warningCount > 0; width: badge2.implicitWidth + Spacing.paddingMedium * 2; height: Spacing.minimumTouchTarget; radius: Radii.chip; color: MissionTheme.warning; Label { id: badge2; anchors.centerIn: parent; text: qsTr("%1 Warning").arg(root.warningCount); font.pixelSize: Typography.bodySmall.size; font.weight: Typography.weightSemibold; color: "white" } }
                    Rectangle { visible: root.failedCount > 0; width: badge3.implicitWidth + Spacing.paddingMedium * 2; height: Spacing.minimumTouchTarget; radius: Radii.chip; color: MissionTheme.error; Label { id: badge3; anchors.centerIn: parent; text: qsTr("%1 Failed").arg(root.failedCount); font.pixelSize: Typography.bodySmall.size; font.weight: Typography.weightSemibold; color: "white" } }
                }

                // ── Diagnostic Results ──
                Column { width: parent.width; spacing: Spacing.gapMedium
                    Label { text: qsTr("Results"); font.pixelSize: Typography.subtitle.size; font.weight: Typography.subtitle.weight; color: MissionTheme.textPrimary; anchors.leftMargin: Spacing.paddingPage; Accessible.role: Accessible.Heading; Accessible.name: text }

                    Column { visible: root.resultCount === 0; width: parent.width; spacing: Spacing.gapSmall; Label { width: parent.width; text: qsTr("No diagnostic results yet"); font.pixelSize: Typography.body.size; font.weight: Typography.weightSemibold; color: MissionTheme.textPrimary; anchors.leftMargin: Spacing.paddingPage }
                    Label { width: parent.width; text: qsTr("Run diagnostics to check your system hardware and software."); font.pixelSize: Typography.bodySmall.size; color: MissionTheme.textSecondary; anchors.leftMargin: Spacing.paddingPage } }

                    Repeater {
                        id: resultRepeater; model: root.diagnosticResults
                        delegate: Rectangle {
                            required property var modelData; required property int index
                            id: resRow; objectName: "res_" + modelData.id
                            width: parent.width - Spacing.paddingPage * 2; anchors.leftMargin: Spacing.paddingPage
                            height: Math.max(Spacing.minimumTouchTarget, resContent.implicitHeight + Spacing.paddingMedium * 2)
                            radius: Radii.card; color: resMouse.containsMouse ? MissionTheme.surfaceVariant : MissionTheme.surface
                            border.color: MissionTheme.outlineVariant; border.width: 1
                            activeFocusOnTab: true
                            Behavior on color { enabled: !root.reducedMotion; animation: ColorAnimation { duration: Motion.colorChange } }
                            Rectangle { anchors.fill: parent; anchors.margins: -2; radius: Radii.card + 2; color: "transparent"; border.color: MissionTheme.focusRing; border.width: 2; visible: resRow.activeFocus }
                            MouseArea { id: resMouse; anchors.fill: parent; hoverEnabled: true; onClicked: { resRow.forceActiveFocus(); root.resultActivated(String(modelData.id)) } }
                            RowLayout {
                                id: resContent; anchors { left: parent.left; right: parent.right; top: parent.top; margins: Spacing.paddingMedium }
                                spacing: Spacing.gapMedium
                                Rectangle { Layout.preferredWidth: 8; Layout.preferredHeight: 8; radius: 4; color: root.statusColor(modelData.status) }
                                Column { Layout.fillWidth: true; spacing: Spacing.gapTiny
                                    Row { spacing: Spacing.gapSmall
                                        Label { text: root.categoryLabel(modelData.category); font.pixelSize: Typography.body.size; font.weight: Typography.weightSemibold; color: MissionTheme.textPrimary }
                                        Label { text: "—" + root.statusLabel(modelData.status); font.pixelSize: Typography.body.size; color: root.statusColor(modelData.status) }
                                    }
                                    Label { visible: modelData.description !== undefined && String(modelData.description).length > 0; text: modelData.description !== undefined ? String(modelData.description) : ""; font.pixelSize: Typography.bodySmall.size; color: MissionTheme.textSecondary; wrapMode: Text.Wrap; width: parent.width }
                                    Label { visible: modelData.recommendation !== undefined && String(modelData.recommendation).length > 0; text: modelData.recommendation !== undefined ? String(modelData.recommendation) : ""; font.pixelSize: Typography.bodySmall.size; color: MissionTheme.textTertiary; wrapMode: Text.Wrap; width: parent.width }
                                }
                            }
                            Accessible.role: Accessible.Button; Accessible.name: qsTr("%1: %2").arg(root.categoryLabel(modelData.category)).arg(root.statusLabel(modelData.status))
                            Keys.onUpPressed: root.focusResult(index - 1); Keys.onDownPressed: root.focusResult(index + 1)
                            Keys.onReturnPressed: root.resultActivated(String(modelData.id)); Keys.onSpacePressed: root.resultActivated(String(modelData.id))
                        }
                    }
                }

                Item { width: 1; height: Spacing.paddingLarge }
            }
        }
    }
}
