// Mission OS — System Ready (MOS-INS-017)
//
// Seventeenth screen of the Mission OS installer — step 17 of 17,
// appended after the Optional Account Connections screen (MOS-INS-016,
// step 16) as the final screen of the first-boot experience.
// Implements the source-defined System Ready structure
// (docs/reference/01_INSTALLER.md § "Screen 19 — System Ready" — the
// next reference screen after Screen 18 / Optional Account Connections
// = MOS-INS-016, following the ordering rule established for
// MOS-INS-014/015/016):
//
//   Hosting: place inside MissionWindow (or MissionPage) content and
//   anchor to fill, e.g.  MissionWindow { SystemReady { anchors.fill: parent } }
//   The component itself sizes to its implicit 1024x768 like MissionPage.
//
//   Header → Stepper Navigation → Main Content → Help Panel → Bottom actions
//
// Displayed items (per reference § "Screen 19 — System Ready"),
// exactly the reference's eight items:
//   - "Installation complete"  (heading — reference display item 1,
//     following the established heading rule from Completion /
//     First Boot Welcome: the heading is the reference's first display
//     item)
//   - "Recovery configured"    (read-only status row)
//   - "Security status"        (read-only status row)
//   - "Privacy status"         (read-only status row)
//   - "Open Mission Hub"       (button → missionHubRequested())
//   - "Open Settings"          (button → settingsRequested())
//   - "Open Documentation"     (button → documentationRequested())
//   - "Finish"                 (primary action → finishRequested())
//
// The reference closes the screen with: "After completion, the user
// enters the Mission OS desktop." — Finish is therefore the terminal
// action of the first-boot experience.
//
// First Boot Principles (reference § "First Boot Principles") are
// respected: the screen is fast and requires minimal interaction (a
// single Finish); there are no unnecessary tutorials, no marketing
// content, and no mandatory sign-in; trust is reinforced through the
// privacy-by-default copy and the always-available links into Mission
// Hub, Settings, and Documentation.
//
// Interpretation notes (documented; no authoritative source specifies
// further detail):
//   - The status rows are read-only and host-fed: `systemStatus` is a
//     fixture of { code, label, value } entries that the host may
//     replace wholesale with the real recovery/security/privacy state.
//     The default values ("Configured", "Protected", "Privacy by
//     default") are UNSPECIFIED by the reference — they are least-
//     assumption fixtures consistent with the install flow (recovery
//     is configured during installation, security/privacy are
//     hardened by default) and are not claimed to be authoritative.
//   - The three open actions are tertiary buttons that emit
//     *Requested signals; the host opens the real destination
//     (Mission Hub, Settings, Documentation — offline where
//     available), the same host-driven pattern as MOS-INS-014
//     Documentation/Release notes and MOS-INS-012 report actions.
//   - Finish is the primary action: validation-before-continue is
//     respected (Finish disabled while loading/error). There is no
//     Continue on this terminal screen (the reference defines Finish,
//     not Continue — same as the Completion terminal screen which has
//     no Continue). Back remains available (step 17 > 1, wireframe
//     "Back navigation always available"); the host decides what
//     backRequested() means here. Escape → backRequested like every
//     non-terminal first-boot screen (MOS-INS-014/015/016).
//   - States follow the wireframe (empty · loading · error · success ·
//     offline). No host/change signal is emitted during initialization.
//
// Design-system compliance:
//   - Tokens only (Colors, Typography, Spacing, Radii, Motion, MissionTheme)
//   - Light + dark themes via MissionTheme (driven by host)
//   - Keyboard navigation with visible focus states
//   - WCAG AA-oriented contrast, reduced-motion aware
//   - Responsive reflow per docs/design/14_RESPONSIVE_RULES.md
//   - 44px minimum touch targets
//   - 1024×768 minimum supported installer resolution

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

    /// Current installer step (1-based); this is step 17 of 17
    property int step: 17

    /// Total number of installer steps (screen registry: 17)
    property int totalSteps: 17

    /// Reduced motion (accessibility)
    property bool reducedMotion: false

    /// Installer/OS version string shown in the header
    property string version: "0.1.0"

    /// Build channel: Stable | Beta | Nightly
    property string buildType: "Nightly"

    /// The system-ready status rows — the reference's display items 2–4
    /// exactly (Recovery configured, Security status, Privacy status).
    /// Each entry: { code, label, value }. Read-only rows; the host may
    /// replace this fixture wholesale with the real recovery/security/
    /// privacy state. Default values are UNSPECIFIED by the reference
    /// and are least-assumption fixtures (see header interpretation
    /// notes).
    /// Default empty — host-fed only; no fabricated status claims (FABRICATION-8)
    property var systemStatus: []

    /// Number of system status rows (all are shown)
    property int statusCount: root.systemStatus.length

    // ── Signals (host wiring) ──────────────────────────────────────
    /// User requested to finish the first-boot experience and enter
    /// the Mission OS desktop (reference § "Screen 19": "After
    /// completion, the user enters the Mission OS desktop.")
    signal finishRequested()
    /// User requested to go back to the previous step
    signal backRequested()
    /// User requested to open Mission Hub
    signal missionHubRequested()
    /// User requested to open Settings
    signal settingsRequested()
    /// User requested documentation
    signal documentationRequested()
    /// User requested to retry after an error
    signal retryRequested()

    // ── Escape navigates back (Master UX: Back always available) ──
    // No child on this screen consumes Escape (the buttons handle
    // Space/Return), so root Escape always → backRequested.
    Keys.onEscapePressed: root.backRequested()

    // ── Responsive helpers ─────────────────────────────────────────
    readonly property bool wideLayout: root.width >= 760
    readonly property bool compactLayout: root.width < 640

    /// Height of one status row (label + value). Named once so the
    /// ListView height formula and the delegate height can never drift
    /// apart (established pattern).
    readonly property int detailRowHeight: 44

    // ── Read-back helpers (host wiring / tests) ────────────────────
    /// The status object (from `systemStatus`) with `code`, or null.
    function getStatus(code) {
        for (var i = 0; i < root.systemStatus.length; ++i) {
            if (root.systemStatus[i].code === code)
                return root.systemStatus[i]
        }
        return null
    }

    // ── Test hooks (used by tests/tst_system_ready.qml) ────────────
    property alias backgroundColor: backgroundRect.color
    property alias headingColor: headingLabel.color
    property alias headingLabel: headingLabel
    property alias statusList: statusList
    property alias missionHubButton: missionHubButton
    property alias settingsButton: settingsButton
    property alias documentationButton: documentationButton
    property alias helpPanel: helpPanel
    property alias backButton: backButton
    property alias finishButton: finishButton
    property alias retryButton: retryButton
    property alias errorBanner: errorBanner
    property alias successBanner: successBanner
    property alias offlineBanner: offlineBanner
    property alias loadingIndicator: loadingIndicator
    property alias contentFlickable: contentFlickable
    property alias contentColumn: contentColumn

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
                text: qsTr("Step %1 of %2 · System Ready").arg(root.step).arg(root.totalSteps)
                font.pixelSize: Typography.bodySmall.size
                font.weight: Typography.weightSemibold
                color: MissionTheme.textSecondary
                elide: Text.ElideRight
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }

            Item { Layout.fillWidth: true }

            // Step segments — responsive dot sizing: compact or
            // non-wide layouts use 8px dots to avoid imbalance
            // when the help panel is hidden (sizing audit fix for
            // the 640–759px responsive gap).
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
                            text: qsTr("Preparing system status…")
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
                        // invisible even when `visible` is true (the
                        // proven fix from MOS-INS-001 onward).
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
                                    text: qsTr("System status could not be loaded")
                                    font.weight: Typography.weightSemibold
                                    color: Colors.contentOnErrorContainer
                                }
                                Label {
                                    text: qsTr("The system readiness information could not be verified. Check the installation and try again.")
                                    font.pixelSize: Typography.bodySmall.size
                                    color: Colors.contentOnErrorContainer
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                            MissionButton {
                                id: retryButton
                                objectName: "systemRetry"
                                variant: MissionButton.Variant.Secondary
                                text: qsTr("Retry")
                                onClicked: root.retryRequested()
                            }
                        }
                    }

                    // Success (system ready — recovery, security and
                    // privacy confirmed)
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
                                    text: qsTr("Mission OS is ready")
                                    font.weight: Typography.weightSemibold
                                    color: Colors.contentOnSuccessContainer
                                }
                                Label {
                                    text: qsTr("Your system is installed, verified, and ready to use. Choose how to continue below.")
                                    font.pixelSize: Typography.bodySmall.size
                                    color: Colors.contentOnSuccessContainer
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }

                    // Offline (informational — the installed system
                    // works fully offline)
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
                                    text: qsTr("Mission OS works fully offline — no account or internet connection is required. Everything you need is already on your system.")
                                    font.pixelSize: Typography.bodySmall.size
                                    color: MissionTheme.textSecondary
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }

                    // ── Heading (reference display item 1:
                    //    "Installation complete") ──
                    Label {
                        id: headingLabel
                        text: qsTr("Installation complete")
                        width: parent.width
                        font.pixelSize: Typography.headline.size
                        font.weight: Typography.headline.weight
                        color: MissionTheme.textPrimary
                        wrapMode: Text.Wrap
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    Label {
                        text: qsTr("Mission OS is installed and ready to use. Your system is configured with recovery, security, and privacy by default — after finishing this step you enter the Mission OS desktop.")
                        width: parent.width
                        font.pixelSize: Typography.bodyLarge.size
                        color: MissionTheme.textSecondary
                        wrapMode: Text.Wrap
                        lineHeight: Typography.lineHeightRelaxed
                    }

                    // ── System status (reference display items 2–4;
                    //    read-only — the host drives the values via the
                    //    systemStatus fixture) ──
                    Label {
                        text: qsTr("Your system")
                        width: parent.width
                        font.pixelSize: Typography.subtitle.size
                        font.weight: Typography.subtitle.weight
                        color: MissionTheme.textPrimary
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    ListView {
                        id: statusList
                        objectName: "systemReadyStatusList"
                        width: parent.width
                        height: Math.max(0, root.systemStatus.length * root.detailRowHeight
                                         + (root.systemStatus.length - 1) * Spacing.gapTiny)
                        clip: true
                        model: root.systemStatus
                        spacing: Spacing.gapTiny
                        ScrollIndicator.vertical: ScrollIndicator {}
                        Accessible.role: Accessible.List
                        Accessible.name: qsTr("System readiness status")

                        delegate: Rectangle {
                            id: statusDelegate
                            required property var modelData
                            required property int index

                            // Read-only rows are not Tab stops; the
                            // objectName is used by the keyboard-focus
                            // test to verify they are NOT in the chain.
                            objectName: "systemReadyStatusItem" + index
                            width: statusList.width
                            height: root.detailRowHeight
                            radius: Radii.input
                            color: MissionTheme.surface

                            // Test hook: expose the rendered value label
                            // so tests can verify the row reflects the
                            // fixture values.
                            property alias valueLabel: statusValueLabel

                            // Bottom hairline separator between rows
                            Rectangle {
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    bottom: parent.bottom
                                }
                                height: 1
                                color: MissionTheme.outlineVariant
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Spacing.paddingMedium
                                anchors.rightMargin: Spacing.paddingMedium
                                spacing: Spacing.gapMedium

                                // Status label (left)
                                Label {
                                    text: modelData.label
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    font.pixelSize: Typography.body.size
                                    color: MissionTheme.textSecondary
                                    verticalAlignment: Text.AlignVCenter
                                }

                                // Status value (right). Always mirrors
                                // the fixture entry for this code.
                                Label {
                                    id: statusValueLabel
                                    text: modelData.value
                                    elide: Text.ElideRight
                                    font.pixelSize: Typography.body.size
                                    font.weight: Typography.weightSemibold
                                    color: MissionTheme.textPrimary
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }

                            Accessible.role: Accessible.ListItem
                            Accessible.name: qsTr("%1: %2").arg(modelData.label).arg(statusValueLabel.text)
                        }
                    }

                    // ── Open actions (reference display items 5–7:
                    //    Open Mission Hub, Open Settings, Open
                    //    Documentation — always reachable). A Flow so
                    //    the buttons wrap instead of overflowing on
                    //    compact widths (responsive reflow per
                    //    docs/design/14_RESPONSIVE_RULES.md). ──
                    Flow {
                        width: parent.width
                        spacing: Spacing.gapMedium
                        MissionButton {
                            id: missionHubButton
                            objectName: "systemMissionHub"
                            variant: MissionButton.Variant.Tertiary
                            text: qsTr("Open Mission Hub")
                            onClicked: root.missionHubRequested()
                        }
                        MissionButton {
                            id: settingsButton
                            objectName: "systemSettings"
                            variant: MissionButton.Variant.Tertiary
                            text: qsTr("Open Settings")
                            onClicked: root.settingsRequested()
                        }
                        MissionButton {
                            id: documentationButton
                            objectName: "systemDocumentation"
                            variant: MissionButton.Variant.Tertiary
                            text: qsTr("Open Documentation")
                            onClicked: root.documentationRequested()
                        }
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
                        text: qsTr("Mission OS is installed and ready. Finish to enter the Mission OS desktop — you can open Mission Hub, Settings, or Documentation from this screen or at any time later.")
                        width: parent.width
                        font.pixelSize: Typography.bodySmall.size
                        color: MissionTheme.textSecondary
                        wrapMode: Text.Wrap
                        lineHeight: Typography.lineHeightNormal
                    }

                    Item { width: 1; height: Spacing.gapSmall }

                    Label {
                        text: qsTr("Recovery is configured and your security and privacy are protected by default. You can review or adjust all of these from Mission Hub at any time.")
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
    // Bottom action bar (Back / Finish)
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
                objectName: "systemBack"
                variant: MissionButton.Variant.Secondary
                text: qsTr("Back")
                enabled: root.step > 1
                onClicked: root.backRequested()
            }

            Item { Layout.fillWidth: true }

            // Finish (primary action; disabled while loading/error so it
            // never silently advances when validation is pending — the
            // reference defines Finish, not Continue, as the terminal
            // action of the first-boot experience)
            MissionButton {
                id: finishButton
                objectName: "systemFinish"
                variant: MissionButton.Variant.Primary
                text: qsTr("Finish")
                loading: root.screenState === "loading"
                enabled: root.screenState !== "loading" && root.screenState !== "error"
                onClicked: root.finishRequested()
                focus: true
            }
        }
    }
}
