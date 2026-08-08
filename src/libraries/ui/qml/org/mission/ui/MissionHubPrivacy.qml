// Mission OS — Mission Hub Privacy (MOS-HUB-006)
//
// Sixth screen of the Mission Hub family. Implements the source-defined
// Privacy structure (docs/design/03_SCREEN_REGISTRY.md MOS-HUB-006
// "Privacy", docs/reference/03_MISSION_HUB.md §3 Privacy Dashboard,
// Permission Manager, Activity Indicators, Privacy Reports,
// docs/design/01_INFORMATION_ARCHITECTURE.md §5 Mission Hub Structure,
// §8 Privacy Structure, docs/design/04_USER_FLOWS.md §8 Privacy Review):
//
//   Hosting: a full-screen application within Mission Hub. The host
//   opens this from the Mission Hub sidebar. Place inside MissionWindow
//   content and anchor to fill, e.g.
//   MissionWindow { MissionHubPrivacy { anchors.fill: parent } }
//   The component sizes to its implicit 1280x720 like Desktop.qml.
//
//   Layout (Master UX Specification §3):
//     Header → Sidebar Navigation → Main Content Area
//
//   Privacy Dashboard (reference §3):
//     Displays: Telemetry status, Crash reporting, Search provider,
//     Location access, Camera permissions, Microphone permissions,
//     Clipboard history, Recent permission requests.
//     "Mission OS defaults to the most privacy-preserving configuration
//     compatible with usability."
//
//   Permission Manager (reference §3):
//     Displays application permissions for: camera, microphone, location,
//     notifications, clipboard, screenshots, screen recording, removable
//     storage, network. Users may: allow, deny, revoke, reset.
//     "Permission changes apply immediately."
//
//   Activity Indicators (reference §3):
//     Live indicators when microphone, camera, screen recording, or
//     location is active. Selecting reveals the responsible application.
//
//   Privacy Reports (reference §3):
//     Users may generate reports showing: granted permissions, revoked
//     permissions, recent permission activity, security recommendations,
//     privacy recommendations. Reports should never contain personal content.
//
//   User Flow §8 (Privacy Review):
//     Mission Hub → Privacy Center → Dashboard → Permissions →
//     Apply Changes
//
//   Privacy Structure (information architecture §8):
//     Dashboard, Permissions, Privacy Score, Timeline, Reports,
//     Data Management, Profiles, Recommendations
//
// Interpretation notes (documented — no authoritative source specifies
// further detail):
//   - The sidebar is persistent on wide layouts (≥768px) and collapses
//     to an icon rail on narrow layouts (established Mission Hub pattern).
//   - Privacy status is host-driven: { telemetry, crashReporting,
//     searchProvider, locationAccess, cameraPermissions,
//     microphonePermissions, clipboardHistory, privacyScore }.
//     All fields are optional; missing data is handled defensively.
//   - Permissions are host-driven: each entry is
//     { id, app, permission, status?, grantedDate? }.
//     status ∈ "granted" | "denied" | "revoked". The screen never
//     mutates the model — actions emit signals.
//   - Active indicators are host-driven: [{ id, type, app? }].
//     type ∈ "microphone" | "camera" | "screenRecording" | "location".
//   - All privacy actions emit host-facing signals rather than
//     performing privileged/backend operations inside QML.
//   - Escape is deliberately unmapped: the host owns window-level
//     dismissal.
//   - Offline state shows a neutral message — Mission Hub works fully
//     offline.
//   - "Do NOT invent privacy mechanisms or claim protections the
//     backend does not provide" (task spec).
//
// Design-system compliance:
//   - Tokens only (Colors, Typography, Spacing, Radii, Motion, MissionTheme)
//   - Light + dark themes via MissionTheme (driven by host)
//   - Keyboard navigation with visible focus states; 44px minimum
//     touch targets (Spacing.minimumTouchTarget)
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

    /// Privacy status overview:
    /// { telemetry (bool|null), crashReporting (bool|null),
    ///   searchProvider (string|null), locationAccess (bool|null),
    ///   cameraPermissions (bool|null), microphonePermissions (bool|null),
    ///   clipboardHistory (bool|null), privacyScore (number|null) }
    property var privacyStatus: ({})

    /// Active indicators: [{ id, type, app? }]
    /// type ∈ "microphone" | "camera" | "screenRecording" | "location"
    property var activeIndicators: []

    /// Permissions: [{ id, app, permission, status?, grantedDate? }]
    /// status ∈ "granted" | "denied" | "revoked"
    property var permissions: []

    /// Recommendations: [{ id, title, description?, severity?, actionLabel? }]
    /// severity ∈ "info" | "warning" | "critical"
    property var recommendations: []

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
    property string selectedNavId: "privacy"

    // ── Signals (host wiring) ──────────────────────────────────────
    /// User activated a permission (host opens the detail or toggles it)
    signal permissionActivated(string permissionId)
    /// User activated an active indicator (host reveals the app)
    signal indicatorActivated(string indicatorId)
    /// User activated a recommendation (host opens the detail)
    signal recommendationActivated(string recommendationId)
    /// User activated a navigation item (host opens the screen)
    signal navigationActivated(string navId)

    // Escape is deliberately unmapped: the host owns window-level dismissal.

    // ── Derived helpers ────────────────────────────────────────────
    /// Number of permissions
    readonly property int permissionCount: root.permissions.length

    /// Number of active indicators
    readonly property int indicatorCount: root.activeIndicators.length

    /// Number of recommendations
    readonly property int recommendationCount: root.recommendations.length

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

    /// Privacy status bool → display label
    function privacyStatusLabel(value) {
        if (value === true) return qsTr("Enabled")
        if (value === false) return qsTr("Disabled")
        return qsTr("Unknown")
    }

    /// Privacy status bool → token color
    function privacyStatusColor(value) {
        if (value === true) return MissionTheme.success
        if (value === false) return MissionTheme.warning
        return MissionTheme.textSecondary
    }

    /// Permission status → display label
    function permStatusLabel(status) {
        switch (String(status)) {
        case "granted": return qsTr("Granted")
        case "denied":  return qsTr("Denied")
        case "revoked": return qsTr("Revoked")
        default:        return qsTr("Unknown")
        }
    }

    /// Permission status → token color
    function permStatusColor(status) {
        switch (String(status)) {
        case "granted": return MissionTheme.success
        case "denied":  return MissionTheme.error
        case "revoked": return MissionTheme.warning
        default:        return MissionTheme.textSecondary
        }
    }

    /// Indicator type → display label
    function indicatorLabel(type) {
        switch (String(type)) {
        case "microphone":      return qsTr("Microphone")
        case "camera":          return qsTr("Camera")
        case "screenRecording": return qsTr("Screen Recording")
        case "location":        return qsTr("Location")
        default:                return qsTr("Unknown")
        }
    }

    /// Severity → token color
    function severityColor(severity) {
        switch (String(severity)) {
        case "critical": return MissionTheme.error
        case "warning":  return MissionTheme.warning
        case "info":     return MissionTheme.primary
        default:         return MissionTheme.textSecondary
        }
    }

    /// Move keyboard focus to a navigation item
    function focusNavItem(index) {
        if (root.navigationItems.length === 0) return
        var count = root.navigationItems.length
        var target = ((index % count) + count) % count
        var item = navRepeater.itemAt(target)
        if (item !== null) item.forceActiveFocus()
    }

    /// Move keyboard focus to a permission row
    function focusPermission(index) {
        if (root.permissions.length === 0) return
        var count = root.permissions.length
        var target = ((index % count) + count) % count
        var item = permissionRepeater.itemAt(target)
        if (item !== null) item.forceActiveFocus()
    }

    /// Move keyboard focus to a recommendation row
    function focusRecommendation(index) {
        if (root.recommendations.length === 0) return
        var count = root.recommendations.length
        var target = ((index % count) + count) % count
        var item = recommendationRepeater.itemAt(target)
        if (item !== null) item.forceActiveFocus()
    }

    // ── Test hooks ──
    property alias headerBar: headerBar
    property alias titleLabel: titleLabel
    property alias sidebar: sidebar
    property alias navRepeater: navRepeater
    property alias mainContent: mainContent
    property alias permissionRepeater: permissionRepeater
    property alias indicatorRepeater: indicatorRepeater
    property alias recommendationRepeater: recommendationRepeater
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
                Label { text: qsTr("Loading privacy information…"); font.pixelSize: Typography.bodySmall.size; color: MissionTheme.textSecondary }
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
                        Label { text: qsTr("Could not load privacy information"); font.weight: Typography.weightSemibold; color: Colors.contentOnErrorContainer }
                        Label { text: qsTr("Privacy status could not be loaded. Check your system and try again."); font.pixelSize: Typography.bodySmall.size; color: Colors.contentOnErrorContainer; wrapMode: Text.Wrap; Layout.fillWidth: true }
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
                        Label { text: qsTr("Local privacy status is still available. Some features may require an internet connection."); font.pixelSize: Typography.bodySmall.size; color: MissionTheme.textSecondary; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    }
                }
            }

            // ── Empty state ──
            Column {
                id: emptyHint; objectName: "hubEmpty"
                visible: root.screenState === "empty"
                width: parent.width; spacing: Spacing.gapSmall
                Label { width: parent.width; text: qsTr("No privacy information available"); font.pixelSize: Typography.body.size; font.weight: Typography.weightSemibold; color: MissionTheme.textPrimary; wrapMode: Text.WordWrap; Accessible.role: Accessible.StaticText; Accessible.name: text }
                Label { width: parent.width; text: qsTr("Privacy status will appear here once the host provides privacy data."); font.pixelSize: Typography.bodySmall.size; color: MissionTheme.textSecondary; wrapMode: Text.WordWrap; Accessible.role: Accessible.StaticText; Accessible.name: text }
            }

            // ══════════════════════════════════════════════════════
            // Normal content
            // ══════════════════════════════════════════════════════
            Column {
                visible: root.screenState === "normal"
                width: parent.width; spacing: Spacing.gapLarge

                // ── Screen title ──
                Label {
                    text: qsTr("Privacy")
                    font.pixelSize: Typography.headline.size; font.weight: Typography.headline.weight
                    color: MissionTheme.textPrimary; anchors.leftMargin: Spacing.paddingPage
                    Accessible.role: Accessible.Heading; Accessible.name: text
                }

                // ── Active indicators (if any) ──
                Column {
                    visible: root.indicatorCount > 0
                    width: parent.width; spacing: Spacing.gapMedium

                    Label {
                        text: qsTr("Active Indicators")
                        font.pixelSize: Typography.subtitle.size; font.weight: Typography.subtitle.weight
                        color: MissionTheme.textPrimary; anchors.leftMargin: Spacing.paddingPage
                        Accessible.role: Accessible.Heading; Accessible.name: text
                    }

                    Repeater {
                        id: indicatorRepeater
                        model: root.activeIndicators

                        delegate: Rectangle {
                            required property var modelData
                            required property int index

                            id: indicatorRow
                            objectName: "indicator_" + modelData.id
                            width: parent.width - Spacing.paddingPage * 2
                            anchors.leftMargin: Spacing.paddingPage
                            height: Math.max(Spacing.minimumTouchTarget, indicatorContent.implicitHeight + Spacing.paddingMedium * 2)
                            radius: Radii.card
                            color: indicatorMouse.containsMouse ? MissionTheme.surfaceVariant : MissionTheme.surface
                            border.color: MissionTheme.error; border.width: 1
                            activeFocusOnTab: true

                            Behavior on color { enabled: !root.reducedMotion; animation: ColorAnimation { duration: Motion.colorChange } }

                            Rectangle {
                                anchors.fill: parent; anchors.margins: -2
                                radius: Radii.card + 2; color: "transparent"
                                border.color: MissionTheme.focusRing; border.width: 2
                                visible: indicatorRow.activeFocus
                            }

                            MouseArea {
                                id: indicatorMouse; anchors.fill: parent; hoverEnabled: true
                                onClicked: { indicatorRow.forceActiveFocus(); root.indicatorActivated(String(modelData.id)) }
                            }

                            RowLayout {
                                id: indicatorContent
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: Spacing.paddingMedium }
                                spacing: Spacing.gapMedium

                                Rectangle { Layout.preferredWidth: 8; Layout.preferredHeight: 8; radius: 4; color: MissionTheme.error }

                                Column {
                                    Layout.fillWidth: true; spacing: Spacing.gapTiny
                                    Label {
                                        text: root.indicatorLabel(modelData.type)
                                        font.pixelSize: Typography.body.size; font.weight: Typography.weightSemibold
                                        color: MissionTheme.textPrimary
                                    }
                                    Label {
                                        visible: modelData.app !== undefined && String(modelData.app).length > 0
                                        text: qsTr("Active: %1").arg(modelData.app)
                                        font.pixelSize: Typography.bodySmall.size; color: MissionTheme.textSecondary
                                    }
                                }
                            }

                            Accessible.role: Accessible.Button
                            Accessible.name: qsTr("Active %1 indicator").arg(root.indicatorLabel(modelData.type))

                            Keys.onReturnPressed: root.indicatorActivated(String(modelData.id))
                            Keys.onSpacePressed: root.indicatorActivated(String(modelData.id))
                        }
                    }
                }

                // ── Privacy Status card ──
                Column {
                    width: parent.width; spacing: Spacing.gapMedium

                    Label {
                        text: qsTr("Privacy Status")
                        font.pixelSize: Typography.subtitle.size; font.weight: Typography.subtitle.weight
                        color: MissionTheme.textPrimary; anchors.leftMargin: Spacing.paddingPage
                        Accessible.role: Accessible.Heading; Accessible.name: text
                    }

                    Rectangle {
                        width: parent.width - Spacing.paddingPage * 2; anchors.leftMargin: Spacing.paddingPage
                        height: statusGrid.implicitHeight + Spacing.paddingLarge * 2
                        radius: Radii.card; color: MissionTheme.surface
                        border.color: MissionTheme.outlineVariant; border.width: 1

                        Grid {
                            id: statusGrid
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Spacing.paddingLarge }
                            columns: root.width >= 960 ? 4 : (root.width >= 640 ? 2 : 1)
                            spacing: Spacing.gapMedium

                            Repeater {
                                model: [
                                    { key: "telemetry",              label: qsTr("Telemetry") },
                                    { key: "crashReporting",          label: qsTr("Crash Reporting") },
                                    { key: "locationAccess",          label: qsTr("Location Access") },
                                    { key: "cameraPermissions",       label: qsTr("Camera") },
                                    { key: "microphonePermissions",   label: qsTr("Microphone") },
                                    { key: "clipboardHistory",        label: qsTr("Clipboard History") }
                                ]

                                delegate: Column {
                                    required property var modelData
                                    spacing: Spacing.gapTiny

                                    Row {
                                        spacing: Spacing.gapSmall
                                        Rectangle {
                                            width: 8; height: 8; radius: 4
                                            color: root.privacyStatusColor(root.privacyStatus[modelData.key])
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Label {
                                            text: modelData.label
                                            font.pixelSize: Typography.body.size; font.weight: Typography.weightSemibold
                                            color: MissionTheme.textPrimary
                                        }
                                    }
                                    Label {
                                        text: root.privacyStatusLabel(root.privacyStatus[modelData.key])
                                        font.pixelSize: Typography.caption.size
                                        color: root.privacyStatusColor(root.privacyStatus[modelData.key])
                                    }

                                    Accessible.role: Accessible.StaticText
                                    Accessible.name: qsTr("%1: %2").arg(modelData.label).arg(
                                        root.privacyStatusLabel(root.privacyStatus[modelData.key])
                                    )
                                }
                            }
                        }
                    }
                }

                // ── Permissions section ──
                Column {
                    width: parent.width; spacing: Spacing.gapMedium

                    Label {
                        text: qsTr("Permissions")
                        font.pixelSize: Typography.subtitle.size; font.weight: Typography.subtitle.weight
                        color: MissionTheme.textPrimary; anchors.leftMargin: Spacing.paddingPage
                        Accessible.role: Accessible.Heading; Accessible.name: text
                    }

                    Column {
                        visible: root.permissionCount === 0
                        width: parent.width; spacing: Spacing.gapSmall
                        Label { width: parent.width; text: qsTr("No permission data available"); font.pixelSize: Typography.body.size; font.weight: Typography.weightSemibold; color: MissionTheme.textPrimary; wrapMode: Text.WordWrap; anchors.leftMargin: Spacing.paddingPage }
                        Label { width: parent.width; text: qsTr("Permission information will appear here once the host provides data."); font.pixelSize: Typography.bodySmall.size; color: MissionTheme.textSecondary; wrapMode: Text.WordWrap; anchors.leftMargin: Spacing.paddingPage }
                    }

                    Repeater {
                        id: permissionRepeater
                        model: root.permissions

                        delegate: Rectangle {
                            required property var modelData
                            required property int index

                            id: permRow
                            objectName: "perm_" + modelData.id
                            width: parent.width - Spacing.paddingPage * 2; anchors.leftMargin: Spacing.paddingPage
                            height: Math.max(Spacing.minimumTouchTarget, permContent.implicitHeight + Spacing.paddingMedium * 2)
                            radius: Radii.card
                            color: permMouse.containsMouse ? MissionTheme.surfaceVariant : MissionTheme.surface
                            border.color: MissionTheme.outlineVariant; border.width: 1
                            activeFocusOnTab: true

                            Behavior on color { enabled: !root.reducedMotion; animation: ColorAnimation { duration: Motion.colorChange } }

                            Rectangle {
                                anchors.fill: parent; anchors.margins: -2
                                radius: Radii.card + 2; color: "transparent"
                                border.color: MissionTheme.focusRing; border.width: 2
                                visible: permRow.activeFocus
                            }

                            MouseArea {
                                id: permMouse; anchors.fill: parent; hoverEnabled: true
                                onClicked: { permRow.forceActiveFocus(); root.permissionActivated(String(modelData.id)) }
                            }

                            RowLayout {
                                id: permContent
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: Spacing.paddingMedium }
                                spacing: Spacing.gapMedium

                                Rectangle {
                                    Layout.preferredWidth: 8; Layout.preferredHeight: 8; radius: 4
                                    color: root.permStatusColor(modelData.status)
                                }

                                Column {
                                    Layout.fillWidth: true; spacing: Spacing.gapTiny
                                    Label {
                                        text: modelData.permission !== undefined ? String(modelData.permission) : String(modelData.id)
                                        font.pixelSize: Typography.body.size; font.weight: Typography.weightSemibold
                                        color: MissionTheme.textPrimary; elide: Text.ElideRight; width: parent.width
                                    }
                                    Label {
                                        visible: modelData.app !== undefined && String(modelData.app).length > 0
                                        text: modelData.app !== undefined ? String(modelData.app) : ""
                                        font.pixelSize: Typography.bodySmall.size; color: MissionTheme.textSecondary
                                    }
                                }

                                Rectangle {
                                    Layout.preferredWidth: statusLbl.implicitWidth + Spacing.paddingMedium * 2
                                    Layout.preferredHeight: Spacing.gapMedium; radius: Radii.chip
                                    color: MissionTheme.surfaceVariant
                                    Label {
                                        id: statusLbl; anchors.centerIn: parent
                                        text: root.permStatusLabel(modelData.status)
                                        font.pixelSize: Typography.caption.size
                                        color: root.permStatusColor(modelData.status)
                                    }
                                }
                            }

                            Accessible.role: Accessible.Button
                            Accessible.name: qsTr("Permission: %1 — %2").arg(
                                modelData.permission !== undefined ? modelData.permission : modelData.id
                            ).arg(root.permStatusLabel(modelData.status))

                            Keys.onUpPressed: root.focusPermission(index - 1)
                            Keys.onDownPressed: root.focusPermission(index + 1)
                            Keys.onReturnPressed: root.permissionActivated(String(modelData.id))
                            Keys.onSpacePressed: root.permissionActivated(String(modelData.id))
                        }
                    }
                }

                // ── Recommendations section ──
                Column {
                    visible: root.recommendationCount > 0
                    width: parent.width; spacing: Spacing.gapMedium

                    Label {
                        text: qsTr("Recommendations")
                        font.pixelSize: Typography.subtitle.size; font.weight: Typography.subtitle.weight
                        color: MissionTheme.textPrimary; anchors.leftMargin: Spacing.paddingPage
                        Accessible.role: Accessible.Heading; Accessible.name: text
                    }

                    Repeater {
                        id: recommendationRepeater
                        model: root.recommendations

                        delegate: Rectangle {
                            required property var modelData
                            required property int index

                            id: recRow
                            objectName: "rec_" + modelData.id
                            width: parent.width - Spacing.paddingPage * 2; anchors.leftMargin: Spacing.paddingPage
                            height: Math.max(Spacing.minimumTouchTarget, recContent.implicitHeight + Spacing.paddingMedium * 2)
                            radius: Radii.card
                            color: recMouse.containsMouse ? MissionTheme.surfaceVariant : MissionTheme.surface
                            border.color: MissionTheme.outlineVariant; border.width: 1
                            activeFocusOnTab: true

                            Behavior on color { enabled: !root.reducedMotion; animation: ColorAnimation { duration: Motion.colorChange } }

                            Rectangle {
                                anchors.fill: parent; anchors.margins: -2
                                radius: Radii.card + 2; color: "transparent"
                                border.color: MissionTheme.focusRing; border.width: 2
                                visible: recRow.activeFocus
                            }

                            MouseArea {
                                id: recMouse; anchors.fill: parent; hoverEnabled: true
                                onClicked: { recRow.forceActiveFocus(); root.recommendationActivated(String(modelData.id)) }
                            }

                            RowLayout {
                                id: recContent
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: Spacing.paddingMedium }
                                spacing: Spacing.gapMedium

                                Rectangle {
                                    visible: modelData.severity !== undefined && String(modelData.severity).length > 0
                                    Layout.preferredWidth: 8; Layout.preferredHeight: 8; radius: 4
                                    color: root.severityColor(modelData.severity)
                                }

                                Column {
                                    Layout.fillWidth: true; spacing: Spacing.gapTiny
                                    Label {
                                        text: modelData.title !== undefined ? String(modelData.title) : String(modelData.id)
                                        font.pixelSize: Typography.body.size; font.weight: Typography.weightSemibold
                                        color: MissionTheme.textPrimary; elide: Text.ElideRight; width: parent.width
                                    }
                                    Label {
                                        visible: modelData.description !== undefined && String(modelData.description).length > 0
                                        text: modelData.description !== undefined ? String(modelData.description) : ""
                                        font.pixelSize: Typography.bodySmall.size; color: MissionTheme.textSecondary
                                        wrapMode: Text.Wrap; width: parent.width
                                    }
                                }
                            }

                            Accessible.role: Accessible.Button
                            Accessible.name: qsTr("Recommendation: %1").arg(
                                modelData.title !== undefined ? modelData.title : modelData.id
                            )

                            Keys.onUpPressed: root.focusRecommendation(index - 1)
                            Keys.onDownPressed: root.focusRecommendation(index + 1)
                            Keys.onReturnPressed: root.recommendationActivated(String(modelData.id))
                            Keys.onSpacePressed: root.recommendationActivated(String(modelData.id))
                        }
                    }
                }

                // ── Bottom spacer ──
                Item { width: 1; height: Spacing.paddingLarge }
            }
        }
    }
}
