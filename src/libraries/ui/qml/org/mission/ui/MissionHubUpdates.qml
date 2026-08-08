// Mission OS — Mission Hub Updates (MOS-HUB-004)
//
// Fourth screen of the Mission Hub family. Implements the source-defined
// Updates structure (docs/design/03_SCREEN_REGISTRY.md MOS-HUB-004
// "Updates", docs/reference/03_MISSION_HUB.md §Update Summary,
// docs/design/01_INFORMATION_ARCHITECTURE.md §5 Mission Hub Structure,
// docs/design/04_USER_FLOWS.md §7 Update System):
//
//   Hosting: a full-screen application within Mission Hub. The host
//   opens this from the Mission Hub sidebar. Place inside MissionWindow
//   content and anchor to fill, e.g.
//   MissionWindow { MissionHubUpdates { anchors.fill: parent } }
//   The component sizes to its implicit 1280x720 like Desktop.qml.
//
//   Layout (Master UX Specification §3):
//     Header → Sidebar Navigation → Main Content Area
//
//   Update Summary (reference §Update Summary):
//     Current version, latest version, update history, pending updates,
//     reboot requirements. "Updates link directly to Update Manager."
//
//   User Flow §7 (Update System):
//     Notification → Update Manager → Review → Install →
//     Restart (if required) → Verification
//
//   Mission Hub Structure (information architecture §5):
//     Mission Hub → Updates (one of: Home, Applications, Search,
//     Updates, Security, Privacy, Recovery, Diagnostics, Devices,
//     Storage, Network, Settings)
//
// Interpretation notes (documented — no authoritative source specifies
// further detail):
//   - The sidebar is persistent on wide layouts (≥768px) and collapses
//     to an icon rail on narrow layouts (established Mission Hub
//     pattern from MOS-HUB-001 Dashboard).
//   - Updates are host-driven: each entry is
//     { id, name, version, size?, type?, security?, releaseDate? }.
//     type ∈ "system" | "security" | "application" | "driver".
//     security is a boolean indicating whether this is a security update.
//   - The host supplies version info: { currentVersion, latestVersion }.
//   - Pending count is derived from the updates model.
//   - Update actions emit host-facing signals rather than performing
//     operations directly (same contract as all Mission Hub screens).
//   - Escape is deliberately unmapped: the host owns window-level
//     dismissal (same contract as all Mission Hub screens).
//   - Offline state shows a neutral message — Mission Hub works fully
//     offline (reference §2: "function fully offline except where
//     Internet access is explicitly required").
//   - "Updates link directly to Update Manager" (reference) — clicking
//     an update emits updateActivated(id); the host navigates.
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

    /// Current installed version
    property string currentVersion: ""

    /// Latest available version
    property string latestVersion: ""

    /// Whether a reboot is required after updates
    property bool rebootRequired: false

    /// Pending updates: [{ id, name, version, size?, type?, security?, releaseDate? }]
    /// type ∈ "system" | "security" | "application" | "driver"
    /// security ∈ boolean
    property var pendingUpdates: []

    /// Update history: [{ id, name, version, installedDate?, type? }]
    property var updateHistory: []

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
    property string selectedNavId: "updates"

    // ── Signals (host wiring) ──────────────────────────────────────
    /// User activated a pending update (host opens the update detail)
    signal updateActivated(string updateId)
    /// User requested to check for updates
    signal checkForUpdates()
    /// User requested to install all pending updates
    signal updateAll()
    /// User activated a navigation item (host opens the screen)
    signal navigationActivated(string navId)

    // Escape is deliberately unmapped (see interpretation notes): the
    // host owns window-level dismissal.

    // ── Derived helpers ────────────────────────────────────────────
    /// Number of pending updates
    readonly property int pendingCount: root.pendingUpdates.length

    /// Number of history items
    readonly property int historyCount: root.updateHistory.length

    /// Whether there are pending updates
    readonly property bool hasPendingUpdates: root.pendingCount > 0

    /// Whether the host has supplied version information (both fields
    /// set). Empty defaults mean "unknown" — never "up to date".
    readonly property bool versionKnown: root.currentVersion.length > 0 &&
                                         root.latestVersion.length > 0

    /// Whether the current version is up to date — only when the host
    /// actually reports both versions (never derived from empty defaults)
    readonly property bool isUpToDate: root.versionKnown &&
                                       root.currentVersion === root.latestVersion &&
                                       !root.hasPendingUpdates

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

    /// Type → display label
    function typeLabel(type) {
        switch (String(type)) {
        case "system":      return qsTr("System")
        case "security":    return qsTr("Security")
        case "application": return qsTr("Application")
        case "driver":      return qsTr("Driver")
        default:            return ""
        }
    }

    /// Type → token color
    function typeColor(type) {
        switch (String(type)) {
        case "security":    return MissionTheme.error
        case "system":      return MissionTheme.primary
        case "application": return MissionTheme.success
        case "driver":      return MissionTheme.warning
        default:            return MissionTheme.textSecondary
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

    /// Move keyboard focus to a pending update row
    function focusUpdate(index) {
        if (root.pendingUpdates.length === 0) return
        var count = root.pendingUpdates.length
        var target = ((index % count) + count) % count
        var item = pendingRepeater.itemAt(target)
        if (item !== null) item.forceActiveFocus()
    }

    /// Move keyboard focus to a history row
    function focusHistory(index) {
        if (root.updateHistory.length === 0) return
        var count = root.updateHistory.length
        var target = ((index % count) + count) % count
        var item = historyRepeater.itemAt(target)
        if (item !== null) item.forceActiveFocus()
    }

    // ── Test hooks (used by tests/tst_mission_hub_updates.qml) ──
    property alias headerBar: headerBar
    property alias titleLabel: titleLabel
    property alias sidebar: sidebar
    property alias navRepeater: navRepeater
    property alias mainContent: mainContent
    property alias pendingRepeater: pendingRepeater
    property alias historyRepeater: historyRepeater
    property alias loadingIndicator: loadingIndicator
    property alias errorBanner: errorBanner
    property alias offlineBanner: offlineBanner
    property alias emptyHint: emptyHint
    property alias rebootBanner: rebootBanner
    property alias statusBadge: statusBadge

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
                    text: qsTr("Checking for updates…")
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
                        Label { text: qsTr("Could not check for updates"); font.weight: Typography.weightSemibold; color: Colors.contentOnErrorContainer }
                        Label { text: qsTr("The update service could not be reached. Check your system and try again."); font.pixelSize: Typography.bodySmall.size; color: Colors.contentOnErrorContainer; wrapMode: Text.Wrap; Layout.fillWidth: true }
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
                        Label { text: qsTr("Update information requires an internet connection. Update history is still available."); font.pixelSize: Typography.bodySmall.size; color: MissionTheme.textSecondary; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    }
                }
            }

            // ── Empty state ──
            Column {
                id: emptyHint
                objectName: "hubEmpty"
                visible: root.screenState === "empty"
                width: parent.width; spacing: Spacing.gapSmall
                Label { width: parent.width; text: qsTr("No update information available"); font.pixelSize: Typography.body.size; font.weight: Typography.weightSemibold; color: MissionTheme.textPrimary; wrapMode: Text.WordWrap; Accessible.role: Accessible.StaticText; Accessible.name: text }
                Label { width: parent.width; text: qsTr("Update information will appear here once the host provides update data."); font.pixelSize: Typography.bodySmall.size; color: MissionTheme.textSecondary; wrapMode: Text.WordWrap; Accessible.role: Accessible.StaticText; Accessible.name: text }
            }

            // ══════════════════════════════════════════════════════
            // Normal content
            // ══════════════════════════════════════════════════════
            Column {
                visible: root.screenState === "normal"
                width: parent.width
                spacing: Spacing.gapLarge

                // ── Screen title ──
                Label {
                    text: qsTr("Updates")
                    font.pixelSize: Typography.headline.size
                    font.weight: Typography.headline.weight
                    color: MissionTheme.textPrimary
                    anchors.leftMargin: Spacing.paddingPage
                    Accessible.role: Accessible.Heading
                    Accessible.name: text
                }

                // ── Version info card ──
                Rectangle {
                    width: parent.width - Spacing.paddingPage * 2
                    anchors.leftMargin: Spacing.paddingPage
                    height: versionColumn.implicitHeight + Spacing.paddingLarge * 2
                    radius: Radii.card
                    color: MissionTheme.surface
                    border.color: MissionTheme.outlineVariant
                    border.width: 1

                    Column {
                        id: versionColumn
                        anchors {
                            left: parent.left; right: parent.right
                            top: parent.top; margins: Spacing.paddingLarge
                        }
                        spacing: Spacing.gapSmall

                        Label {
                            text: qsTr("System Version")
                            font.pixelSize: Typography.subtitle.size
                            font.weight: Typography.subtitle.weight
                            color: MissionTheme.textPrimary
                            Accessible.role: Accessible.Heading
                            Accessible.name: text
                        }

                        RowLayout {
                            width: parent.width
                            spacing: Spacing.gapLarge

                            Column {
                                spacing: Spacing.gapTiny
                                Label {
                                    text: qsTr("Current")
                                    font.pixelSize: Typography.caption.size
                                    color: MissionTheme.textSecondary
                                }
                                Label {
                                    text: root.currentVersion.length > 0 ? root.currentVersion : "—"
                                    font.pixelSize: Typography.bodyLarge.size
                                    font.weight: Typography.weightSemibold
                                    color: MissionTheme.textPrimary
                                    Accessible.role: Accessible.StaticText
                                    Accessible.name: qsTr("Current version: %1").arg(text)
                                }
                            }

                            Column {
                                spacing: Spacing.gapTiny
                                Label {
                                    text: qsTr("Latest")
                                    font.pixelSize: Typography.caption.size
                                    color: MissionTheme.textSecondary
                                }
                                Label {
                                    text: root.latestVersion.length > 0 ? root.latestVersion : "—"
                                    font.pixelSize: Typography.bodyLarge.size
                                    font.weight: Typography.weightSemibold
                                    color: root.isUpToDate ? MissionTheme.success : MissionTheme.primary
                                    Accessible.role: Accessible.StaticText
                                    Accessible.name: qsTr("Latest version: %1").arg(text)
                                }
                            }

                            Item { Layout.fillWidth: true }

                            // Status badge
                            Rectangle {
                                Layout.preferredWidth: statusBadge.implicitWidth + Spacing.paddingMedium * 2
                                Layout.preferredHeight: Spacing.minimumTouchTarget
                                radius: Radii.chip
                                color: root.hasPendingUpdates ? MissionTheme.warning
                                     : (root.isUpToDate ? MissionTheme.success
                                                        : MissionTheme.textTertiary)
                                Label {
                                    id: statusBadge
                                    anchors.centerIn: parent
                                    text: root.hasPendingUpdates ? qsTr("%1 pending").arg(root.pendingCount)
                                         : (root.isUpToDate ? qsTr("Up to date")
                                                            : qsTr("Unknown"))
                                    font.pixelSize: Typography.bodySmall.size
                                    font.weight: Typography.weightSemibold
                                    // contentOnPrimary pairs with the colored chips
                                    // (warning/success); textPrimary keeps the neutral
                                    // "Unknown" chip (textTertiary bg) readable
                                    color: root.hasPendingUpdates || root.isUpToDate
                                         ? MissionTheme.contentOnPrimary
                                         : MissionTheme.textPrimary
                                }
                            }
                        }
                    }
                }

                // ── Reboot required banner ──
                Rectangle {
                    id: rebootBanner
                    objectName: "rebootBanner"
                    visible: root.rebootRequired
                    width: parent.width - Spacing.paddingPage * 2
                    anchors.leftMargin: Spacing.paddingPage
                    height: rebootLayout.implicitHeight + Spacing.paddingMedium * 2
                    radius: Radii.card
                    color: MissionTheme.warningContainer || MissionTheme.surfaceVariant

                    RowLayout {
                        id: rebootLayout
                        anchors.fill: parent
                        anchors.margins: Spacing.paddingMedium
                        spacing: Spacing.gapMedium
                        Rectangle { Layout.preferredWidth: 12; Layout.preferredHeight: 12; radius: 6; color: MissionTheme.warning }
                        Label {
                            text: qsTr("A reboot is required to complete some updates.")
                            font.pixelSize: Typography.bodySmall.size
                            font.weight: Typography.weightSemibold
                            color: MissionTheme.textPrimary
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                        }
                    }
                }

                // ── Pending updates section ──
                Column {
                    width: parent.width
                    spacing: Spacing.gapMedium

                    RowLayout {
                        width: parent.width
                        spacing: Spacing.gapMedium
                        Label {
                            text: qsTr("Pending Updates")
                            font.pixelSize: Typography.subtitle.size
                            font.weight: Typography.subtitle.weight
                            color: MissionTheme.textPrimary
                            Layout.leftMargin: Spacing.paddingPage
                            Accessible.role: Accessible.Heading
                            Accessible.name: text
                        }
                        Item { Layout.fillWidth: true }
                        MissionButton {
                            visible: root.hasPendingUpdates
                            variant: MissionButton.Variant.Primary
                            text: qsTr("Update All")
                            onClicked: root.updateAll()
                        }
                        MissionButton {
                            variant: MissionButton.Variant.Secondary
                            text: qsTr("Check for Updates")
                            onClicked: root.checkForUpdates()
                        }
                    }

                    // No pending updates message
                    Column {
                        visible: !root.hasPendingUpdates
                        width: parent.width
                        spacing: Spacing.gapSmall
                        Label {
                            width: parent.width
                            text: qsTr("Your system is up to date")
                            font.pixelSize: Typography.body.size
                            font.weight: Typography.weightSemibold
                            color: MissionTheme.textPrimary
                            wrapMode: Text.WordWrap
                            anchors.leftMargin: Spacing.paddingPage
                        }
                        Label {
                            width: parent.width
                            text: qsTr("No pending updates at this time.")
                            font.pixelSize: Typography.bodySmall.size
                            color: MissionTheme.textSecondary
                            wrapMode: Text.WordWrap
                            anchors.leftMargin: Spacing.paddingPage
                        }
                    }

                    // Pending updates list
                    Repeater {
                        id: pendingRepeater
                        model: root.pendingUpdates

                        delegate: Rectangle {
                            required property var modelData
                            required property int index

                            id: updateRow
                            objectName: "update_" + modelData.id
                            width: parent.width - Spacing.paddingPage * 2
                            anchors.leftMargin: Spacing.paddingPage
                            height: Math.max(Spacing.minimumTouchTarget,
                                             updateContent.implicitHeight + Spacing.paddingMedium * 2)
                            radius: Radii.card
                            color: updateRowMouse.containsMouse
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
                                visible: updateRow.activeFocus
                            }

                            MouseArea {
                                id: updateRowMouse
                                anchors.fill: parent; hoverEnabled: true
                                onClicked: {
                                    updateRow.forceActiveFocus()
                                    root.updateActivated(String(modelData.id))
                                }
                            }

                            RowLayout {
                                id: updateContent
                                anchors {
                                    left: parent.left; right: parent.right
                                    top: parent.top; margins: Spacing.paddingMedium
                                }
                                spacing: Spacing.gapMedium

                                // Security indicator
                                Rectangle {
                                    visible: modelData.security === true
                                    Layout.preferredWidth: securityLabel.implicitWidth + Spacing.paddingSmall * 2
                                    Layout.preferredHeight: Spacing.gapMedium
                                    radius: Radii.chip
                                    color: MissionTheme.error
                                    Label {
                                        id: securityLabel
                                        anchors.centerIn: parent
                                        text: qsTr("Security")
                                        font.pixelSize: Typography.caption.size
                                        font.weight: Typography.weightSemibold
                                        color: MissionTheme.contentOnErrorContainer || "white"
                                    }
                                }

                                // Update info
                                Column {
                                    Layout.fillWidth: true
                                    spacing: Spacing.gapTiny
                                    Label {
                                        text: modelData.name !== undefined
                                              ? String(modelData.name) : String(modelData.id)
                                        font.pixelSize: Typography.body.size
                                        font.weight: Typography.weightSemibold
                                        color: MissionTheme.textPrimary
                                        elide: Text.ElideRight
                                    }
                                    Row {
                                        spacing: Spacing.gapSmall
                                        Label {
                                            text: modelData.version !== undefined
                                                  ? qsTr("v%1").arg(modelData.version) : ""
                                            font.pixelSize: Typography.bodySmall.size
                                            color: MissionTheme.textSecondary
                                            visible: text.length > 0
                                        }
                                        Label {
                                            visible: modelData.size !== undefined && String(modelData.size).length > 0
                                            text: modelData.size !== undefined ? String(modelData.size) : ""
                                            font.pixelSize: Typography.bodySmall.size
                                            color: MissionTheme.textTertiary
                                        }
                                    }
                                }

                                // Type tag
                                Rectangle {
                                    visible: modelData.type !== undefined && String(modelData.type).length > 0
                                    width: typeTagLabel.implicitWidth + Spacing.paddingSmall * 2
                                    height: Spacing.gapMedium
                                    radius: Radii.chip
                                    color: MissionTheme.surfaceVariant
                                    Label {
                                        id: typeTagLabel
                                        anchors.centerIn: parent
                                        text: root.typeLabel(modelData.type)
                                        font.pixelSize: Typography.caption.size
                                        color: root.typeColor(modelData.type)
                                    }
                                }

                                // Release date
                                Label {
                                    visible: modelData.releaseDate !== undefined
                                             && String(modelData.releaseDate).length > 0
                                    text: modelData.releaseDate !== undefined
                                          ? String(modelData.releaseDate) : ""
                                    font.pixelSize: Typography.caption.size
                                    color: MissionTheme.textTertiary
                                }
                            }

                            Accessible.role: Accessible.Button
                            Accessible.name: qsTr("%1 update: %2").arg(
                                modelData.type !== undefined ? root.typeLabel(modelData.type) : "Update"
                            ).arg(modelData.name !== undefined ? modelData.name : modelData.id)

                            Keys.onUpPressed: root.focusUpdate(index - 1)
                            Keys.onDownPressed: root.focusUpdate(index + 1)
                            Keys.onReturnPressed: root.updateActivated(String(modelData.id))
                            Keys.onSpacePressed: root.updateActivated(String(modelData.id))
                        }
                    }
                }

                // ── Update history section ──
                Column {
                    visible: root.historyCount > 0
                    width: parent.width
                    spacing: Spacing.gapMedium

                    Label {
                        text: qsTr("Update History")
                        font.pixelSize: Typography.subtitle.size
                        font.weight: Typography.subtitle.weight
                        color: MissionTheme.textPrimary
                        anchors.leftMargin: Spacing.paddingPage
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    Repeater {
                        id: historyRepeater
                        model: root.updateHistory

                        delegate: Rectangle {
                            required property var modelData
                            required property int index

                            id: historyRow
                            objectName: "history_" + modelData.id
                            width: parent.width - Spacing.paddingPage * 2
                            anchors.leftMargin: Spacing.paddingPage
                            height: Math.max(Spacing.minimumTouchTarget,
                                             historyContent.implicitHeight + Spacing.paddingMedium * 2)
                            radius: Radii.card
                            color: MissionTheme.surface
                            border.color: MissionTheme.outlineVariant
                            border.width: 1
                            activeFocusOnTab: true

                            Rectangle {
                                anchors.fill: parent; anchors.margins: -2
                                radius: Radii.card + 2; color: "transparent"
                                border.color: MissionTheme.focusRing; border.width: 2
                                visible: historyRow.activeFocus
                            }

                            MouseArea {
                                anchors.fill: parent; hoverEnabled: true
                                onClicked: {
                                    historyRow.forceActiveFocus()
                                    root.updateActivated(String(modelData.id))
                                }
                            }

                            RowLayout {
                                id: historyContent
                                anchors {
                                    left: parent.left; right: parent.right
                                    top: parent.top; margins: Spacing.paddingMedium
                                }
                                spacing: Spacing.gapMedium

                                Column {
                                    Layout.fillWidth: true
                                    spacing: Spacing.gapTiny
                                    Label {
                                        text: modelData.name !== undefined
                                              ? String(modelData.name) : String(modelData.id)
                                        font.pixelSize: Typography.body.size
                                        font.weight: Typography.weightSemibold
                                        color: MissionTheme.textPrimary
                                        elide: Text.ElideRight
                                    }
                                    Label {
                                        text: modelData.version !== undefined
                                              ? qsTr("v%1").arg(modelData.version) : ""
                                        font.pixelSize: Typography.bodySmall.size
                                        color: MissionTheme.textSecondary
                                        visible: text.length > 0
                                    }
                                }

                                // Type tag
                                Rectangle {
                                    visible: modelData.type !== undefined && String(modelData.type).length > 0
                                    width: histTypeLabel.implicitWidth + Spacing.paddingSmall * 2
                                    height: Spacing.gapMedium
                                    radius: Radii.chip
                                    color: MissionTheme.surfaceVariant
                                    Label {
                                        id: histTypeLabel
                                        anchors.centerIn: parent
                                        text: root.typeLabel(modelData.type)
                                        font.pixelSize: Typography.caption.size
                                        color: root.typeColor(modelData.type)
                                    }
                                }

                                // Installed date
                                Label {
                                    visible: modelData.installedDate !== undefined
                                             && String(modelData.installedDate).length > 0
                                    text: modelData.installedDate !== undefined
                                          ? String(modelData.installedDate) : ""
                                    font.pixelSize: Typography.caption.size
                                    color: MissionTheme.textTertiary
                                }
                            }

                            Accessible.role: Accessible.Button
                            Accessible.name: qsTr("%1 installed: %2").arg(
                                modelData.type !== undefined ? root.typeLabel(modelData.type) : "Update"
                            ).arg(modelData.name !== undefined ? modelData.name : modelData.id)

                            Keys.onUpPressed: root.focusHistory(index - 1)
                            Keys.onDownPressed: root.focusHistory(index + 1)
                            Keys.onReturnPressed: root.updateActivated(String(modelData.id))
                            Keys.onSpacePressed: root.updateActivated(String(modelData.id))
                        }
                    }
                }

                // ── Bottom spacer ──
                Item { width: 1; height: Spacing.paddingLarge }
            }
        }
    }
}
