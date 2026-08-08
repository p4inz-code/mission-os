// Mission OS — Mission Hub Applications (MOS-HUB-003)
//
// Third screen of the Mission Hub family. Implements the source-defined
// Applications structure (docs/design/03_SCREEN_REGISTRY.md MOS-HUB-003
// "Applications", docs/reference/03_MISSION_HUB.md §11 Application
// Structure, docs/design/01_INFORMATION_ARCHITECTURE.md §5 Mission Hub
// Structure, docs/design/04_USER_FLOWS.md §5 Launch Application,
// §6 Install Application):
//
//   Hosting: a full-screen application within Mission Hub. The host
//   opens this from the Mission Hub sidebar. Place inside MissionWindow
//   content and anchor to fill, e.g.
//   MissionWindow { MissionHubApplications { anchors.fill: parent } }
//   The component sizes to its implicit 1280x720 like Desktop.qml.
//
//   Layout (Master UX Specification §3):
//     Header → Sidebar Navigation → Main Content Area
//
//   Application Structure (reference §11):
//     Applications: Mission Store, File Manager, Terminal, Text Editor,
//     Image Viewer, Archive Manager, Calculator, Screenshot, Media
//     Player, Settings
//
//   User Flow §5 (Launch Application):
//     Desktop → Mission Hub → Search → Select App → Launch
//   User Flow §6 (Install Application):
//     Mission Hub → Mission Store → Search → Application → Install →
//     Verify → Launch
//
//   Mission Hub Structure (information architecture §5):
//     Mission Hub → Applications (one of: Home, Applications, Search,
//     Updates, Security, Privacy, Recovery, Diagnostics, Devices,
//     Storage, Network, Settings)
//
// Interpretation notes (documented — no authoritative source specifies
// further detail):
//   - The sidebar is persistent on wide layouts (≥768px) and collapses
//     to an icon rail on narrow layouts (established Mission Hub
//     pattern from MOS-HUB-001 Dashboard).
//   - Applications are host-driven: each entry is
//     { id, name, description?, version?, status?, icon?, category? }.
//     status ∈ "installed" | "available" | "updating" | "error".
//     category ∈ "system" | "productivity" | "development" | "media" |
//     "utilities" (reference §11 application categories). The screen
//     never mutates the model — activation emits applicationActivated(id).
//   - Search/filter is local to the screen: the user types a query and
//     selects a category; matching applications are displayed. The host
//     supplies the full application model; the screen filters locally.
//   - Application actions emit host-facing signals rather than performing
//     operations directly (same contract as all Mission Hub screens).
//   - Escape is deliberately unmapped: the host owns window-level
//     dismissal (same contract as all Mission Hub screens).
//   - Offline state shows a neutral message — Mission Hub works fully
//     offline (reference §2: "function fully offline except where
//     Internet access is explicitly required").
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

    /// Current search query (user-editable; local filtering)
    property string query: ""

    /// Applications model: [{ id, name, description?, version?, status?, icon?, category? }]
    /// status ∈ "installed" | "available" | "updating" | "error"
    /// category ∈ "system" | "productivity" | "development" | "media" | "utilities"
    property var applications: []

    /// Category filters: [{ id, label }]
    property var categories: [
        { id: "all",           label: "All" },
        { id: "system",        label: "System" },
        { id: "productivity",  label: "Productivity" },
        { id: "development",   label: "Development" },
        { id: "media",         label: "Media" },
        { id: "utilities",     label: "Utilities" }
    ]

    /// Currently selected category filter id
    property string selectedCategoryId: "all"

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
        { id: "settings",    label: "Settings" },
        { id: "applications", label: "Applications" }
    ]

    /// Currently selected navigation item id
    property string selectedNavId: "applications"

    // ── Signals (host wiring) ──────────────────────────────────────
    /// User activated an application (host opens or installs it)
    signal applicationActivated(string appId)
    /// User activated a category filter (host applies the filter)
    signal categoryActivated(string categoryId)
    /// User activated a navigation item (host opens the screen)
    signal navigationActivated(string navId)

    // Escape is deliberately unmapped (see interpretation notes): the
    // host owns window-level dismissal.

    // ── Derived helpers ────────────────────────────────────────────
    /// Whether the user has typed a (non-whitespace) query
    readonly property bool hasQuery: root.query.trim().length > 0

    /// Number of applications in the host model
    readonly property int appCount: root.applications.length

    /// Filtered applications based on query and category.
    /// Uses a function call in bindings so QML tracks the property
    /// accesses (query, applications, selectedCategoryId) and
    /// re-evaluates reactively.
    function getFilteredApps() {
        var apps = root.applications
        if (root.selectedCategoryId !== "all") {
            var filtered = []
            for (var i = 0; i < apps.length; i++) {
                if (apps[i].category === root.selectedCategoryId)
                    filtered.push(apps[i])
            }
            apps = filtered
        }
        if (root.hasQuery) {
            var q = root.query.trim().toLowerCase()
            var searchFiltered = []
            for (var j = 0; j < apps.length; j++) {
                var name = apps[j].name !== undefined ? String(apps[j].name).toLowerCase() : ""
                var desc = apps[j].description !== undefined ? String(apps[j].description).toLowerCase() : ""
                if (name.indexOf(q) >= 0 || desc.indexOf(q) >= 0)
                    searchFiltered.push(apps[j])
            }
            apps = searchFiltered
        }
        return apps
    }

    /// Number of filtered applications
    readonly property int filteredCount: root.getFilteredApps().length

    /// Number of category filters
    readonly property int categoryCount: root.categories.length

    /// Number of navigation items
    readonly property int navCount: root.navigationItems.length

    /// Whether the sidebar is expanded (wide layout)
    readonly property bool sidebarExpanded: root.width >= 768

    /// Number of columns in the application grid
    readonly property int appColumns: root.width >= 960 ? 3 : (root.width >= 640 ? 2 : 1)

    /// Display label for a navigation item (falls back to id)
    function navLabel(item) {
        if (item === null || item === undefined) return ""
        var l = item.label !== undefined ? String(item.label) : ""
        return l.length > 0 ? l : String(item.id)
    }

    /// Display label for a category (falls back to id)
    function categoryLabel(item) {
        if (item === null || item === undefined) return ""
        var l = item.label !== undefined ? String(item.label) : ""
        return l.length > 0 ? l : String(item.id)
    }

    /// Status → display label
    function statusLabel(status) {
        switch (String(status)) {
        case "installed": return qsTr("Installed")
        case "available": return qsTr("Available")
        case "updating":  return qsTr("Updating")
        case "error":     return qsTr("Error")
        default:          return ""
        }
    }

    /// Status → token color
    function statusColor(status) {
        switch (String(status)) {
        case "installed": return MissionTheme.success
        case "available": return MissionTheme.primary
        case "updating":  return MissionTheme.warning
        case "error":     return MissionTheme.error
        default:          return MissionTheme.textSecondary
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

    /// Move keyboard focus to an application card
    function focusApp(index) {
        var filtered = root.getFilteredApps()
        if (filtered.length === 0) return
        var count = filtered.length
        var target = ((index % count) + count) % count
        var item = appRepeater.itemAt(target)
        if (item !== null) item.forceActiveFocus()
    }

    /// Move keyboard focus to a category filter
    function focusCategory(index) {
        if (root.categories.length === 0) return
        var count = root.categories.length
        var target = ((index % count) + count) % count
        var item = categoryRepeater.itemAt(target)
        if (item !== null) item.forceActiveFocus()
    }

    // ── Test hooks (used by tests/tst_mission_hub_applications.qml) ──
    property alias headerBar: headerBar
    property alias titleLabel: titleLabel
    property alias sidebar: sidebar
    property alias navRepeater: navRepeater
    property alias mainContent: mainContent
    property alias searchField: searchField
    property alias categoryRepeater: categoryRepeater
    property alias appRepeater: appRepeater
    property alias loadingIndicator: loadingIndicator
    property alias errorBanner: errorBanner
    property alias offlineBanner: offlineBanner
    property alias emptyHint: emptyHint
    property alias noQueryHint: noQueryHint
    property alias noResultsHint: noResultsHint

    // ══════════════════════════════════════════════════════════════
    // Background
    // ══════════════════════════════════════════════════════════════
    Rectangle {
        id: backgroundRect
        anchors.fill: parent
        color: MissionTheme.background
    }

    // ══════════════════════════════════════════════════════════════
    // Header (Mission Hub pattern from MOS-HUB-001)
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

            Rectangle {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                Layout.alignment: Qt.AlignVCenter
                radius: Radii.radiusMd
                color: MissionTheme.primary
                Rectangle {
                    anchors.centerIn: parent
                    width: 14; height: 14; radius: 7
                    color: "transparent"
                    border.width: 2
                    border.color: MissionTheme.contentOnPrimary
                }
                Accessible.role: Accessible.Graphic
                Accessible.name: qsTr("Mission Hub logo")
            }

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
                              ? MissionTheme.surfaceVariant : "transparent")
                    activeFocusOnTab: true

                    Behavior on color {
                        enabled: !root.reducedMotion
                        animation: ColorAnimation { duration: Motion.colorChange }
                    }

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
                spacing: Spacing.gapMedium
                Item { width: Spacing.paddingPage; height: 1 }
                Label {
                    text: qsTr("Loading applications…")
                    font.pixelSize: Typography.bodySmall.size
                    color: MissionTheme.textSecondary
                }
                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: 4; radius: 2
                    color: MissionTheme.surfaceDim
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
                id: errorBanner
                objectName: "hubError"
                visible: root.screenState === "error"
                width: parent.width - Spacing.paddingPage * 2
                anchors.leftMargin: Spacing.paddingPage
                height: errorLayout.implicitHeight + Spacing.paddingMedium * 2
                radius: Radii.card; color: Colors.errorContainer
                RowLayout {
                    id: errorLayout
                    anchors.fill: parent; anchors.margins: Spacing.paddingMedium
                    spacing: Spacing.gapMedium
                    Rectangle { Layout.preferredWidth: 12; Layout.preferredHeight: 12; radius: 6; color: MissionTheme.error }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: Spacing.gapTiny
                        Label { text: qsTr("Could not load applications"); font.weight: Typography.weightSemibold; color: Colors.contentOnErrorContainer }
                        Label { text: qsTr("The application list could not be loaded. Check your system and try again."); font.pixelSize: Typography.bodySmall.size; color: Colors.contentOnErrorContainer; wrapMode: Text.Wrap; Layout.fillWidth: true }
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
                radius: Radii.card; color: MissionTheme.surfaceVariant
                RowLayout {
                    id: offlineLayout
                    anchors.fill: parent; anchors.margins: Spacing.paddingMedium
                    spacing: Spacing.gapMedium
                    Rectangle { Layout.preferredWidth: 12; Layout.preferredHeight: 12; radius: 6; color: MissionTheme.textSecondary }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: Spacing.gapTiny
                        Label { text: qsTr("You're offline"); font.weight: Typography.weightSemibold; color: MissionTheme.textPrimary }
                        Label { text: qsTr("Installed applications are available offline. Some features may require an internet connection."); font.pixelSize: Typography.bodySmall.size; color: MissionTheme.textSecondary; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    }
                }
            }

            // ── Empty state ──
            Column {
                id: emptyHint
                objectName: "hubEmpty"
                visible: root.screenState === "empty"
                width: parent.width; spacing: Spacing.gapSmall
                Label { width: parent.width; text: qsTr("No applications available"); font.pixelSize: Typography.body.size; font.weight: Typography.weightSemibold; color: MissionTheme.textPrimary; wrapMode: Text.WordWrap; Accessible.role: Accessible.StaticText; Accessible.name: text }
                Label { width: parent.width; text: qsTr("Applications will appear here once the host provides application data."); font.pixelSize: Typography.bodySmall.size; color: MissionTheme.textSecondary; wrapMode: Text.WordWrap; Accessible.role: Accessible.StaticText; Accessible.name: text }
            }

            // ══════════════════════════════════════════════════════
            // Normal content
            // ══════════════════════════════════════════════════════
            Column {
                visible: root.screenState === "normal"
                width: parent.width
                spacing: Spacing.gapMedium

                // ── Screen title ──
                Label {
                    text: qsTr("Applications")
                    font.pixelSize: Typography.headline.size
                    font.weight: Typography.headline.weight
                    color: MissionTheme.textPrimary
                    anchors.leftMargin: Spacing.paddingPage
                    Accessible.role: Accessible.Heading
                    Accessible.name: text
                }

                // ── Search field ──
                Item {
                    width: parent.width
                    height: searchField.height + Spacing.paddingSmall * 2
                    TextField {
                        id: searchField
                        objectName: "appSearchField"
                        anchors {
                            left: parent.left; right: parent.right
                            top: parent.top; margins: Spacing.paddingPage
                        }
                        text: root.query
                        onTextChanged: { if (text !== root.query) root.query = text }
                        placeholderText: qsTr("Search applications…")
                        font.pixelSize: Typography.bodyLarge.size
                        color: MissionTheme.textPrimary
                        placeholderTextColor: MissionTheme.textTertiary
                        selectByMouse: true
                        leftPadding: Spacing.paddingLarge + 20 + Spacing.gapSmall
                        rightPadding: Spacing.paddingLarge
                        background: Rectangle {
                            radius: Radii.input
                            color: MissionTheme.surface
                            border.width: searchField.activeFocus ? 2 : 1
                            border.color: searchField.activeFocus ? MissionTheme.focusRing : MissionTheme.outline
                        }
                        Accessible.role: Accessible.EditableText
                        Accessible.name: qsTr("Search applications")
                        Accessible.description: qsTr("Type to search installed and available applications")
                    }
                    Rectangle {
                        anchors.verticalCenter: searchField.verticalCenter
                        anchors.left: searchField.left
                        anchors.leftMargin: Spacing.paddingMedium
                        width: 20; height: 20; radius: 4; color: "transparent"
                        Label {
                            anchors.centerIn: parent
                            text: "🔍"; font.pixelSize: Typography.body.size
                            color: MissionTheme.textSecondary
                        }
                        Accessible.role: Accessible.Graphic
                        Accessible.name: qsTr("Search icon")
                    }
                }

                // ── Category filters ──
                Flow {
                    width: parent.width
                    spacing: Spacing.gapSmall
                    leftPadding: Spacing.paddingPage; rightPadding: Spacing.paddingPage

                    Repeater {
                        id: categoryRepeater
                        model: root.categories

                        delegate: Rectangle {
                            required property var modelData
                            required property int index

                            id: catChip
                            objectName: "cat_" + modelData.id
                            height: Spacing.minimumTouchTarget
                            width: catLabel.implicitWidth + Spacing.paddingMedium * 2
                            radius: Radii.chip
                            color: catChipMouse.containsMouse
                                   ? MissionTheme.surfaceVariant
                                   : (modelData.id === root.selectedCategoryId
                                      ? MissionTheme.primary : MissionTheme.surface)
                            border.width: 1
                            border.color: modelData.id === root.selectedCategoryId
                                          ? MissionTheme.primary : MissionTheme.outlineVariant
                            activeFocusOnTab: true

                            Behavior on color {
                                enabled: !root.reducedMotion
                                animation: ColorAnimation { duration: Motion.colorChange }
                            }

                            Rectangle {
                                anchors.fill: parent; anchors.margins: -2
                                radius: Radii.chip + 2; color: "transparent"
                                border.color: MissionTheme.focusRing; border.width: 2
                                visible: catChip.activeFocus
                            }

                            MouseArea {
                                id: catChipMouse
                                anchors.fill: parent; hoverEnabled: true
                                onClicked: {
                                    catChip.forceActiveFocus()
                                    root.selectedCategoryId = modelData.id
                                    root.categoryActivated(modelData.id)
                                }
                            }

                            Label {
                                id: catLabel
                                anchors.centerIn: parent
                                text: root.categoryLabel(modelData)
                                font.pixelSize: Typography.bodySmall.size
                                font.weight: modelData.id === root.selectedCategoryId
                                             ? Typography.weightSemibold : Typography.weightRegular
                                color: modelData.id === root.selectedCategoryId
                                       ? MissionTheme.contentOnPrimary : MissionTheme.textPrimary
                            }

                            Accessible.role: Accessible.Button
                            Accessible.name: root.categoryLabel(modelData)
                            Accessible.selected: modelData.id === root.selectedCategoryId

                            Keys.onLeftPressed: root.focusCategory(index - 1)
                            Keys.onRightPressed: root.focusCategory(index + 1)
                            Keys.onReturnPressed: {
                                root.selectedCategoryId = modelData.id
                                root.categoryActivated(modelData.id)
                            }
                            Keys.onSpacePressed: {
                                root.selectedCategoryId = modelData.id
                                root.categoryActivated(modelData.id)
                            }
                        }
                    }
                }

                // ── No query hint ──
                Column {
                    id: noQueryHint
                    objectName: "noQueryHint"
                    visible: !root.hasQuery && root.appCount === 0 && root.screenState === "normal"
                    width: parent.width
                    spacing: Spacing.gapSmall
                    Label {
                        width: parent.width
                        text: qsTr("No applications to display")
                        font.pixelSize: Typography.body.size
                        font.weight: Typography.weightSemibold
                        color: MissionTheme.textPrimary
                        wrapMode: Text.WordWrap
                        anchors.leftMargin: Spacing.paddingPage
                        Accessible.role: Accessible.StaticText
                        Accessible.name: text
                    }
                    Label {
                        width: parent.width
                        text: qsTr("The host has not provided any application data yet.")
                        font.pixelSize: Typography.bodySmall.size
                        color: MissionTheme.textSecondary
                        wrapMode: Text.WordWrap
                        anchors.leftMargin: Spacing.paddingPage
                        Accessible.role: Accessible.StaticText
                        Accessible.name: text
                    }
                }

                // ── No results hint (when search/filter yields nothing) ──
                Column {
                    id: noResultsHint
                    objectName: "noResultsHint"
                    visible: root.screenState === "normal" && root.appCount > 0 && root.filteredCount === 0
                    width: parent.width
                    spacing: Spacing.gapSmall
                    Label {
                        width: parent.width
                        text: qsTr("No applications match your search")
                        font.pixelSize: Typography.body.size
                        font.weight: Typography.weightSemibold
                        color: MissionTheme.textPrimary
                        wrapMode: Text.WordWrap
                        anchors.leftMargin: Spacing.paddingPage
                        Accessible.role: Accessible.StaticText
                        Accessible.name: text
                    }
                    Label {
                        width: parent.width
                        text: qsTr("Try a different search term or category filter.")
                        font.pixelSize: Typography.bodySmall.size
                        color: MissionTheme.textSecondary
                        wrapMode: Text.WordWrap
                        anchors.leftMargin: Spacing.paddingPage
                        Accessible.role: Accessible.StaticText
                        Accessible.name: text
                    }
                }

                // ── Results count ──
                Label {
                    visible: root.screenState === "normal" && root.filteredCount > 0
                    text: qsTr("%1 application%2").arg(root.filteredCount).arg(root.filteredCount !== 1 ? "s" : "")
                    font.pixelSize: Typography.caption.size
                    color: MissionTheme.textSecondary
                    anchors.leftMargin: Spacing.paddingPage
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }

                // ── Application grid ──
                Grid {
                    visible: root.screenState === "normal" && root.filteredCount > 0
                    width: parent.width
                    columns: root.appColumns
                    spacing: Spacing.gapMedium

                    Repeater {
                        id: appRepeater
                        model: root.getFilteredApps()

                        delegate: Rectangle {
                            required property var modelData
                            required property int index

                            id: appCard
                            objectName: "app_" + modelData.id
                            width: root.appColumns >= 3
                                   ? (root.width - Spacing.paddingPage * 2 - Spacing.gapMedium * 2) / 3
                                   : (root.appColumns >= 2
                                      ? (root.width - Spacing.paddingPage * 2 - Spacing.gapMedium) / 2
                                      : root.width - Spacing.paddingPage * 2)
                            height: appCardColumn.implicitHeight + Spacing.paddingMedium * 2
                            radius: Radii.card
                            color: appCardMouse.containsMouse
                                   ? MissionTheme.surfaceVariant : MissionTheme.surface
                            border.color: MissionTheme.outlineVariant
                            border.width: 1
                            activeFocusOnTab: true

                            Behavior on color {
                                enabled: !root.reducedMotion
                                animation: ColorAnimation { duration: Motion.colorChange }
                            }

                            Rectangle {
                                anchors.fill: parent; anchors.margins: -2
                                radius: Radii.card + 2; color: "transparent"
                                border.color: MissionTheme.focusRing; border.width: 2
                                visible: appCard.activeFocus
                            }

                            MouseArea {
                                id: appCardMouse
                                anchors.fill: parent; hoverEnabled: true
                                onClicked: {
                                    appCard.forceActiveFocus()
                                    root.applicationActivated(String(modelData.id))
                                }
                            }

                            Column {
                                id: appCardColumn
                                anchors {
                                    left: parent.left; right: parent.right
                                    top: parent.top; margins: Spacing.paddingMedium
                                }
                                spacing: Spacing.gapTiny

                                // Status dot + label
                                Row {
                                    spacing: Spacing.gapTiny
                                    Rectangle {
                                        width: 8; height: 8; radius: 4
                                        color: root.statusColor(modelData.status)
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Label {
                                        text: root.statusLabel(modelData.status)
                                        font.pixelSize: Typography.caption.size
                                        color: MissionTheme.textSecondary
                                        visible: text.length > 0
                                    }
                                }

                                // App name
                                Label {
                                    text: modelData.name !== undefined
                                          ? String(modelData.name) : String(modelData.id)
                                    font.pixelSize: Typography.body.size
                                    font.weight: Typography.weightSemibold
                                    color: MissionTheme.textPrimary
                                    elide: Text.ElideRight
                                    width: parent.width
                                }

                                // Description
                                Label {
                                    visible: modelData.description !== undefined
                                             && String(modelData.description).length > 0
                                    text: modelData.description !== undefined
                                          ? String(modelData.description) : ""
                                    font.pixelSize: Typography.bodySmall.size
                                    color: MissionTheme.textTertiary
                                    wrapMode: Text.Wrap
                                    width: parent.width
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }

                                // Version
                                Label {
                                    visible: modelData.version !== undefined
                                             && String(modelData.version).length > 0
                                    text: qsTr("v%1").arg(modelData.version)
                                    font.pixelSize: Typography.caption.size
                                    color: MissionTheme.textTertiary
                                }

                                // Category tag
                                Rectangle {
                                    visible: modelData.category !== undefined
                                             && String(modelData.category).length > 0
                                    width: appCatLabel.implicitWidth + Spacing.paddingSmall * 2
                                    height: Spacing.gapMedium
                                    radius: Radii.chip
                                    color: MissionTheme.surfaceVariant
                                    Label {
                                        id: appCatLabel
                                        anchors.centerIn: parent
                                        text: modelData.category !== undefined
                                              ? String(modelData.category) : ""
                                        font.pixelSize: Typography.caption.size
                                        color: MissionTheme.textSecondary
                                    }
                                }
                            }

                            Accessible.role: Accessible.Button
                            Accessible.name: qsTr("%1: %2").arg(
                                modelData.name !== undefined ? modelData.name : modelData.id
                            ).arg(root.statusLabel(modelData.status))

                            Keys.onUpPressed: root.focusApp(index - root.appColumns)
                            Keys.onDownPressed: root.focusApp(index + root.appColumns)
                            Keys.onLeftPressed: root.focusApp(index - 1)
                            Keys.onRightPressed: root.focusApp(index + 1)
                            Keys.onReturnPressed: root.applicationActivated(String(modelData.id))
                            Keys.onSpacePressed: root.applicationActivated(String(modelData.id))
                        }
                    }
                }

                // ── Bottom spacer ──
                Item { width: 1; height: Spacing.paddingLarge }
            }
        }
    }
}
