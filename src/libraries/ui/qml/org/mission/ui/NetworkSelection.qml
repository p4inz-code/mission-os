// Mission OS — Installer Network Selection (MOS-INS-004)
//
// Fourth screen of the Mission OS installer.
// Implements the source-defined Network structure (docs/wireframes/
// 01_INSTALLER.md + docs/reference/01_INSTALLER.md "Network
// Configuration"):
//
//   Hosting: place inside MissionWindow (or MissionPage) content and
//   anchor to fill, e.g.  MissionWindow { NetworkSelection { anchors.fill: parent } }
//   The component itself sizes to its implicit 1024x768 like MissionPage.
//
//   Header → Stepper Navigation → Main Content → Help Panel → Bottom actions
//
// Displayed items (per reference "Network Configuration"):
//   - Connection method list: Offline installation (default), Ethernet,
//     Wi-Fi, Proxy, Static IP, DHCP. Single-select list; selected row
//     highlighted; visible focus ring; Enter/Space/click selects.
//     No search/filter (not specified for this screen — do not invent).
//   - Live feedback of the current selection
//   - Back / Continue (wireframe UX rules: linear workflow, back always
//     available, validation before continuing)
//
// "Installation should remain possible without an Internet connection
// whenever practical" — Offline installation is the default.
//
// States (per wireframe): empty · loading · error · success · offline
// The screen exposes *Requested signals; the host application decides
// what each action does (e.g. driving NetworkManager).
//
// Design-system compliance:
//   - Tokens only (Colors, Typography, Spacing, Radii, Motion, MissionTheme)
//   - Light + dark themes via MissionTheme (driven by host)
//   - Keyboard navigation with visible focus states
//   - WCAG AA-oriented contrast, reduced-motion aware
//   - Responsive reflow per docs/design/14_RESPONSIVE_RULES.md

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.mission.ui 1.0

