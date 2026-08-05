// Mission OS — Optional Account Connections (MOS-INS-016)
//
// Sixteenth screen of the Mission OS installer — step 16 of 17,
// appended after the Workspace Confirmation screen (MOS-INS-015,
// step 15) as the third screen of the first-boot experience.
// Implements the source-defined Optional Account Connections structure
// (docs/reference/01_INSTALLER.md § "Screen 18 — Optional Account
// Connections" — the next reference screen after Screen 17 / Workspace
// Confirmation = MOS-INS-015):
//
//   Hosting: place inside MissionWindow (or MissionPage) content and
//   anchor to fill, e.g.  MissionWindow { AccountConnections { anchors.fill: parent } }
//   The component itself sizes to its implicit 1024x768 like MissionPage.
//
//   Header → Stepper Navigation → Main Content → Help Panel → Bottom actions
//
// Displayed items (per reference § "Screen 18 — Optional Account
// Connections"), exactly the reference's content:
//   - The lead-in statement "Mission OS operates fully without online
//     accounts."
//   - The optional integrations — exactly the reference's five, in
//     order: GitHub, GitLab, Nextcloud, Microsoft account, Google
//     account. No integration is invented or omitted.
//   - The reassurance "These are optional conveniences and should
//     never be required to use the operating system."
//
// First Boot Principles (reference § "First Boot Principles") are
// respected: the screen is fast and requires minimal interaction
// (all integrations OFF by default — nothing mandatory), there is no
// mandatory sign-in, and the whole first-boot experience can be
// skipped or revisited later.
//
// Interpretation notes (documented; no authoritative source specifies
// further detail):
//   - No source defines an in-flow account-sign-in mechanism, so this
//     screen is an opt-in review list: every integration is OFF by
//     default (privacy by default — no account required, no telemetry,
//     no cloud services; reference § "Privacy Requirements"). The user
//     may enable an integration; each toggle emits
//     accountConnectionRequested(code, connected) exactly once and the
//     host runs the real authorization flow and feeds the result back
//     into the connected properties (the established host-driven
//     pattern, e.g. SecurityOptions toggles). Connections can also be
//     set up later at any time, so nothing here is mandatory.
//   - Following the established toggle semantics (SecurityOptions /
//     PrivacySetup precedent), onCheckedChanged fires on both
//     programmatic and user-initiated changes, so a host feeding a
//     state back also emits the signal (idempotent for the host).
//     Note the failure path: if the host rejects a connection (e.g. an
//     authorization flow fails) and feeds the disconnected state back,
//     the switch flips and accountConnectionRequested re-emits with
//     connected=false — the host must treat that as the outcome of the
//     request it already received, not as a new user action.
//   - Continue is the primary action: because every integration is
//     optional, there is no validation gate beyond the established
//     loading/error block (validation-before-continue). Back is
//     available (step 16 > 1); Escape → backRequested like every
//     non-terminal screen.
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

    /// Current installer step (1-based); this is step 16 of 17
    property int step: 16

    /// Total number of installer steps (screen registry: 16)
    property int totalSteps: 17

    /// Reduced motion (accessibility)
    property bool reducedMotion: false

    /// Installer/OS version string shown in the header
    property string version: "0.1.0"

    /// Build channel: Stable | Beta | Nightly
    property string buildType: "Nightly"

    /// Available optional account integrations. Each entry:
    /// { code, label, description } — the reference's five integrations
    /// (GitHub, GitLab, Nextcloud, Microsoft account, Google account)
    /// with a brief optional-convenience line. Static fixture the host
    /// may replace wholesale; the host applies the real connection when
    /// accountConnectionRequested fires.
    property var optionalAccounts: [
        { code: "github",
          label: "GitHub",
          description: "Connect to GitHub for repository and development workflows." },
        { code: "gitlab",
          label: "GitLab",
          description: "Connect to GitLab for project hosting and CI/CD workflows." },
        { code: "nextcloud",
          label: "Nextcloud",
          description: "Connect to Nextcloud for file sync and storage." },
        { code: "microsoft",
          label: "Microsoft account",
          description: "Connect a Microsoft account for Microsoft service integration." },
        { code: "google",
          label: "Google account",
          description: "Connect a Google account for Google service integration." }
    ]

    /// Number of optional account integrations (all are shown)
    property int accountCount: root.optionalAccounts.length

    /// Whether GitHub integration is connected (interactive toggle;
    /// OFF by default — optional, privacy by default)
    property bool githubConnected: false

    /// Whether GitLab integration is connected (interactive toggle;
    /// OFF by default — optional, privacy by default)
    property bool gitlabConnected: false

    /// Whether Nextcloud integration is connected (interactive toggle;
    /// OFF by default — optional, privacy by default)
    property bool nextcloudConnected: false

    /// Whether Microsoft account integration is connected (interactive
    /// toggle; OFF by default — optional, privacy by default)
    property bool microsoftConnected: false

    /// Whether Google account integration is connected (interactive
    /// toggle; OFF by default — optional, privacy by default)
    property bool googleConnected: false

    // ── Signals (host wiring) ──────────────────────────────────────
    /// User requested to continue to the next step
    signal continueRequested()
    /// User requested to go back to the previous step
    signal backRequested()
    /// User toggled an optional account integration (code, connected)
    signal accountConnectionRequested(string code, bool connected)
    /// User requested to retry after an error
    signal retryRequested()

    // ── Escape navigates back (Master UX: Back always available) ──
    // No child on this screen consumes Escape (the toggle switches
    // handle Space/Return to flip), so root Escape always → backRequested.
    Keys.onEscapePressed: root.backRequested()

    // ── Responsive helpers ─────────────────────────────────────────
    readonly property bool wideLayout: root.width >= 760
    readonly property bool compactLayout: root.width < 640

    // ── Test hooks (used by tests/tst_account_connections.qml) ─────
    property alias backgroundColor: backgroundRect.color
    property alias headingColor: headingLabel.color
    property alias headingLabel: headingLabel
    property alias accountRows: accountRows
    property alias selectionCaption: selectionCaption
    property alias helpPanel: helpPanel
    property alias backButton: backButton
    property alias continueButton: continueButton
    property alias retryButton: retryButton
    property alias errorBanner: errorBanner
    property alias successBanner: successBanner
    property alias offlineBanner: offlineBanner
    property alias loadingIndicator: loadingIndicator
    property alias contentFlickable: contentFlickable
    property alias contentColumn: contentColumn

    /// Number of connected account integrations
    readonly property int connectedCount: {
        var n = 0
        if (root.githubConnected) n++
        if (root.gitlabConnected) n++
        if (root.nextcloudConnected) n++
        if (root.microsoftConnected) n++
        if (root.googleConnected) n++
        return n
    }

    /// Formatted summary of the current connection state
    readonly property string connectedSummary: {
        if (root.connectedCount === 0)
            return qsTr("No accounts connected — Mission OS works fully without online accounts")
        var parts = []
        if (root.githubConnected) parts.push("GitHub")
        if (root.gitlabConnected) parts.push("GitLab")
        if (root.nextcloudConnected) parts.push("Nextcloud")
        if (root.microsoftConnected) parts.push("Microsoft account")
        if (root.googleConnected) parts.push("Google account")
        return qsTr("Connected: %1").arg(parts.join(", "))
    }

    /// The account object (from `optionalAccounts`) with `code`, or null.
    function getAccount(code) {
        for (var i = 0; i < root.optionalAccounts.length; ++i) {
            if (root.optionalAccounts[i].code === code)
                return root.optionalAccounts[i]
        }
        return null
    }

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
                text: qsTr("Step %1 of %2 · Accounts").arg(root.step).arg(root.totalSteps)
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
                            text: qsTr("Checking account integrations…")
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
                                    text: qsTr("Account options could not be loaded")
                                    font.weight: Typography.weightSemibold
                                    color: Colors.contentOnErrorContainer
                                }
                                Label {
                                    text: qsTr("The optional account information could not be verified. Check the installation and try again.")
                                    font.pixelSize: Typography.bodySmall.size
                                    color: Colors.contentOnErrorContainer
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                            MissionButton {
                                id: retryButton
                                objectName: "accountsRetry"
                                variant: MissionButton.Variant.Secondary
                                text: qsTr("Retry")
                                onClicked: root.retryRequested()
                            }
                        }
                    }

                    // Success (account connections confirmed)
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
                                    text: qsTr("Account preferences saved")
                                    font.weight: Typography.weightSemibold
                                    color: Colors.contentOnSuccessContainer
                                }
                                Label {
                                    text: qsTr("Your account choices will be applied. You can connect or disconnect any integration later at any time.")
                                    font.pixelSize: Typography.bodySmall.size
                                    color: Colors.contentOnSuccessContainer
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }

                    // Offline (informational — works fully offline)
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
                                    text: qsTr("Mission OS works fully offline — no account or internet connection is required. Account integrations can be connected later when you are online.")
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
                        text: qsTr("Optional Account Connections")
                        width: parent.width
                        font.pixelSize: Typography.headline.size
                        font.weight: Typography.headline.weight
                        color: MissionTheme.textPrimary
                        wrapMode: Text.Wrap
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    // ── Lead-in (reference § "Screen 18": "Mission OS
                    //    operates fully without online accounts.") ──
                    Label {
                        text: qsTr("Mission OS operates fully without online accounts. The integrations below are optional conveniences — none are required to use the operating system, and you can set them up later at any time.")
                        width: parent.width
                        font.pixelSize: Typography.bodyLarge.size
                        color: MissionTheme.textSecondary
                        wrapMode: Text.Wrap
                        lineHeight: Typography.lineHeightRelaxed
                    }

                    // ── Optional account integrations (opt-in toggles —
                    //    the reference's five, in order, all OFF by
                    //    default) ──
                    Label {
                        text: qsTr("Optional account integrations")
                        width: parent.width
                        font.pixelSize: Typography.subtitle.size
                        font.weight: Typography.subtitle.weight
                        color: MissionTheme.textPrimary
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    Repeater {
                        id: accountRows
                        model: root.optionalAccounts

                        delegate: Rectangle {
                            id: accountDelegate
                            required property var modelData
                            required property int index

                            // Read the connected state from the root
                            // property that mirrors this integration's
                            // code (host-fed, established toggle pattern
                            // e.g. SecurityOptions).
                            property bool isConnected: {
                                if (modelData.code === "github") return root.githubConnected
                                if (modelData.code === "gitlab") return root.gitlabConnected
                                if (modelData.code === "nextcloud") return root.nextcloudConnected
                                if (modelData.code === "microsoft") return root.microsoftConnected
                                if (modelData.code === "google") return root.googleConnected
                                return false
                            }

                            property alias toggleControl: toggleControl

                            objectName: "accountsItem" + index
                            width: parent.width
                            radius: Radii.card
                            color: MissionTheme.surface
                            border.color: MissionTheme.outlineVariant
                            border.width: 1
                            height: accountColumn.height + Spacing.paddingMedium * 2

                            Column {
                                id: accountColumn
                                x: Spacing.paddingMedium
                                y: Spacing.paddingMedium
                                width: parent.width - Spacing.paddingMedium * 2
                                spacing: Spacing.gapSmall

                                // Title row + toggle (44px touch target)
                                RowLayout {
                                    width: parent.width
                                    spacing: Spacing.gapMedium

                                    Label {
                                        text: modelData.label
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 120
                                        elide: Text.ElideRight
                                        font.pixelSize: Typography.subtitle.size
                                        font.weight: Typography.subtitle.weight
                                        color: MissionTheme.textPrimary
                                        verticalAlignment: Text.AlignVCenter
                                    }

                                    // Connect toggle (Switch, 44px target)
                                    Item {
                                        Layout.preferredWidth: 64
                                        Layout.preferredHeight: Spacing.minimumTouchTarget
                                        Layout.alignment: Qt.AlignVCenter

                                        Switch {
                                            id: toggleControl
                                            objectName: "accountsToggle" + index
                                            checked: isConnected
                                            anchors.centerIn: parent
                                            Layout.preferredHeight: Spacing.minimumTouchTarget
                                            Layout.preferredWidth: 64

                                            onCheckedChanged: {
                                                if (modelData.code === "github") {
                                                    root.githubConnected = checked
                                                    root.accountConnectionRequested("github", checked)
                                                } else if (modelData.code === "gitlab") {
                                                    root.gitlabConnected = checked
                                                    root.accountConnectionRequested("gitlab", checked)
                                                } else if (modelData.code === "nextcloud") {
                                                    root.nextcloudConnected = checked
                                                    root.accountConnectionRequested("nextcloud", checked)
                                                } else if (modelData.code === "microsoft") {
                                                    root.microsoftConnected = checked
                                                    root.accountConnectionRequested("microsoft", checked)
                                                } else if (modelData.code === "google") {
                                                    root.googleConnected = checked
                                                    root.accountConnectionRequested("google", checked)
                                                }
                                            }

                                            indicator: Rectangle {
                                                id: switchTrack
                                                anchors.verticalCenter: parent.verticalCenter
                                                x: toggleControl.width - width - 4
                                                width: 44
                                                height: 24
                                                radius: 12
                                                color: toggleControl.checked
                                                     ? MissionTheme.primary
                                                     : (toggleControl.hovered
                                                        ? MissionTheme.outline
                                                        : MissionTheme.surfaceDim)
                                                border.width: toggleControl.checked ? 0 : 1
                                                border.color: MissionTheme.outline

                                                Behavior on color {
                                                    enabled: !root.reducedMotion
                                                    // Ubuntu Qt 6.10 toolchain: Behavior `duration`
                                                    // convenience property is rejected; use the
                                                    // equivalent `animation:` group property.
                                                    animation: ColorAnimation { duration: Motion.colorChange }
                                                }

                                                Rectangle {
                                                    anchors.fill: parent
                                                    anchors.margins: -3
                                                    radius: 15
                                                    color: "transparent"
                                                    border.color: MissionTheme.focusRing
                                                    border.width: 2
                                                    visible: toggleControl.activeFocus
                                                }

                                                Rectangle {
                                                    x: toggleControl.checked
                                                       ? parent.width - width - 3
                                                       : 3
                                                    width: 18
                                                    height: 18
                                                    radius: 9
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    color: toggleControl.checked
                                                         ? MissionTheme.contentOnPrimary
                                                         : MissionTheme.textSecondary

                                                    Behavior on x {
                                                        enabled: !root.reducedMotion
                                                        NumberAnimation { duration: Motion.durationFast }
                                                    }
                                                }
                                            }

                                            Accessible.role: Accessible.CheckBox
                                            Accessible.name: modelData.label
                                            Accessible.description: modelData.description
                                            Accessible.checked: toggleControl.checked
                                        }
                                    }
                                }

                                // Optional-convenience description
                                Label {
                                    text: modelData.description
                                    width: parent.width
                                    font.pixelSize: Typography.bodySmall.size
                                    color: MissionTheme.textSecondary
                                    wrapMode: Text.Wrap
                                    lineHeight: Typography.lineHeightNormal
                                }
                            }

                            Accessible.role: Accessible.Grouping
                            Accessible.name: modelData.label
                            Accessible.description: modelData.description
                        }
                    }

                    // ── Live selection feedback (reference § "Screen
                    //    18": "These are optional conveniences and
                    //    should never be required to use the operating
                    //    system") ──
                    Label {
                        id: selectionCaption
                        width: parent.width
                        text: qsTr("%1 — these are optional conveniences and are never required to use the operating system").arg(root.connectedSummary)
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
                        text: qsTr("Account integrations are entirely optional. Mission OS works fully without online accounts — no account, no telemetry, and no cloud service is ever required. Connecting an integration only adds convenience for that specific service.")
                        width: parent.width
                        font.pixelSize: Typography.bodySmall.size
                        color: MissionTheme.textSecondary
                        wrapMode: Text.Wrap
                        lineHeight: Typography.lineHeightNormal
                    }

                    Item { width: 1; height: Spacing.gapSmall }

                    Label {
                        text: qsTr("You can skip this step entirely and connect any integration later at any time. Nothing here is mandatory, and nothing affects how the operating system works.")
                        width: parent.width
                        font.pixelSize: Typography.bodySmall.size
                        color: MissionTheme.textSecondary
                        wrapMode: Text.Wrap
                        lineHeight: Typography.lineHeightNormal
                    }

                    Item { width: 1; height: Spacing.gapSmall }

                    Label {
                        text: qsTr("Privacy by default — no account, no telemetry, no cloud required.")
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
                objectName: "accountsBack"
                variant: MissionButton.Variant.Secondary
                text: qsTr("Back")
                enabled: root.step > 1
                onClicked: root.backRequested()
            }

            Item { Layout.fillWidth: true }

            // Continue (primary action; disabled while loading/error so it
            // never silently advances when validation is pending — every
            // integration is optional, so no further gate applies on this
            // opt-in screen)
            MissionButton {
                id: continueButton
                objectName: "accountsContinue"
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
