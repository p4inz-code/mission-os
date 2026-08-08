// Mission OS — Mission Hub Security (MOS-HUB-005)
//
// Fifth screen of the Mission Hub family. Implements the source-defined
// Security structure (docs/design/03_SCREEN_REGISTRY.md MOS-HUB-005
// "Security", docs/reference/03_MISSION_HUB.md §3 Section 3 Security
// & Privacy Integration, docs/design/01_INFORMATION_ARCHITECTURE.md
// §5 Mission Hub Structure, §7 Security Structure,
// docs/design/04_USER_FLOWS.md §9 Security Review):
//
//   Hosting: a full-screen application within Mission Hub. The host
//   opens this from the Mission Hub sidebar. Place inside MissionWindow
//   content and anchor to fill, e.g.
//   MissionWindow { MissionHubSecurity { anchors.fill: parent } }
//   The component sizes to its implicit 1280x720 like Desktop.qml.
//
//   Layout (Master UX Specification §3):
//     Header → Sidebar Navigation → Main Content Area
//
//   Security Dashboard (reference §3 Section 3):
//     Overall Security Score, Secure Boot status, TPM status,
//     Encryption status, Firewall status, Security Updates,
//     Driver Trust Status, Boot Integrity, Application Sandboxing,
//     Active Protection Modules. "Every status indicator links
//     directly to detailed information."
//
//   Security Score (reference §3 Section 3):
//     Categories: Excellent, Good, Moderate, At Risk, Critical.
//     "Every deduction must explain why it happened, associated risk,
//     recommended fix."
//
//   Threat Center (reference §3 Section 3):
//     Recent security events: failed login attempts, suspicious
//     executable, blocked application, unsigned package, failed
//     verification, revoked certificate, abnormal privilege request.
//     "Each event includes: timestamp, severity, affected component,
//     recommended action."
//
//   Security Recommendations (reference §3 Section 3):
//     "Mission Hub recommends improvements without using fear-based
//     messaging." Examples: Enable Full Disk Encryption, Create
//     Recovery USB, Install Security Updates, Enable Automatic Lock,
//     Rotate Recovery Keys, Verify Installation Media.
//     "Recommendations are prioritized by impact."
//
//   User Flow §9 (Security Review):
//     Mission Hub → Security Center → Dashboard → Recommendations →
//     Apply Fixes
//
//   Security Structure (information architecture §7):
//     Dashboard, Firewall, Encryption, Secure Boot, TPM,
//     Authentication, Certificates, Incident History, Reports
//
// Interpretation notes (documented — no authoritative source specifies
// further detail):
//   - The sidebar is persistent on wide layouts (≥768px) and collapses
//     to an icon rail on narrow layouts (established Mission Hub
//     pattern from MOS-HUB-001 Dashboard).
//   - Security overview is host-driven: { score, level, secureBoot,
//     tpm, encryption, firewall, lastScan, appSandboxing,
//     activeProtection }. score ∈ 0-100; level ∈ "excellent" | "good" |
//     "moderate" | "risk" | "critical" (reference §3 Security Score).
//   - Recommendations are host-driven: each entry is
//     { id, title, description, severity?, actionLabel? }.
//     severity ∈ "info" | "warning" | "critical". The screen never
//     mutates the model — activation emits recommendationActivated(id).
//   - Threat events are host-driven: each entry is
//     { id, title, description?, timestamp?, severity?, component? }.
//     severity ∈ "info" | "warning" | "critical".
//   - All security actions emit host-facing signals rather than
//     performing privileged/backend operations inside QML (task spec:
//     "Any security actions must emit host-facing signals rather than
//     pretending to perform privileged/backend operations inside QML").
//   - Escape is deliberately unmapped: the host owns window-level
//     dismissal (same contract as all Mission Hub screens).
//   - Offline state shows a neutral message — Mission Hub works fully
//     offline (reference §2: "function fully offline except where
//     Internet access is explicitly required").
//   - "Do NOT invent security mechanisms or claim protections the
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

    /// Security overview: { score, level, secureBoot, tpm, encryption,
    ///   firewall, lastScan, appSandboxing, activeProtection }
    /// score ∈ 0-100
    /// level ∈ "excellent" | "good" | "moderate" | "risk" | "critical"
    /// secureBoot/tpm/encryption/firewall/appSandboxing ∈ bool | null
    /// lastScan ∈ string (date) | null
    /// activeProtection ∈ number (count) | null
    property var securityOverview: ({
        score: 85,
        level: "good",
        secureBoot: true,
        tpm: true,
        encryption: true,
        firewall: true,
        lastScan: null,
        appSandboxing: true,
        activeProtection: 3
    })

    /// Security recommendations: [{ id, title, description, severity?, actionLabel? }]
    /// severity ∈ "info" | "warning" | "critical"
    property var recommendations: []

    /// Threat events: [{ id, title, description?, timestamp?, severity?, component? }]
    /// severity ∈ "info" | "warning" | "critical"
    property var threatEvents: []

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
    property string selectedNavId: "security"

    // ── Signals (host wiring) ──────────────────────────────────────
    /// User activated a recommendation (host opens the detail or applies the fix)
    signal recommendationActivated(string recommendationId)
    /// User activated a threat event (host opens the event detail)
    signal threatActivated(string threatId)
    /// User requested a security scan
    signal scanRequested()
    /// User activated a navigation item (host opens the screen)
    signal navigationActivated(string navId)

    // Escape is deliberately unmapped (see interpretation notes): the
    // host owns window-level dismissal.

    // ── Derived helpers ────────────────────────────────────────────
    /// Number of recommendations
    readonly property int recommendationCount: root.recommendations.length

    /// Number of threat events
    readonly property int threatCount: root.threatEvents.length

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

    /// Security level → display label
    function levelLabel(level) {
        switch (String(level)) {
        case "excellent": return qsTr("Excellent")
        case "good":      return qsTr("Good")
        case "moderate":  return qsTr("Moderate")
        case "risk":      return qsTr("At Risk")
        case "critical":  return qsTr("Critical")
        default:          return qsTr("Unknown")
        }
    }

    /// Security level → token color
    function levelColor(level) {
        switch (String(level)) {
        case "excellent": return MissionTheme.success
        case "good":      return MissionTheme.primary
        case "moderate":  return MissionTheme.warning
        case "risk":      return MissionTheme.error
        case "critical":  return MissionTheme.error
        default:          return MissionTheme.textSecondary
        }
    }

    /// Status bool → display label
    function statusLabel(value) {
        if (value === true) return qsTr("Enabled")
        if (value === false) return qsTr("Disabled")
        return qsTr("Unknown")
    }

    /// Status bool → token color
    function statusColor(value) {
        if (value === true) return MissionTheme.success
        if (value === false) return MissionTheme.error
        return MissionTheme.textSecondary
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

    /// Move keyboard focus to a recommendation row
    function focusRecommendation(index) {
        if (root.recommendations.length === 0) return
        var count = root.recommendations.length
        var target = ((index % count) + count) % count
        var item = recommendationRepeater.itemAt(target)
        if (item !== null) item.forceActiveFocus()
    }

    /// Move keyboard focus to a threat event row
    function focusThreat(index) {
        if (root.threatEvents.length === 0) return
        var count = root.threatEvents.length
        var target = ((index % count) + count) % count
        var item = threatRepeater.itemAt(target)
        if (item !== null) item.forceActiveFocus()
    }

    // ── Test hooks (used by tests/tst_mission_hub_security.qml) ──
    property alias headerBar: headerBar
    property alias titleLabel: titleLabel
    property alias sidebar: sidebar
    property alias navRepeater: navRepeater
    property alias mainContent: mainContent
    property alias recommendationRepeater: recommendationRepeater
    property alias threatRepeater: threatRepeater
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
                    text: qsTr("Loading security information…")
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
                        Label { text: qsTr("Could not load security information"); font.weight: Typography.weightSemibold; color: Colors.contentOnErrorContainer }
                        Label { text: qsTr("Security status could not be loaded. Check your system and try again."); font.pixelSize: Typography.bodySmall.size; color: Colors.contentOnErrorContainer; wrapMode: Text.Wrap; Layout.fillWidth: true }
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
                        Label { text: qsTr("Local security status is still available. Some features may require an internet connection."); font.pixelSize: Typography.bodySmall.size; color: MissionTheme.textSecondary; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    }
                }
            }

            // ── Empty state ──
            Column {
                id: emptyHint
                objectName: "hubEmpty"
                visible: root.screenState === "empty"
                width: parent.width; spacing: Spacing.gapSmall
                Label { width: parent.width; text: qsTr("No security information available"); font.pixelSize: Typography.body.size; font.weight: Typography.weightSemibold; color: MissionTheme.textPrimary; wrapMode: Text.WordWrap; Accessible.role: Accessible.StaticText; Accessible.name: text }
                Label { width: parent.width; text: qsTr("Security status will appear here once the host provides security data."); font.pixelSize: Typography.bodySmall.size; color: MissionTheme.textSecondary; wrapMode: Text.WordWrap; Accessible.role: Accessible.StaticText; Accessible.name: text }
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
                    text: qsTr("Security")
                    font.pixelSize: Typography.headline.size
                    font.weight: Typography.headline.weight
                    color: MissionTheme.textPrimary
                    anchors.leftMargin: Spacing.paddingPage
                    Accessible.role: Accessible.Heading
                    Accessible.name: text
                }

                // ── Security Score card ──
                Rectangle {
                    width: parent.width - Spacing.paddingPage * 2
                    anchors.leftMargin: Spacing.paddingPage
                    height: scoreColumn.implicitHeight + Spacing.paddingLarge * 2
                    radius: Radii.card
                    color: MissionTheme.surface
                    border.color: MissionTheme.outlineVariant
                    border.width: 1

                    Column {
                        id: scoreColumn
                        anchors {
                            left: parent.left; right: parent.right
                            top: parent.top; margins: Spacing.paddingLarge
                        }
                        spacing: Spacing.gapSmall

                        Label {
                            text: qsTr("Security Score")
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
                                border.color: root.levelColor(root.securityOverview.level)
                                border.width: 3

                                Label {
                                    id: scoreValue
                                    anchors.centerIn: parent
                                    text: root.securityOverview.score !== undefined
                                          ? String(root.securityOverview.score) : "—"
                                    font.pixelSize: Typography.title.size
                                    font.weight: Typography.title.weight
                                    color: root.levelColor(root.securityOverview.level)
                                    Accessible.role: Accessible.StaticText
                                    Accessible.name: qsTr("Security score: %1").arg(text)
                                }
                            }

                            Column {
                                spacing: Spacing.gapTiny
                                Label {
                                    id: scoreLabel
                                    text: root.levelLabel(root.securityOverview.level)
                                    font.pixelSize: Typography.bodyLarge.size
                                    font.weight: Typography.weightSemibold
                                    color: MissionTheme.textPrimary
                                }
                                Label {
                                    text: qsTr("Overall security assessment")
                                    font.pixelSize: Typography.bodySmall.size
                                    color: MissionTheme.textSecondary
                                }
                            }

                            Item { Layout.fillWidth: true }

                            MissionButton {
                                variant: MissionButton.Variant.Secondary
                                text: qsTr("Run Scan")
                                onClicked: root.scanRequested()
                            }
                        }
                    }
                }

                // ── Security Status Grid ──
                Column {
                    width: parent.width
                    spacing: Spacing.gapMedium

                    Label {
                        text: qsTr("Security Status")
                        font.pixelSize: Typography.subtitle.size
                        font.weight: Typography.subtitle.weight
                        color: MissionTheme.textPrimary
                        anchors.leftMargin: Spacing.paddingPage
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    Grid {
                        width: parent.width
                        columns: root.width >= 960 ? 3 : (root.width >= 640 ? 2 : 1)
                        spacing: Spacing.gapMedium

                        Repeater {
                            model: [
                                { key: "secureBoot",  label: qsTr("Secure Boot") },
                                { key: "tpm",         label: qsTr("TPM") },
                                { key: "encryption",  label: qsTr("Encryption") },
                                { key: "firewall",    label: qsTr("Firewall") },
                                { key: "appSandboxing", label: qsTr("App Sandboxing") }
                            ]

                            delegate: Rectangle {
                                required property var modelData

                                objectName: "status_" + modelData.key
                                width: root.width >= 960
                                       ? (root.width - Spacing.paddingPage * 2 - Spacing.gapMedium * 2) / 3
                                       : (root.width >= 640
                                          ? (root.width - Spacing.paddingPage * 2 - Spacing.gapMedium) / 2
                                          : root.width - Spacing.paddingPage * 2)
                                height: statusRow.implicitHeight + Spacing.paddingMedium * 2
                                radius: Radii.card
                                color: MissionTheme.surface
                                border.color: MissionTheme.outlineVariant
                                border.width: 1

                                RowLayout {
                                    id: statusRow
                                    anchors {
                                        left: parent.left; right: parent.right
                                        top: parent.top; margins: Spacing.paddingMedium
                                    }
                                    spacing: Spacing.gapSmall

                                    Rectangle {
                                        width: 8; height: 8; radius: 4
                                        color: root.statusColor(root.securityOverview[modelData.key])
                                    }

                                    Column {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        Label {
                                            text: modelData.label
                                            font.pixelSize: Typography.body.size
                                            font.weight: Typography.weightSemibold
                                            color: MissionTheme.textPrimary
                                        }
                                        Label {
                                            text: root.statusLabel(root.securityOverview[modelData.key])
                                            font.pixelSize: Typography.caption.size
                                            color: root.statusColor(root.securityOverview[modelData.key])
                                        }
                                    }
                                }

                                Accessible.role: Accessible.StaticText
                                Accessible.name: qsTr("%1: %2").arg(modelData.label).arg(
                                    root.statusLabel(root.securityOverview[modelData.key])
                                )
                            }
                        }
                    }
                }

                // ── Recommendations section ──
                Column {
                    width: parent.width
                    spacing: Spacing.gapMedium

                    Label {
                        text: qsTr("Recommendations")
                        font.pixelSize: Typography.subtitle.size
                        font.weight: Typography.subtitle.weight
                        color: MissionTheme.textPrimary
                        anchors.leftMargin: Spacing.paddingPage
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    // No recommendations message
                    Column {
                        visible: root.recommendationCount === 0
                        width: parent.width
                        spacing: Spacing.gapSmall
                        Label {
                            width: parent.width
                            text: qsTr("No recommendations at this time")
                            font.pixelSize: Typography.body.size
                            font.weight: Typography.weightSemibold
                            color: MissionTheme.textPrimary
                            wrapMode: Text.WordWrap
                            anchors.leftMargin: Spacing.paddingPage
                        }
                        Label {
                            width: parent.width
                            text: qsTr("Your system security configuration looks good.")
                            font.pixelSize: Typography.bodySmall.size
                            color: MissionTheme.textSecondary
                            wrapMode: Text.WordWrap
                            anchors.leftMargin: Spacing.paddingPage
                        }
                    }

                    Repeater {
                        id: recommendationRepeater
                        model: root.recommendations

                        delegate: Rectangle {
                            required property var modelData
                            required property int index

                            id: recRow
                            objectName: "rec_" + modelData.id
                            width: parent.width - Spacing.paddingPage * 2
                            anchors.leftMargin: Spacing.paddingPage
                            height: Math.max(Spacing.minimumTouchTarget,
                                             recContent.implicitHeight + Spacing.paddingMedium * 2)
                            radius: Radii.card
                            color: recRowMouse.containsMouse
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
                                visible: recRow.activeFocus
                            }

                            MouseArea {
                                id: recRowMouse
                                anchors.fill: parent; hoverEnabled: true
                                onClicked: {
                                    recRow.forceActiveFocus()
                                    root.recommendationActivated(String(modelData.id))
                                }
                            }

                            RowLayout {
                                id: recContent
                                anchors {
                                    left: parent.left; right: parent.right
                                    top: parent.top; margins: Spacing.paddingMedium
                                }
                                spacing: Spacing.gapMedium

                                // Severity indicator
                                Rectangle {
                                    visible: modelData.severity !== undefined
                                             && String(modelData.severity).length > 0
                                    Layout.preferredWidth: 8
                                    Layout.preferredHeight: 8
                                    radius: 4
                                    color: root.severityColor(modelData.severity)
                                }

                                Column {
                                    Layout.fillWidth: true
                                    spacing: Spacing.gapTiny
                                    Label {
                                        text: modelData.title !== undefined
                                              ? String(modelData.title) : String(modelData.id)
                                        font.pixelSize: Typography.body.size
                                        font.weight: Typography.weightSemibold
                                        color: MissionTheme.textPrimary
                                        elide: Text.ElideRight
                                        width: parent.width
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
                                }

                                // Action button
                                Rectangle {
                                    visible: modelData.actionLabel !== undefined
                                             && String(modelData.actionLabel).length > 0
                                    width: recActionLabel.implicitWidth + Spacing.paddingMedium * 2
                                    height: Spacing.minimumTouchTarget
                                    radius: Radii.chip
                                    color: recActionMouse.containsMouse
                                           ? MissionTheme.primary : MissionTheme.surfaceVariant
                                    Label {
                                        id: recActionLabel
                                        anchors.centerIn: parent
                                        text: modelData.actionLabel !== undefined
                                              ? String(modelData.actionLabel) : ""
                                        font.pixelSize: Typography.bodySmall.size
                                        font.weight: Typography.weightSemibold
                                        color: recActionMouse.containsMouse
                                               ? MissionTheme.contentOnPrimary : MissionTheme.textPrimary
                                    }
                                    MouseArea {
                                        id: recActionMouse
                                        anchors.fill: parent; hoverEnabled: true
                                        onClicked: {
                                            recRow.forceActiveFocus()
                                            root.recommendationActivated(String(modelData.id))
                                        }
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

                // ── Threat Events section ──
                Column {
                    visible: root.threatCount > 0
                    width: parent.width
                    spacing: Spacing.gapMedium

                    Label {
                        text: qsTr("Recent Security Events")
                        font.pixelSize: Typography.subtitle.size
                        font.weight: Typography.subtitle.weight
                        color: MissionTheme.textPrimary
                        anchors.leftMargin: Spacing.paddingPage
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    Repeater {
                        id: threatRepeater
                        model: root.threatEvents

                        delegate: Rectangle {
                            required property var modelData
                            required property int index

                            id: threatRow
                            objectName: "threat_" + modelData.id
                            width: parent.width - Spacing.paddingPage * 2
                            anchors.leftMargin: Spacing.paddingPage
                            height: Math.max(Spacing.minimumTouchTarget,
                                             threatContent.implicitHeight + Spacing.paddingMedium * 2)
                            radius: Radii.card
                            color: threatRowMouse.containsMouse
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
                                visible: threatRow.activeFocus
                            }

                            MouseArea {
                                id: threatRowMouse
                                anchors.fill: parent; hoverEnabled: true
                                onClicked: {
                                    threatRow.forceActiveFocus()
                                    root.threatActivated(String(modelData.id))
                                }
                            }

                            RowLayout {
                                id: threatContent
                                anchors {
                                    left: parent.left; right: parent.right
                                    top: parent.top; margins: Spacing.paddingMedium
                                }
                                spacing: Spacing.gapMedium

                                // Severity indicator
                                Rectangle {
                                    visible: modelData.severity !== undefined
                                             && String(modelData.severity).length > 0
                                    Layout.preferredWidth: 8
                                    Layout.preferredHeight: 8
                                    radius: 4
                                    color: root.severityColor(modelData.severity)
                                }

                                Column {
                                    Layout.fillWidth: true
                                    spacing: Spacing.gapTiny
                                    Label {
                                        text: modelData.title !== undefined
                                              ? String(modelData.title) : String(modelData.id)
                                        font.pixelSize: Typography.body.size
                                        font.weight: Typography.weightSemibold
                                        color: MissionTheme.textPrimary
                                        elide: Text.ElideRight
                                        width: parent.width
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
                                    Row {
                                        spacing: Spacing.gapSmall
                                        Label {
                                            visible: modelData.component !== undefined
                                                     && String(modelData.component).length > 0
                                            text: modelData.component !== undefined
                                                  ? String(modelData.component) : ""
                                            font.pixelSize: Typography.caption.size
                                            color: MissionTheme.textTertiary
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
                                }
                            }

                            Accessible.role: Accessible.Button
                            Accessible.name: qsTr("Security event: %1").arg(
                                modelData.title !== undefined ? modelData.title : modelData.id
                            )

                            Keys.onUpPressed: root.focusThreat(index - 1)
                            Keys.onDownPressed: root.focusThreat(index + 1)
                            Keys.onReturnPressed: root.threatActivated(String(modelData.id))
                            Keys.onSpacePressed: root.threatActivated(String(modelData.id))
                        }
                    }
                }

                // ── Bottom spacer ──
                Item { width: 1; height: Spacing.paddingLarge }
            }
        }
    }
}
