// Mission OS — Mission Hub Search (MOS-HUB-002)
//
// Second screen of the Mission Hub family. Implements the source-defined
// Search structure (docs/design/03_SCREEN_REGISTRY.md MOS-HUB-002
// "Search", docs/reference/03_MISSION_HUB.md §9 Search, docs/design/
// 01_INFORMATION_ARCHITECTURE.md §5 Mission Hub Structure):
//
//   Hosting: a full-screen application within Mission Hub (not an
//   overlay like the Desktop family's MOS-DES-005 Search). The host
//   opens this from the Mission Hub sidebar or from the Dashboard's
//   global search entry point. Place inside MissionWindow content and
//   anchor to fill, e.g.
//   MissionWindow { MissionHubSearch { anchors.fill: parent } }
//   The component sizes to its implicit 1280x720 like Desktop.qml.
//
//   Layout (Master UX Specification §3):
//     Header → Sidebar Navigation → Main Content Area
//
//   Search (reference §9):
//     Searchable items: settings, features, devices, documentation,
//     troubleshooting articles, installed drivers, update history, logs.
//     "Search should function offline whenever possible."
//
//   Mission Hub Structure (information architecture §5):
//     Mission Hub → Search (one of: Home, Applications, Search,
//     Updates, Security, Privacy, Recovery, Diagnostics, Devices,
//     Storage, Network, Settings)
//
//   This screen is DIFFERENT from Desktop Search (MOS-DES-005):
//     - Desktop Search is a centered overlay with scrim backdrop
//     - Mission Hub Search is a full-screen application with sidebar
//     - Desktop Search searches apps/files/settings/commands/documents
//     - Mission Hub Search searches settings/features/devices/drivers/
//       documentation/update history/logs (reference §9)
//     - Desktop Search has no sidebar navigation
//     - Mission Hub Search has persistent Mission Hub sidebar
//
// Interpretation notes (documented — no authoritative source specifies
// further detail):
//   - The sidebar is persistent on wide layouts (≥768px) and collapses
//     to an icon rail on narrow layouts (established Mission Hub
//     pattern from MOS-HUB-001 Dashboard).
//   - The search field is the primary interaction point; typing updates
//     `query` and the host supplies matching `results` (host-driven,
//     same contract as Desktop Search but with Mission Hub categories).
//   - Results are host-driven: each entry is { id, title, subtitle?,
//     category?, icon? }. category ∈ "settings" | "features" |
//     "devices" | "drivers" | "documentation" | "updates" | "logs" |
//     "troubleshooting" (reference §9 searchable items). The screen
//     never mutates the model — activation emits resultActivated(id).
//   - Recent searches are host-driven strings rendered as chips while
//     the query is empty (Component Library §Search Components).
//   - Category filters are host-driven: each entry is { id, label }.
//     Clicking a filter emits categoryActivated(id); the host applies
//     the filter to the results model (documented interpretation).
//   - "Search should function offline whenever possible" (reference §9)
//     is carried as a caption in the empty state.
//   - Escape is deliberately unmapped: the host owns window-level
//     dismissal (same contract as all Mission Hub screens).
//   - The query field auto-focuses on presentation so typing works
//     immediately (reference: "Search opens instantly from anywhere").
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

    /// Current query text (user-editable; the host reads it to supply
    /// live results — reference §9 "Search should function offline")
    property string query: ""

    /// Search results: [{ id, title, subtitle?, category?, icon? }]
    /// host-driven. category ∈ "settings" | "features" | "devices" |
    /// "drivers" | "documentation" | "updates" | "logs" |
    /// "troubleshooting" (reference §9 searchable items).
    property var results: []

    /// Recent searches (host-driven strings; shown as chips while the
    /// query is empty — Component Library §Search Components)
    property var recentSearches: []

    /// Category filters: [{ id, label }]
    /// host-driven. Clicking emits categoryActivated(id).
    property var categories: [
        { id: "all",            label: "All" },
        { id: "settings",       label: "Settings" },
        { id: "features",       label: "Features" },
        { id: "devices",        label: "Devices" },
        { id: "drivers",        label: "Drivers" },
        { id: "documentation",  label: "Documentation" },
        { id: "updates",        label: "Updates" },
        { id: "logs",           label: "Logs" },
        { id: "troubleshooting", label: "Troubleshooting" }
    ]

    /// Currently selected category filter id
    property string selectedCategoryId: "all"

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
        { id: "settings",   label: "Settings" },
        { id: "search",     label: "Search" }
    ]

    /// Currently selected navigation item id
    property string selectedNavId: "search"

    // ── Signals (host wiring) ──────────────────────────────────────
    /// User activated a search result (host opens the result)
    signal resultActivated(string resultId)
    /// User activated a recent-search chip (host re-runs the search)
    signal recentSearchActivated(string text)
    /// User activated a category filter (host applies the filter)
    signal categoryActivated(string categoryId)
    /// User activated a navigation item (host opens the screen)
    signal navigationActivated(string navId)

    // Escape is deliberately unmapped (see interpretation notes): the
    // host owns window-level dismissal.

    // ── Derived helpers ────────────────────────────────────────────
    /// Whether the user has typed a (non-whitespace) query
    readonly property bool hasQuery: root.query.trim().length > 0

    /// Number of results in the host model
    readonly property int resultCount: root.results.length

    /// Number of recent-search chips in the host model
    readonly property int recentCount: root.recentSearches.length

    /// Number of category filters
    readonly property int categoryCount: root.categories.length

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

    /// Display label for a category (falls back to id)
    function categoryLabel(item) {
        if (item === null || item === undefined) return ""
        var l = item.label !== undefined ? String(item.label) : ""
        return l.length > 0 ? l : String(item.id)
    }

    /// Move keyboard focus to a navigation item
    function focusNavItem(index) {
        if (root.navigationItems.length === 0) return
        var count = root.navigationItems.length
        var target = ((index % count) + count) % count
        var item = navRepeater.itemAt(target)
        if (item !== null) item.forceActiveFocus()
    }

    /// Move keyboard focus to a result row
    function focusResult(index) {
        if (root.results.length === 0) return
        var count = root.results.length
        var target = ((index % count) + count) % count
        var item = resultRepeater.itemAt(target)
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

    // ── Test hooks (used by tests/tst_mission_hub_search.qml) ─────
    property alias headerBar: headerBar
    property alias titleLabel: titleLabel
    property alias sidebar: sidebar
    property alias navRepeater: navRepeater
    property alias mainContent: mainContent
    property alias searchField: searchField
    property alias categoryRepeater: categoryRepeater
    property alias resultRepeater: resultRepeater
    property alias recentChips: recentChips
    property alias noQueryHint: noQueryHint
    property alias noResultsHint: noResultsHint
    property alias loadingIndicator: loadingIndicator
    property alias errorBanner: errorBanner
    property alias offlineBanner: offlineBanner
    property alias emptyHint: emptyHint
    property alias clearButton: clearButton
    property alias clearMouse: clearMouse

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
                        anchors.fill: parent; anchors.margins: -2
                        radius: Radii.card + 2; color: "transparent"
                        border.color: MissionTheme.focusRing; border.width: 2
                        visible: navItem.activeFocus
                    }

                    MouseArea {
                        id: navItemMouse
                        anchors.fill: parent; hoverEnabled: true
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
            left: sidebar.right; right: parent.right
            top: headerBar.bottom; bottom: parent.bottom
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
                    text: qsTr("Searching…")
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
                        Label { text: qsTr("Search could not be loaded"); font.weight: Typography.weightSemibold; color: Colors.contentOnErrorContainer }
                        Label { text: qsTr("The search index could not be accessed. Check your system and try again."); font.pixelSize: Typography.bodySmall.size; color: Colors.contentOnErrorContainer; wrapMode: Text.Wrap; Layout.fillWidth: true }
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
                        Label { text: qsTr("Mission Hub search works fully offline — local settings, features and documentation are always available."); font.pixelSize: Typography.bodySmall.size; color: MissionTheme.textSecondary; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    }
                }
            }

            // ── Empty state ──
            Column {
                id: emptyHint
                objectName: "hubEmpty"
                visible: root.screenState === "empty"
                width: parent.width; spacing: Spacing.gapSmall
                Label { width: parent.width; text: qsTr("No search data available"); font.pixelSize: Typography.body.size; font.weight: Typography.weightSemibold; color: MissionTheme.textPrimary; wrapMode: Text.WordWrap; Accessible.role: Accessible.StaticText; Accessible.name: text }
                Label { width: parent.width; text: qsTr("Search results will appear here once the host provides search data."); font.pixelSize: Typography.bodySmall.size; color: MissionTheme.textSecondary; wrapMode: Text.WordWrap; Accessible.role: Accessible.StaticText; Accessible.name: text }
            }

            // ══════════════════════════════════════════════════════
            // Normal content
            // ══════════════════════════════════════════════════════
            Column {
                visible: root.screenState === "normal"
                width: parent.width
                spacing: Spacing.gapMedium

                // ── Search field ──
                Item {
                    width: parent.width
                    height: searchField.height + Spacing.paddingPage * 2
                    TextField {
                        id: searchField
                        objectName: "searchField"
                        anchors {
                            left: parent.left; right: parent.right
                            top: parent.top; margins: Spacing.paddingPage
                        }
                        text: root.query
                        onTextChanged: { if (text !== root.query) root.query = text }
                        placeholderText: qsTr("Search settings, features, devices, drivers, documentation…")
                        font.pixelSize: Typography.bodyLarge.size
                        color: MissionTheme.textPrimary
                        placeholderTextColor: MissionTheme.textTertiary
                        selectByMouse: true
                        leftPadding: Spacing.paddingLarge + searchIcon.width + Spacing.gapSmall
                        rightPadding: clearButton.visible ? clearButton.width + Spacing.paddingMedium : Spacing.paddingLarge
                        background: Rectangle {
                            radius: Radii.input
                            color: MissionTheme.surface
                            border.width: searchField.activeFocus ? 2 : 1
                            border.color: searchField.activeFocus ? MissionTheme.focusRing : MissionTheme.outline
                        }
                        Accessible.role: Accessible.EditableText
                        Accessible.name: qsTr("Search")
                        Accessible.description: qsTr("Type to search settings, features, devices, drivers and documentation")
                    }
                    // Search icon (left side)
                    Rectangle {
                        id: searchIcon
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
                    // Clear button (right side, visible when query is non-empty)
                    Rectangle {
                        id: clearButton
                        objectName: "searchClear"
                        visible: root.hasQuery
                        anchors.verticalCenter: searchField.verticalCenter
                        anchors.right: searchField.right
                        anchors.rightMargin: Spacing.paddingMedium
                        width: clearLabel.implicitWidth + Spacing.paddingSmall * 2
                        height: Spacing.gapMedium
                        radius: Radii.chip
                        color: clearMouse.containsMouse
                               ? MissionTheme.surfaceVariant : "transparent"
                        Label {
                            id: clearLabel
                            anchors.centerIn: parent
                            text: qsTr("Clear")
                            font.pixelSize: Typography.caption.size
                            color: MissionTheme.textSecondary
                        }
                        MouseArea {
                            id: clearMouse
                            anchors.fill: parent; hoverEnabled: true
                            onClicked: {
                                root.query = ""
                                searchField.forceActiveFocus()
                            }
                        }
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Clear search")
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

                // ── Recent searches (chips; visible while query is empty) ──
                Column {
                    width: parent.width
                    visible: !root.hasQuery && root.recentCount > 0
                    spacing: Spacing.gapSmall

                    Label {
                        text: qsTr("Recent searches")
                        font.pixelSize: Typography.caption.size
                        color: MissionTheme.textSecondary
                        anchors.leftMargin: Spacing.paddingPage
                        Accessible.role: Accessible.StaticText
                        Accessible.name: text
                    }

                    Flow {
                        width: parent.width
                        spacing: Spacing.gapSmall
                        leftPadding: Spacing.paddingPage; rightPadding: Spacing.paddingPage

                        Repeater {
                            id: recentChips
                            model: root.recentSearches

                            delegate: Rectangle {
                                required property var modelData
                                required property int index

                                id: recentChip
                                objectName: "searchRecent" + index
                                height: Spacing.minimumTouchTarget
                                width: recentLabel.implicitWidth + Spacing.paddingMedium * 2
                                radius: Radii.chip
                                color: recentChipMouse.containsMouse
                                       ? MissionTheme.surfaceVariant : MissionTheme.surface
                                border.width: 1; border.color: MissionTheme.outlineVariant
                                activeFocusOnTab: true

                                Behavior on color {
                                    enabled: !root.reducedMotion
                                    animation: ColorAnimation { duration: Motion.colorChange }
                                }

                                Rectangle {
                                    anchors.fill: parent; anchors.margins: -2
                                    radius: Radii.chip + 2; color: "transparent"
                                    border.color: MissionTheme.focusRing; border.width: 2
                                    visible: recentChip.activeFocus
                                }

                                Label {
                                    id: recentLabel
                                    anchors.centerIn: parent
                                    text: String(modelData)
                                    font.pixelSize: Typography.bodySmall.size
                                    color: MissionTheme.textPrimary
                                }

                                MouseArea {
                                    id: recentChipMouse
                                    anchors.fill: parent; hoverEnabled: true
                                    onClicked: {
                                        recentChip.forceActiveFocus()
                                        root.recentSearchActivated(String(modelData))
                                    }
                                }

                                Keys.onReturnPressed: root.recentSearchActivated(String(modelData))
                                Keys.onSpacePressed: root.recentSearchActivated(String(modelData))

                                Accessible.role: Accessible.Button
                                Accessible.name: String(modelData)
                                Accessible.description: qsTr("Run the search %1 again").arg(String(modelData))
                            }
                        }
                    }
                }

                // ── Results list ──
                Column {
                    visible: root.hasQuery
                    width: parent.width
                    spacing: Spacing.gapSmall

                    // Result count
                    Label {
                        text: root.resultCount > 0
                              ? qsTr("%1 result%2").arg(root.resultCount).arg(root.resultCount !== 1 ? "s" : "")
                              : ""
                        visible: root.resultCount > 0
                        font.pixelSize: Typography.caption.size
                        color: MissionTheme.textSecondary
                        anchors.leftMargin: Spacing.paddingPage
                        Accessible.role: Accessible.StaticText
                        Accessible.name: text
                    }

                    Repeater {
                        id: resultRepeater
                        model: root.results

                        delegate: Rectangle {
                            required property var modelData
                            required property int index

                            id: resultRow
                            objectName: "searchResult" + index
                            width: parent.width - Spacing.paddingPage * 2
                            anchors.leftMargin: Spacing.paddingPage
                            height: Math.max(Spacing.minimumTouchTarget,
                                             resultContent.implicitHeight + Spacing.paddingMedium * 2)
                            radius: Radii.card
                            color: resultRowMouse.containsMouse
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
                                visible: resultRow.activeFocus
                            }

                            MouseArea {
                                id: resultRowMouse
                                anchors.fill: parent; hoverEnabled: true
                                onClicked: {
                                    resultRow.forceActiveFocus()
                                    root.resultActivated(String(modelData.id))
                                }
                            }

                            RowLayout {
                                id: resultContent
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: Spacing.paddingMedium }
                                spacing: Spacing.gapMedium

                                // Category tag
                                Rectangle {
                                    visible: modelData.category !== undefined && String(modelData.category).length > 0
                                    Layout.preferredWidth: resultCatLabel.implicitWidth + Spacing.paddingSmall * 2
                                    Layout.preferredHeight: Spacing.gapMedium
                                    radius: Radii.chip
                                    color: MissionTheme.surfaceVariant
                                    Label {
                                        id: resultCatLabel
                                        anchors.centerIn: parent
                                        text: modelData.category !== undefined ? String(modelData.category) : ""
                                        font.pixelSize: Typography.caption.size
                                        color: MissionTheme.textSecondary
                                    }
                                }

                                Column {
                                    Layout.fillWidth: true; spacing: Spacing.gapTiny
                                    Label {
                                        width: parent.width
                                        text: modelData.title !== undefined ? String(modelData.title) : ""
                                        font.pixelSize: Typography.body.size
                                        font.weight: Typography.weightSemibold
                                        color: MissionTheme.textPrimary
                                        elide: Text.ElideRight
                                    }
                                    Label {
                                        width: parent.width
                                        visible: modelData.subtitle !== undefined && String(modelData.subtitle).length > 0
                                        text: modelData.subtitle !== undefined ? String(modelData.subtitle) : ""
                                        font.pixelSize: Typography.bodySmall.size
                                        color: MissionTheme.textSecondary
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            Keys.onUpPressed: root.focusResult(index - 1)
                            Keys.onDownPressed: root.focusResult(index + 1)
                            Keys.onReturnPressed: root.resultActivated(String(modelData.id))
                            Keys.onSpacePressed: root.resultActivated(String(modelData.id))

                            Accessible.role: Accessible.Button
                            Accessible.name: {
                                var t = modelData.title !== undefined ? String(modelData.title) : ""
                                var c = modelData.category !== undefined ? String(modelData.category) : ""
                                if (c.length > 0) return qsTr("%1, %2").arg(t).arg(c)
                                return t
                            }
                        }
                    }
                }

                // ── No query hint ──
                Column {
                    id: noQueryHint
                    objectName: "searchNoQuery"
                    visible: !root.hasQuery && root.recentCount === 0 && root.screenState === "normal"
                    width: parent.width; spacing: Spacing.gapSmall
                    Label { width: parent.width; text: qsTr("Start typing to search settings, features, devices, drivers and documentation"); font.pixelSize: Typography.bodySmall.size; color: MissionTheme.textSecondary; wrapMode: Text.WordWrap; Accessible.role: Accessible.StaticText; Accessible.name: text }
                    Label { width: parent.width; text: qsTr("Mission Hub search works fully offline — local content is always available"); font.pixelSize: Typography.caption.size; color: MissionTheme.textTertiary; wrapMode: Text.WordWrap; Accessible.role: Accessible.StaticText; Accessible.name: text }
                }

                // ── No results hint ──
                Column {
                    id: noResultsHint
                    objectName: "searchNoResults"
                    visible: root.hasQuery && root.resultCount === 0 && root.screenState === "normal"
                    width: parent.width; spacing: Spacing.gapMedium
                    Label { width: parent.width; text: qsTr("No results for \u201c%1\u201d").arg(root.query.trim()); font.pixelSize: Typography.body.size; font.weight: Typography.weightSemibold; color: MissionTheme.textPrimary; wrapMode: Text.WordWrap; Accessible.role: Accessible.StaticText; Accessible.name: text }
                    Label { width: parent.width; text: qsTr("Try a different search term, or check the settings that control what is indexed."); font.pixelSize: Typography.bodySmall.size; color: MissionTheme.textSecondary; wrapMode: Text.WordWrap; Accessible.role: Accessible.StaticText; Accessible.name: text }
                    MissionButton {
                        variant: MissionButton.Variant.Secondary
                        text: qsTr("Clear search")
                        onClicked: { root.query = ""; searchField.forceActiveFocus() }
                        Accessible.description: qsTr("Clear the search query")
                    }
                }

                // ── Bottom spacer ──
                Item { width: 1; height: Spacing.paddingLarge }
            }
        }
    }

    // ── Initial focus (keyboard-first) ─────────────────────────────
    focus: true
    Component.onCompleted: {
        searchField.forceActiveFocus()
    }
}
