// Mission OS — Mission Hub Dashboard (MOS-HUB-001)
//
// First screen of the Mission Hub family. Implements the source-defined
// Dashboard structure (docs/design/03_SCREEN_REGISTRY.md MOS-HUB-001
// "Dashboard", docs/wireframes/04_MISSION_HUB.md, docs/reference/
// 03_MISSION_HUB.md §5 Home Dashboard, docs/design/01_INFORMATION_
// ARCHITECTURE.md §5 Mission Hub Structure):
//
//   Hosting: a full-screen application (not an overlay like the Desktop
//   family). The host opens Mission Hub from the Desktop's Top Panel
//   Mission Menu or from System Ready's "Open Mission Hub" button.
//   Place inside MissionWindow content and anchor to fill, e.g.
//   MissionWindow { MissionHubDashboard { anchors.fill: parent } }
//   The component sizes to its implicit 1280x720 like Desktop.qml.
//
//   Layout (Master UX Specification §3):
//     Header → Sidebar Navigation → Main Content Area
//
//   Dashboard (wireframe § Layout):
//     Top Header → Global Search → Quick Actions → Dashboard Cards →
//     Recent Activity → Recommendations
//
//   Dashboard Cards (wireframe § Dashboard Cards):
//     Privacy, Security, Updates, Recovery, Storage, Devices, Network,
//     System Health
//
//   Home Dashboard (reference §5):
//     Mission OS version, Build channel, System Health Score,
//     Security Status, Privacy Status, Available Updates,
//     Storage Usage, Memory Usage, CPU Usage, GPU Usage,
//     Battery Status, Recent Notifications, Connected Devices
//
//   Navigation (reference §8):
//     Persistent left-side navigation: Dashboard, Security, Privacy,
//     Updates, Recovery, Diagnostics, Drivers, Storage, Devices,
//     Workspaces, Settings
//
//   States (wireframe § States):
//     Normal, Loading, Empty, Offline, Error
//
// Interpretation notes (documented — no authoritative source specifies
// further detail):
//   - The sidebar is persistent on wide layouts (≥768px) and collapses
//     to an icon rail on narrow layouts (the responsive reflow pattern
//     from docs/design/14_RESPONSIVE_RULES.md).
//   - Dashboard cards are host-driven: each entry is
//     { id, label, description?, status?, level?, icon? }. The host
//     owns the data; the screen is presentation-only.
//   - Navigation items emit signals; the host opens the corresponding
//     screen. This mirrors the Desktop family's host-driven pattern.
//   - The health score is host-fed: { score, label, level } where
//     level ∈ "excellent" | "good" | "attention" | "critical".
//   - Quick actions are host-driven: each entry is
//     { id, label, icon? }. Clicking emits quickActionActivated(id).
//   - Recent activity is host-driven: each entry is
//     { id, title, description?, timestamp?, level? }.
//   - Escape is deliberately unmapped on the Dashboard root: the
//     host owns window-level dismissal. Individual navigation items
//     may handle Escape for their own context.
//   - Offline state shows a neutral message — Mission Hub works
//     fully offline (reference §2: "function fully offline except
//     where Internet access is explicitly required").
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

    /// System health score: { score (0-100), label, level }
    /// level ∈ "excellent" | "good" | "attention" | "critical"
    property var healthScore: ({ score: 85, label: "Good", level: "good" })

    /// Dashboard cards: [{ id, label, description?, status?, level?, icon? }]
    /// level ∈ "ok" | "warning" | "critical"
    property var dashboardCards: [
        { id: "privacy",   label: "Privacy",   status: "Protected",     level: "ok" },
        { id: "security",  label: "Security",  status: "Secure",        level: "ok" },
        { id: "updates",   label: "Updates",   status: "Up to date",    level: "ok" },
        { id: "recovery",  label: "Recovery",  status: "Configured",    level: "ok" },
        { id: "storage",   label: "Storage",   status: "72% free",      level: "ok" },
        { id: "devices",   label: "Devices",   status: "3 connected",   level: "ok" },
        { id: "network",   label: "Network",   status: "Connected",     level: "ok" },
        { id: "health",    label: "System Health", status: "Good",      level: "ok" }
    ]

    /// Quick actions: [{ id, label, icon? }]
    property var quickActions: [
        { id: "check-updates",  label: "Check for Updates" },
        { id: "privacy-center", label: "Privacy Center" },
        { id: "run-diagnostics", label: "Run Diagnostics" },
        { id: "open-settings",  label: "Settings" }
    ]

    /// Recent activity: [{ id, title, description?, timestamp?, level? }]
    property var recentActivity: []

    /// Navigation items: [{ id, label, icon? }]
    property var navigationItems: [
        { id: "dashboard",  label: "Dashboard" },
        { id: "security",   label: "Security" },
        { id: "privacy",    label: "Privacy" },
        { id: "updates",    label: "Updates" },
        { id: "recovery",   label: "Recovery" },
        { id: "diagnostics", label: "Diagnostics" },
        { id: "drivers",    label: "Drivers" },
        { id: "storage",    label: "Storage" },
        { id: "devices",    label: "Devices" },
        { id: "workspaces", label: "Workspaces" },
        { id: "settings",   label: "Settings" }
    ]

    /// Currently selected navigation item id
    property string selectedNavId: "dashboard"

    // ── Signals (host wiring) ──────────────────────────────────────
    /// User activated a dashboard card (host opens the card's detail)
    signal cardActivated(string cardId)
    /// User activated a quick action (host executes the action)
    signal quickActionActivated(string actionId)
    /// User activated a navigation item (host opens the screen)
    signal navigationActivated(string navId)
    /// User activated a recent activity item
    signal activityActivated(string activityId)

    // Escape is deliberately unmapped (see interpretation notes): the
    // host owns window-level dismissal.

    // ── Derived helpers ────────────────────────────────────────────
    /// Display label for a navigation item (falls back to id)
    function navLabel(item) {
        if (item === null || item === undefined) return ""
        var l = item.label !== undefined ? String(item.label) : ""
        return l.length > 0 ? l : String(item.id)
    }

    /// Level → token color for dashboard cards
    function cardLevelColor(level) {
        switch (String(level)) {
        case "warning":  return MissionTheme.warning
        case "critical": return MissionTheme.error
        default:         return MissionTheme.success
        }
    }

    /// Health level → display label
    function healthLevelLabel(level) {
        switch (String(level)) {
        case "excellent": return qsTr("Excellent")
        case "good":      return qsTr("Good")
        case "attention": return qsTr("Attention Required")
        case "critical":  return qsTr("Critical")
        default:          return qsTr("Good")
        }
    }

    /// Health level → token color
    function healthLevelColor(level) {
        switch (String(level)) {
        case "excellent": return MissionTheme.success
        case "good":      return MissionTheme.primary
        case "attention": return MissionTheme.warning
        case "critical":  return MissionTheme.error
        default:          return MissionTheme.primary
        }
    }

    /// Number of dashboard cards
    readonly property int cardCount: root.dashboardCards.length

    /// Number of quick actions
    readonly property int actionCount: root.quickActions.length

    /// Number of recent activity items
    readonly property int activityCount: root.recentActivity.length

    /// Number of navigation items
    readonly property int navCount: root.navigationItems.length

    /// Whether the sidebar is expanded (wide layout)
    readonly property bool sidebarExpanded: root.width >= 768

    /// Number of columns in the dashboard card grid
    readonly property int cardColumns: root.width >= 960 ? 4 : (root.width >= 640 ? 2 : 1)

    /// Move keyboard focus to a navigation item
    function focusNavItem(index) {
        if (root.navigationItems.length === 0) return
        var count = root.navigationItems.length
        var target = ((index % count) + count) % count
        var item = navRepeater.itemAt(target)
        if (item !== null) item.forceActiveFocus()
    }

    /// Move keyboard focus to a card
    function focusCard(index) {
        if (root.dashboardCards.length === 0) return
        var count = root.dashboardCards.length
        var target = ((index % count) + count) % count
        var item = cardRepeater.itemAt(target)
        if (item !== null) item.forceActiveFocus()
    }

    /// Move keyboard focus to a quick action
    function focusAction(index) {
        if (root.quickActions.length === 0) return
        var count = root.quickActions.length
        var target = ((index % count) + count) % count
        var item = actionRepeater.itemAt(target)
        if (item !== null) item.forceActiveFocus()
    }

    // ── Test hooks (used by tests/tst_mission_hub_dashboard.qml) ──
    property alias headerBar: headerBar
    property alias titleLabel: titleLabel
    property alias sidebar: sidebar
    property alias navRepeater: navRepeater
    property alias mainContent: mainContent
    property alias healthScoreLabel: healthScoreValue
    property alias healthScoreValue: healthScoreValue
    property alias cardRepeater: cardRepeater
    property alias actionRepeater: actionRepeater
    property alias activityList: activityList
    property alias loadingIndicator: loadingIndicator
    property alias errorBanner: errorBanner
    property alias offlineBanner: offlineBanner
    property alias emptyHint: emptyHint

    // ══════════════════════════════════════════════════════════════
    // Background
    // ══════════════════════════════════════════════════════════════
    Rectangle {
        id: backgroundRect
        anchors.fill: parent
        color: MissionTheme.background
    }

    // ══════════════════════════════════════════════════════════════
    // Header
    // ══════════════════════════════════════════════════════════════
    Rectangle {
        id: headerBar
        objectName: "hubHeader"
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        height: Spacing.headerHeight
        color: MissionTheme.surface
        z: 2

        // Bottom hairline
        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }
            height: 1
            color: MissionTheme.outline
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Spacing.paddingPage
            anchors.rightMargin: Spacing.paddingPage
            spacing: Spacing.gapMedium

            // Logo mark
            Rectangle {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                Layout.alignment: Qt.AlignVCenter
                radius: Radii.radiusMd
                color: MissionTheme.primary
                Rectangle {
                    anchors.centerIn: parent
                    width: 14
                    height: 14
                    radius: 7
                    color: "transparent"
                    border.width: 2
                    border.color: MissionTheme.contentOnPrimary
                }
                Accessible.role: Accessible.Graphic
                Accessible.name: qsTr("Mission Hub logo")
            }

            // Title + version
            Column {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 0
                Label {
                    id: titleLabel
                    objectName: "hubTitle"
                    text: qsTr("Mission Hub")
                    font.pixelSize: Typography.title.size
                    font.weight: Typography.title.weight
                    color: MissionTheme.textPrimary
                    elide: Text.ElideRight
                    Accessible.role: Accessible.Heading
                    Accessible.name: text
                }
                Label {
                    text: qsTr("Version %1 · %2").arg(root.version).arg(root.buildType)
                    font.pixelSize: Typography.caption.size
                    color: MissionTheme.textSecondary
                }
            }

            // Right side: state indicator
            Label {
                id: stateLabel
                objectName: "hubState"
                text: root.screenState === "normal" ? "" :
                      root.screenState === "loading" ? qsTr("Loading…") :
                      root.screenState === "offline" ? qsTr("Offline") :
                      root.screenState === "error" ? qsTr("Error") : ""
                visible: text.length > 0
                font.pixelSize: Typography.bodySmall.size
                color: MissionTheme.textSecondary
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }
        }
    }

    // ══════════════════════════════════════════════════════════════
    // Sidebar navigation (persistent left-side per reference §8)
    // ══════════════════════════════════════════════════════════════
    Rectangle {
        id: sidebar
        objectName: "hubSidebar"
        anchors {
            left: parent.left
            top: headerBar.bottom
            bottom: parent.bottom
        }
        width: root.sidebarExpanded ? Spacing.sidebarWidth : 56
        color: MissionTheme.surface
        z: 1

        // Right hairline
        Rectangle {
            anchors {
                right: parent.right
                top: parent.top
                bottom: parent.bottom
            }
            width: 1
            color: MissionTheme.outline
        }

        Behavior on width {
            enabled: !root.reducedMotion
            animation: NumberAnimation { duration: Motion.durationFast }
        }

        Column {
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: Spacing.gapSmall
            }
            spacing: Spacing.gapTiny

            Repeater {
                id: navRepeater
                model: root.navigationItems

                delegate: Rectangle {
                    required property var modelData
                    required property int index

                    id: navItem
                    objectName: "navItem_" + modelData.id
                    width: parent.width
                    height: Spacing.minimumTouchTarget
                    radius: Radii.card
                    color: navItemMouse.containsMouse
                           ? MissionTheme.surfaceVariant
                           : (modelData.id === root.selectedNavId
                              ? MissionTheme.surfaceVariant
                              : "transparent")
                    activeFocusOnTab: true

                    Behavior on color {
                        enabled: !root.reducedMotion
                        animation: ColorAnimation { duration: Motion.colorChange }
                    }

                    // Visible focus ring
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -2
                        radius: Radii.card + 2
                        color: "transparent"
                        border.color: MissionTheme.focusRing
                        border.width: 2
                        visible: navItem.activeFocus
                    }

                    MouseArea {
                        id: navItemMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            navItem.forceActiveFocus()
                            root.selectedNavId = modelData.id
                            root.navigationActivated(modelData.id)
                        }
                    }

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: Spacing.paddingMedium
                        spacing: Spacing.gapSmall

                        // Selection indicator
                        Rectangle {
                            width: 3
                            height: navItem.height * 0.5
                            radius: 1.5
                            color: modelData.id === root.selectedNavId
                                   ? MissionTheme.primary : "transparent"
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Label {
                            text: root.navLabel(modelData)
                            font.pixelSize: Typography.body.size
                            font.weight: modelData.id === root.selectedNavId
                                         ? Typography.weightSemibold : Typography.weightRegular
                            color: modelData.id === root.selectedNavId
                                   ? MissionTheme.textPrimary : MissionTheme.textSecondary
                            elide: Text.ElideRight
                            visible: root.sidebarExpanded
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Accessible.role: Accessible.Button
                    Accessible.name: root.navLabel(modelData)
                    Accessible.selected: modelData.id === root.selectedNavId

                    Keys.onUpPressed: root.focusNavItem(index - 1)
                    Keys.onDownPressed: root.focusNavItem(index + 1)
                    Keys.onReturnPressed: {
                        root.selectedNavId = modelData.id
                        root.navigationActivated(modelData.id)
                    }
                    Keys.onSpacePressed: {
                        root.selectedNavId = modelData.id
                        root.navigationActivated(modelData.id)
                    }
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
        anchors {
            left: sidebar.right
            right: parent.right
            top: headerBar.bottom
            bottom: parent.bottom
        }
        clip: true
        contentHeight: contentColumn.implicitHeight
        interactive: contentHeight > height

        ScrollBar.vertical: ScrollBar {}

        Column {
            id: contentColumn
            width: mainContent.width
            spacing: Spacing.gapLarge

            // ── Loading state ──
            RowLayout {
                id: loadingIndicator
                objectName: "hubLoading"
                visible: root.screenState === "loading"
                width: parent.width
                anchors.leftMargin: Spacing.paddingPage
                anchors.rightMargin: Spacing.paddingPage
                spacing: Spacing.gapMedium
                Label {
                    text: qsTr("Loading system information…")
                    font.pixelSize: Typography.bodySmall.size
                    color: MissionTheme.textSecondary
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 4
                    radius: 2
                    color: MissionTheme.surfaceDim
                    Rectangle {
                        width: 96
                        height: 4
                        radius: 2
                        color: MissionTheme.primary
                        x: -96
                        NumberAnimation on x {
                            running: root.screenState === "loading" && !root.reducedMotion
                            from: -96
                            to: loadingIndicator.width
                            duration: Motion.durationSlow
                            loops: Animation.Infinite
                        }
                    }
                }
            }

            // ── Error state ──
            Rectangle {
                id: errorBanner
                objectName: "hubError"
                visible: root.screenState === "error"
                width: parent.width - Spacing.paddingPage * 2
                anchors.leftMargin: Spacing.paddingPage
                height: errorLayout.implicitHeight + Spacing.paddingMedium * 2
                radius: Radii.card
                color: Colors.errorContainer

                RowLayout {
                    id: errorLayout
                    anchors.fill: parent
                    anchors.margins: Spacing.paddingMedium
                    spacing: Spacing.gapMedium
                    Rectangle {
                        Layout.preferredWidth: 12
                        Layout.preferredHeight: 12
                        radius: 6
                        color: MissionTheme.error
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Spacing.gapTiny
                        Label {
                            text: qsTr("Could not load dashboard")
                            font.weight: Typography.weightSemibold
                            color: Colors.contentOnErrorContainer
                        }
                        Label {
                            text: qsTr("The system information could not be loaded. Check your system and try again.")
                            font.pixelSize: Typography.bodySmall.size
                            color: Colors.contentOnErrorContainer
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                        }
                    }
                }
            }

            // ── Offline state ──
            Rectangle {
                id: offlineBanner
                objectName: "hubOffline"
                visible: root.screenState === "offline"
                width: parent.width - Spacing.paddingPage * 2
                anchors.leftMargin: Spacing.paddingPage
                height: offlineLayout.implicitHeight + Spacing.paddingMedium * 2
                radius: Radii.card
                color: MissionTheme.surfaceVariant

                RowLayout {
                    id: offlineLayout
                    anchors.fill: parent
                    anchors.margins: Spacing.paddingMedium
                    spacing: Spacing.gapMedium
                    Rectangle {
                        Layout.preferredWidth: 12
                        Layout.preferredHeight: 12
                        radius: 6
                        color: MissionTheme.textSecondary
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Spacing.gapTiny
                        Label {
                            text: qsTr("You're offline")
                            font.weight: Typography.weightSemibold
                            color: MissionTheme.textPrimary
                        }
                        Label {
                            text: qsTr("Mission Hub works fully offline — most features are available without an internet connection.")
                            font.pixelSize: Typography.bodySmall.size
                            color: MissionTheme.textSecondary
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                        }
                    }
                }
            }

            // ── Empty state ──
            Column {
                id: emptyHint
                objectName: "hubEmpty"
                visible: root.screenState === "empty"
                width: parent.width
                spacing: Spacing.gapSmall
                Label {
                    width: parent.width
                    text: qsTr("No dashboard data available")
                    font.pixelSize: Typography.body.size
                    font.weight: Typography.weightSemibold
                    color: MissionTheme.textPrimary
                    wrapMode: Text.WordWrap
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }
                Label {
                    width: parent.width
                    text: qsTr("System information will appear here once the host provides dashboard data.")
                    font.pixelSize: Typography.bodySmall.size
                    color: MissionTheme.textSecondary
                    wrapMode: Text.WordWrap
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }
            }

            // ══════════════════════════════════════════════════════
            // Normal content (visible when state is "normal")
            // ══════════════════════════════════════════════════════
            Column {
                visible: root.screenState === "normal"
                width: parent.width
                spacing: Spacing.gapLarge

                // ── System Health Score ──
                Rectangle {
                    width: parent.width - Spacing.paddingPage * 2
                    anchors.leftMargin: Spacing.paddingPage
                    height: healthColumn.implicitHeight + Spacing.paddingLarge * 2
                    radius: Radii.card
                    color: MissionTheme.surface
                    border.color: MissionTheme.outlineVariant
                    border.width: 1

                    Column {
                        id: healthColumn
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            margins: Spacing.paddingLarge
                        }
                        spacing: Spacing.gapSmall

                        Label {
                            text: qsTr("System Health")
                            font.pixelSize: Typography.subtitle.size
                            font.weight: Typography.subtitle.weight
                            color: MissionTheme.textPrimary
                            Accessible.role: Accessible.Heading
                            Accessible.name: text
                        }

                        RowLayout {
                            width: parent.width
                            spacing: Spacing.gapMedium

                            // Score circle
                            Rectangle {
                                Layout.preferredWidth: 64
                                Layout.preferredHeight: 64
                                radius: 32
                                color: "transparent"
                                border.color: root.healthLevelColor(root.healthScore.level)
                                border.width: 3

                                Label {
                                    id: healthScoreValue
                                    anchors.centerIn: parent
                                    text: root.healthScore.score !== undefined
                                          ? String(root.healthScore.score) : "—"
                                    font.pixelSize: Typography.title.size
                                    font.weight: Typography.title.weight
                                    color: root.healthLevelColor(root.healthScore.level)
                                    Accessible.role: Accessible.StaticText
                                    Accessible.name: qsTr("Health score: %1").arg(text)
                                }
                            }

                            Column {
                                spacing: Spacing.gapTiny
                                Label {
                                    id: healthScoreLabel
                                    text: root.healthLevelLabel(root.healthScore.level)
                                    font.pixelSize: Typography.bodyLarge.size
                                    font.weight: Typography.weightSemibold
                                    color: MissionTheme.textPrimary
                                }
                                Label {
                                    text: qsTr("Overall system health assessment")
                                    font.pixelSize: Typography.bodySmall.size
                                    color: MissionTheme.textSecondary
                                }
                            }
                        }
                    }
                }

                // ── Dashboard Cards Grid ──
                Column {
                    width: parent.width
                    spacing: Spacing.gapMedium

                    Label {
                        text: qsTr("Overview")
                        font.pixelSize: Typography.subtitle.size
                        font.weight: Typography.subtitle.weight
                        color: MissionTheme.textPrimary
                        anchors.leftMargin: Spacing.paddingPage
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    Grid {
                        width: parent.width
                        columns: root.cardColumns
                        spacing: Spacing.gapMedium

                        Repeater {
                            id: cardRepeater
                            model: root.dashboardCards

                            delegate: Rectangle {
                                required property var modelData
                                required property int index

                                id: card
                                objectName: "card_" + modelData.id
                                width: root.cardColumns >= 4
                                       ? (root.width - Spacing.paddingPage * 2 - Spacing.gapMedium * 3) / 4
                                       : (root.cardColumns >= 2
                                          ? (root.width - Spacing.paddingPage * 2 - Spacing.gapMedium) / 2
                                          : root.width - Spacing.paddingPage * 2)
                                height: cardColumn.implicitHeight + Spacing.paddingMedium * 2
                                radius: Radii.card
                                color: cardMouse.containsMouse
                                       ? MissionTheme.surfaceVariant : MissionTheme.surface
                                border.color: MissionTheme.outlineVariant
                                border.width: 1
                                activeFocusOnTab: true

                                Behavior on color {
                                    enabled: !root.reducedMotion
                                    animation: ColorAnimation { duration: Motion.colorChange }
                                }

                                // Focus ring
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: -2
                                    radius: Radii.card + 2
                                    color: "transparent"
                                    border.color: MissionTheme.focusRing
                                    border.width: 2
                                    visible: card.activeFocus
                                }

                                MouseArea {
                                    id: cardMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        card.forceActiveFocus()
                                        root.cardActivated(modelData.id)
                                    }
                                }

                                Column {
                                    id: cardColumn
                                    anchors {
                                        left: parent.left
                                        right: parent.right
                                        top: parent.top
                                        margins: Spacing.paddingMedium
                                    }
                                    spacing: Spacing.gapTiny

                                    // Status dot + level
                                    Row {
                                        spacing: Spacing.gapTiny
                                        Rectangle {
                                            width: 8
                                            height: 8
                                            radius: 4
                                            color: root.cardLevelColor(modelData.level)
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Label {
                                            text: modelData.status !== undefined
                                                  ? String(modelData.status) : ""
                                            font.pixelSize: Typography.caption.size
                                            color: MissionTheme.textSecondary
                                            visible: text.length > 0
                                        }
                                    }

                                    // Card label
                                    Label {
                                        text: modelData.label !== undefined
                                              ? String(modelData.label) : String(modelData.id)
                                        font.pixelSize: Typography.body.size
                                        font.weight: Typography.weightSemibold
                                        color: MissionTheme.textPrimary
                                        elide: Text.ElideRight
                                    }

                                    // Description (if present)
                                    Label {
                                        visible: modelData.description !== undefined
                                                 && String(modelData.description).length > 0
                                        text: modelData.description !== undefined
                                              ? String(modelData.description) : ""
                                        font.pixelSize: Typography.bodySmall.size
                                        color: MissionTheme.textTertiary
                                        wrapMode: Text.Wrap
                                        width: parent.width
                                    }
                                }

                                Accessible.role: Accessible.Button
                                Accessible.name: qsTr("%1: %2").arg(
                                    modelData.label !== undefined ? modelData.label : modelData.id
                                ).arg(modelData.status !== undefined ? modelData.status : "")

                                Keys.onUpPressed: root.focusCard(index - root.cardColumns)
                                Keys.onDownPressed: root.focusCard(index + root.cardColumns)
                                Keys.onLeftPressed: root.focusCard(index - 1)
                                Keys.onRightPressed: root.focusCard(index + 1)
                                Keys.onReturnPressed: root.cardActivated(modelData.id)
                                Keys.onSpacePressed: root.cardActivated(modelData.id)
                            }
                        }
                    }
                }

                // ── Quick Actions ──
                Column {
                    width: parent.width
                    spacing: Spacing.gapMedium

                    Label {
                        text: qsTr("Quick Actions")
                        font.pixelSize: Typography.subtitle.size
                        font.weight: Typography.subtitle.weight
                        color: MissionTheme.textPrimary
                        anchors.leftMargin: Spacing.paddingPage
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    Flow {
                        width: parent.width
                        anchors.leftMargin: Spacing.paddingPage
                        anchors.rightMargin: Spacing.paddingPage
                        spacing: Spacing.gapSmall

                        Repeater {
                            id: actionRepeater
                            model: root.quickActions

                            delegate: MissionButton {
                                required property var modelData
                                required property int index

                                objectName: "action_" + modelData.id
                                variant: MissionButton.Variant.Secondary
                                text: modelData.label !== undefined
                                      ? String(modelData.label) : String(modelData.id)
                                onClicked: root.quickActionActivated(modelData.id)
                            }
                        }
                    }
                }

                // ── Recent Activity ──
                Column {
                    visible: root.activityCount > 0
                    width: parent.width
                    spacing: Spacing.gapMedium

                    Label {
                        text: qsTr("Recent Activity")
                        font.pixelSize: Typography.subtitle.size
                        font.weight: Typography.subtitle.weight
                        color: MissionTheme.textPrimary
                        anchors.leftMargin: Spacing.paddingPage
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    Repeater {
                        id: activityList
                        model: root.recentActivity

                        delegate: Rectangle {
                            required property var modelData
                            required property int index

                            objectName: "activity_" + modelData.id
                            width: parent.width - Spacing.paddingPage * 2
                            anchors.leftMargin: Spacing.paddingPage
                            height: activityColumn.implicitHeight + Spacing.paddingMedium * 2
                            radius: Radii.card
                            color: MissionTheme.surface
                            border.color: MissionTheme.outlineVariant
                            border.width: 1
                            activeFocusOnTab: true

                            // Focus ring
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: -2
                                radius: Radii.card + 2
                                color: "transparent"
                                border.color: MissionTheme.focusRing
                                border.width: 2
                                visible: parent.activeFocus
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    parent.forceActiveFocus()
                                    root.activityActivated(modelData.id)
                                }
                            }

                            Column {
                                id: activityColumn
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    top: parent.top
                                    margins: Spacing.paddingMedium
                                }
                                spacing: Spacing.gapTiny

                                Label {
                                    text: modelData.title !== undefined
                                          ? String(modelData.title) : ""
                                    font.pixelSize: Typography.body.size
                                    font.weight: Typography.weightSemibold
                                    color: MissionTheme.textPrimary
                                    elide: Text.ElideRight
                                }
                                Label {
                                    visible: modelData.description !== undefined
                                             && String(modelData.description).length > 0
                                    text: modelData.description !== undefined
                                          ? String(modelData.description) : ""
                                    font.pixelSize: Typography.bodySmall.size
                                    color: MissionTheme.textSecondary
                                    wrapMode: Text.Wrap
                                    width: parent.width
                                }
                                Label {
                                    visible: modelData.timestamp !== undefined
                                             && String(modelData.timestamp).length > 0
                                    text: modelData.timestamp !== undefined
                                          ? String(modelData.timestamp) : ""
                                    font.pixelSize: Typography.caption.size
                                    color: MissionTheme.textTertiary
                                }
                            }

                            Accessible.role: Accessible.Button
                            Accessible.name: modelData.title !== undefined
                                              ? String(modelData.title) : ""

                            Keys.onReturnPressed: root.activityActivated(modelData.id)
                            Keys.onSpacePressed: root.activityActivated(modelData.id)
                        }
                    }
                }

                // ── Bottom spacer ──
                Item { width: 1; height: Spacing.paddingLarge }
            }
        }
    }
}