FocusScope {
    id: root

    implicitWidth: 1024
    implicitHeight: 768

    // ── Public API ─────────────────────────────────────────────────
    /// Screen state: "empty" | "loading" | "error" | "success" | "offline"
    property string screenState: "empty"

    /// Current installer step (1-based); Back is only enabled past step 1
    property int step: 4

    /// Total number of installer steps (screen registry: 12)
    property int totalSteps: 17

    /// Reduced motion (accessibility)
    property bool reducedMotion: false

    /// Installer/OS version string shown in the header
    property string version: "0.1.0"

    /// Build channel: Stable | Beta | Nightly
    property string buildType: "Nightly"

    /// Available connection methods. Each entry: { label, code }.
    /// Static fixture — the host service (NetworkManager) applies the
    /// real connection when connectionChangeRequested fires.
    /// Offline installation is first and the default (installation must
    /// remain possible without an Internet connection whenever practical).
    property var connectionOptions: [
        { label: "Offline installation", code: "offline" },
        { label: "Ethernet", code: "ethernet" },
        { label: "Wi-Fi", code: "wifi" },
        { label: "Proxy", code: "proxy" },
        { label: "Static IP", code: "static" },
        { label: "DHCP", code: "dhcp" }
    ]

    /// Index of the selected connection within `connectionOptions`
    property int selectedConnectionIndex: 0

    /// The selected connection object (from `connectionOptions`)
    property var selectedConnection: root.connectionOptions.length > 0 ? root.connectionOptions[0] : null

    /// Currently selected connection label. Preselected to Offline
    /// installation (the default) so the screen loads with a valid
    /// selection (no signal is emitted on load — the host already knows
    /// the default).
    property string currentConnectionLabel: root.connectionOptions.length > 0 ? root.connectionOptions[0].label : ""

    /// Currently selected connection code (e.g. "offline")
    property string currentConnectionCode: root.connectionOptions.length > 0 ? root.connectionOptions[0].code : ""

    // ── Signals (host wiring) ──────────────────────────────────────
    /// User requested to continue to the next step
    signal continueRequested()
    /// User requested to go back to the previous step
    signal backRequested()
    /// User selected a connection method (connection code, e.g. "offline")
    signal connectionChangeRequested(string code)
    /// User requested to retry after an error
    signal retryRequested()

    // ── Escape navigates back (Master UX: Back always available) ──
    Keys.onEscapePressed: root.backRequested()

    // ── Responsive helpers ─────────────────────────────────────────
    readonly property bool wideLayout: root.width >= 760
    readonly property bool compactLayout: root.width < 640

    // ── Selection helper ───────────────────────────────────────────
    function selectConnection(index) {
        if (index < 0 || index >= root.connectionOptions.length)
            return
        var option = root.connectionOptions[index]
        root.selectedConnectionIndex = index
        root.selectedConnection = option
        root.currentConnectionLabel = option.label
        root.currentConnectionCode = option.code
        root.connectionChangeRequested(root.currentConnectionCode)
    }

    // ── Test hooks (used by tests/tst_network.qml) ─────────────────
    property alias backgroundColor: backgroundRect.color
    property alias headingColor: headingLabel.color
    property alias headingLabel: headingLabel
    property alias connectionList: connectionList
    property alias selectionCaption: selectionCaption
    property alias helpPanel: helpPanel
    property alias backButton: backButton
    property alias continueButton: continueButton
    property alias retryButton: retryButton
    property alias errorBanner: errorBanner
    property alias successBanner: successBanner
    property alias offlineBanner: offlineBanner
    property alias loadingIndicator: loadingIndicator

    // ── Background ─────────────────────────────────────────────────
    Rectangle {
        id: backgroundRect
        anchors.fill: parent
        color: MissionTheme.background
    }

    // ══════════════════════════════════════════════════════════════
    // Header
    // ══════════════════════════════════════════════════════════════
    Rectangle {
        id: header
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

            // Logo mark (simple geometric mark; icon set not yet shipped)
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
                Accessible.name: qsTr("Mission OS logo")
            }

            // Wordmark + version/build type
            Column {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 0
                Label {
                    text: "Mission OS"
                    font.pixelSize: Typography.title.size
                    font.weight: Typography.title.weight
                    color: MissionTheme.textPrimary
                    elide: Text.ElideRight
                }
                Label {
                    text: qsTr("Version %1 · %2").arg(root.version).arg(root.buildType)
                    font.pixelSize: Typography.caption.size
                    color: MissionTheme.textSecondary
                    visible: !root.compactLayout
                }
            }
        }
    }

    // ══════════════════════════════════════════════════════════════
    // Stepper / navigation context
    // ══════════════════════════════════════════════════════════════
    Item {
        id: stepperBar
        anchors {
            left: parent.left
            right: parent.right
            top: header.bottom
        }
        height: Spacing.toolbarHeight

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Spacing.paddingPage
            anchors.rightMargin: Spacing.paddingPage
            spacing: Spacing.gapMedium

            Label {
                text: qsTr("Step %1 of %2 · Network").arg(root.step).arg(root.totalSteps)
                font.pixelSize: Typography.bodySmall.size
                font.weight: Typography.weightSemibold
                color: MissionTheme.textSecondary
                elide: Text.ElideRight
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }

            Item { Layout.fillWidth: true }

            // Step segments
            Row {
                spacing: Spacing.gapTiny
                Accessible.role: Accessible.Grouping
                Accessible.name: qsTr("Installation steps: %1 of %2").arg(root.step).arg(root.totalSteps)
                Repeater {
                    model: root.totalSteps
                    delegate: Rectangle {
                        property bool isCurrent: index === root.step - 1
                        property bool isDone: index < root.step - 1
                        width: (root.compactLayout || !root.wideLayout) ? 8 : 20
                        height: 4
                        radius: 2
                        color: isDone ? MissionTheme.success
                             : isCurrent ? MissionTheme.primary
                             : MissionTheme.outlineVariant
                    }
                }
            }
        }
    }

    // ══════════════════════════════════════════════════════════════
    // Main content + help panel
    // ══════════════════════════════════════════════════════════════
    Item {
        anchors {
            left: parent.left
            right: parent.right
            top: stepperBar.bottom
            bottom: actionBar.top
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Spacing.paddingPage
            anchors.rightMargin: Spacing.paddingPage
            anchors.topMargin: Spacing.gapLarge
            anchors.bottomMargin: Spacing.gapLarge
            spacing: Spacing.gapLarge

            // ── Main content (scrollable) ──
            Flickable {
                id: contentFlickable
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentHeight: contentColumn.height
                ScrollIndicator.vertical: ScrollIndicator {}

                Column {
                    id: contentColumn
                    width: contentFlickable.width
                    spacing: Spacing.gapMedium

                    // ── State area (per installer wireframe states) ──
                    // Loading (non-blocking progress)
                    RowLayout {
                        id: loadingIndicator
                        visible: root.screenState === "loading"
                        width: parent.width
                        spacing: Spacing.gapMedium
                        Label {
                            text: qsTr("Checking network options…")
                            font.pixelSize: Typography.bodySmall.size
                            color: MissionTheme.textSecondary
                        }
                        Rectangle {
                            id: loadingTrack
                            Layout.fillWidth: true
                            Layout.preferredHeight: 4
                            radius: 2
                            color: MissionTheme.surfaceDim
                            Rectangle {
                                id: loadingFill
                                width: 96
                                height: 4
                                radius: 2
                                color: MissionTheme.primary
                                x: -96
                                NumberAnimation on x {
                                    running: root.screenState === "loading" && !root.reducedMotion
                                    from: -96
                                    to: loadingTrack.width
                                    duration: Motion.durationSlow
                                    loops: Animation.Infinite
                                }
                            }
                        }
                    }

                    // Error (title + explanation + recovery action)
                    Rectangle {
                        id: errorBanner
                        visible: root.screenState === "error"
                        width: parent.width
                        // The inner RowLayout uses anchors (not layout
                        // sizing), so give the banner an explicit height
                        // from its content — otherwise the Rectangle has
                        // implicit height 0 and the state banner is
                        // invisible even when `visible` is true.
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
                                    text: qsTr("Network options could not be loaded")
                                    font.weight: Typography.weightSemibold
                                    color: Colors.contentOnErrorContainer
                                }
                                Label {
                                    text: qsTr("The connection catalog could not be verified. Check the installation media and try again.")
                                    font.pixelSize: Typography.bodySmall.size
                                    color: Colors.contentOnErrorContainer
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                            MissionButton {
                                id: retryButton
                                objectName: "networkRetry"
                                variant: MissionButton.Variant.Secondary
                                text: qsTr("Retry")
                                onClicked: root.retryRequested()
                            }
                        }
                    }

                    // Success
                    Rectangle {
                        id: successBanner
                        visible: root.screenState === "success"
                        width: parent.width
                        height: successLayout.implicitHeight + Spacing.paddingMedium * 2
                        radius: Radii.card
                        color: Colors.successContainer

                        RowLayout {
                            id: successLayout
                            anchors.fill: parent
                            anchors.margins: Spacing.paddingMedium
                            spacing: Spacing.gapMedium
                            Rectangle {
                                Layout.preferredWidth: 12
                                Layout.preferredHeight: 12
                                radius: 6
                                color: MissionTheme.success
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Spacing.gapTiny
                                Label {
                                    text: qsTr("Network selection saved")
                                    font.weight: Typography.weightSemibold
                                    color: Colors.contentOnSuccessContainer
                                }
                                Label {
                                    text: qsTr("Your connection method will be used for this installation.")
                                    font.pixelSize: Typography.bodySmall.size
                                    color: Colors.contentOnSuccessContainer
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }

                    // Offline (informational — installation works offline)
                    Rectangle {
                        id: offlineBanner
                        visible: root.screenState === "offline"
                        width: parent.width
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
                                    text: qsTr("Mission OS installs fully without an internet connection. All required packages are included on the installation media.")
                                    font.pixelSize: Typography.bodySmall.size
                                    color: MissionTheme.textSecondary
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }

                    // ── Heading ──
                    Label {
                        id: headingLabel
                        text: qsTr("Select a connection method")
                        width: parent.width
                        font.pixelSize: Typography.headline.size
                        font.weight: Typography.headline.weight
                        color: MissionTheme.textPrimary
                        wrapMode: Text.Wrap
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    Label {
                        text: qsTr("Choose how Mission OS connects during installation. You can install fully offline — no account or internet connection is required.")
                        width: parent.width
                        font.pixelSize: Typography.bodyLarge.size
                        color: MissionTheme.textSecondary
                        wrapMode: Text.Wrap
                        lineHeight: Typography.lineHeightRelaxed
                    }

                    // ── Connection method list (no search — not
                    //    specified for this screen) ──
                    Label {
                        text: qsTr("Connection method")
                        width: parent.width
                        font.pixelSize: Typography.subtitle.size
                        font.weight: Typography.subtitle.weight
                        color: MissionTheme.textPrimary
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    ListView {
                        id: connectionList
                        objectName: "networkList"
                        width: parent.width
                        // All rows visible by default; capped so the list
                        // never dominates short windows (scrolls inside).
                        height: Math.min(root.connectionOptions.length * Spacing.minimumTouchTarget
                                         + (root.connectionOptions.length - 1) * Spacing.gapTiny,
                                         396)
                        clip: true
                        model: root.connectionOptions
                        spacing: Spacing.gapTiny
                        activeFocusOnTab: true
                        keyNavigationWraps: true
                        highlightFollowsCurrentItem: true
                        ScrollIndicator.vertical: ScrollIndicator {}
                        onCountChanged: {
                            if (connectionList.count > 0 && connectionList.currentIndex < 0)
                                connectionList.currentIndex = 0
                        }
                        Keys.onReturnPressed: root.selectConnection(connectionList.currentIndex)
                        Keys.onSpacePressed: root.selectConnection(connectionList.currentIndex)
                        Accessible.role: Accessible.List
                        Accessible.name: qsTr("Connection methods")

                        delegate: Rectangle {
                            id: connectionDelegate
                            required property var modelData
                            required property int index

                            // When the list is reached via Tab, focus lands on
                            // the currentItem delegate — not on the ListView
                            // itself — so the delegate carries the objectName
                            // used by the keyboard-focus test.
                            objectName: "networkItem" + index
                            width: connectionList.width
                            height: Spacing.minimumTouchTarget
                            radius: Radii.input
                            color: {
                                if (root.selectedConnectionIndex === index)
                                    return MissionTheme.darkMode ? MissionTheme.primary
                                                                 : MissionTheme.primaryContainer
                                if (connectionList.currentIndex === index && connectionList.activeFocus)
                                    return MissionTheme.surfaceVariant
                                if (connectionDelegateMouse.containsMouse)
                                    return MissionTheme.surfaceVariant
                                return "transparent"
                            }

                            Behavior on color {
                                enabled: !root.reducedMotion
                                // Ubuntu Qt 6.10 toolchain: Behavior `duration`
                                // convenience property is rejected; use the
                                // equivalent `animation:` group property.
                                animation: ColorAnimation { duration: Motion.colorChange }
                            }

                            // Visible focus ring (keyboard navigation)
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: -2
                                radius: Radii.input + 2
                                color: "transparent"
                                border.color: MissionTheme.focusRing
                                border.width: 2
                                visible: connectionList.currentIndex === index &&
                                         connectionList.activeFocus
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Spacing.paddingMedium
                                anchors.rightMargin: Spacing.paddingMedium
                                spacing: Spacing.gapMedium

                                Label {
                                    text: modelData.label
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    font.pixelSize: Typography.body.size
                                    font.weight: root.selectedConnectionIndex === index
                                                 ? Typography.weightSemibold : Typography.weightRegular
                                    color: root.selectedConnectionIndex === index
                                         ? (MissionTheme.darkMode ? MissionTheme.contentOnPrimary
                                                                 : MissionTheme.contentOnPrimaryContainer)
                                         : MissionTheme.textPrimary
                                }

                                Label {
                                    text: modelData.code
                                    font.pixelSize: Typography.caption.size
                                    color: root.selectedConnectionIndex === index
                                         ? (MissionTheme.darkMode ? MissionTheme.contentOnPrimary
                                                                 : MissionTheme.contentOnPrimaryContainer)
                                         : MissionTheme.textTertiary
                                }
                            }

                            MouseArea {
                                id: connectionDelegateMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    connectionList.currentIndex = index
                                    root.selectConnection(index)
                                }
                            }

                            Accessible.role: Accessible.ListItem
                            Accessible.name: modelData.label + ", " + modelData.code
                            Accessible.selected: root.selectedConnectionIndex === index
                        }
                    }

                    // ── Live selection feedback ──
                    Label {
                        id: selectionCaption
                        width: parent.width
                        visible: root.currentConnectionCode.length > 0
                        text: qsTr("Selected: %1 · %2").arg(root.currentConnectionLabel)
                                                      .arg(root.currentConnectionCode)
                        font.pixelSize: Typography.caption.size
                        color: MissionTheme.textTertiary
                        elide: Text.ElideRight
                        Accessible.role: Accessible.StaticText
                        Accessible.name: text
                    }
                }
            }

            // ── Help panel (optional; collapses on narrow widths) ──
            Rectangle {
                id: helpPanel
                visible: root.wideLayout
                Layout.fillHeight: true
                Layout.preferredWidth: Math.min(Spacing.sidebarWidth, root.width * 0.32)
                radius: Radii.card
                color: MissionTheme.surfaceVariant

                Column {
                    anchors.fill: parent
                    anchors.margins: Spacing.paddingLarge
                    spacing: Spacing.gapMedium

                    Label {
                        text: qsTr("Help & tips")
                        font.pixelSize: Typography.subtitle.size
                        font.weight: Typography.subtitle.weight
                        color: MissionTheme.textPrimary
                    }

                    Label {
                        text: qsTr("Mission OS installs fully without an internet connection — all required packages are on the installation media. Choose a connection only if you need updates or drivers during installation.")
                        width: parent.width
                        font.pixelSize: Typography.bodySmall.size
                        color: MissionTheme.textSecondary
                        wrapMode: Text.Wrap
                        lineHeight: Typography.lineHeightNormal
                    }

                    Item { width: 1; height: Spacing.gapSmall }

                    Label {
                        text: qsTr("You can change the connection method at any time during installation.")
                        width: parent.width
                        font.pixelSize: Typography.bodySmall.size
                        color: MissionTheme.textSecondary
                        wrapMode: Text.Wrap
                        lineHeight: Typography.lineHeightNormal
                    }

                    Item { width: 1; height: Spacing.gapSmall }

                    Label {
                        text: qsTr("Privacy by default — no telemetry, no account, no cloud required.")
                        width: parent.width
                        font.pixelSize: Typography.caption.size
                        color: MissionTheme.textTertiary
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }

    // ══════════════════════════════════════════════════════════════
    // Bottom action bar (Back / Continue)
    // ══════════════════════════════════════════════════════════════
    Rectangle {
        id: actionBar
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: Spacing.minimumTouchTarget + Spacing.paddingMedium * 2
        color: MissionTheme.surface
        z: 2

        // Top hairline
        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
            }
            height: 1
            color: MissionTheme.outline
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Spacing.paddingPage
            anchors.rightMargin: Spacing.paddingPage
            spacing: Spacing.gapMedium

            // Back is only available past step 1 (linear workflow)
            MissionButton {
                id: backButton
                objectName: "networkBack"
                variant: MissionButton.Variant.Secondary
                text: qsTr("Back")
                enabled: root.step > 1
                onClicked: root.backRequested()
            }

            Item { Layout.fillWidth: true }

            // Continue (primary action; disabled while loading/error so it
            // never silently advances when validation is pending)
            MissionButton {
                id: continueButton
                objectName: "networkContinue"
                variant: MissionButton.Variant.Primary
                text: qsTr("Continue")
                loading: root.screenState === "loading"
                enabled: root.screenState !== "loading" && root.screenState !== "error"
                onClicked: root.continueRequested()
                focus: true
            }
        }
    }
}
