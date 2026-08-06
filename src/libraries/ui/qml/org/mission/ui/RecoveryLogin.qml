// Mission OS — Recovery Login (MOS-LCK-004)
//
// Fourth and final screen of the Mission OS lock/login family.
// Implements the source-defined Recovery Login structure
// (docs/wireframes/02_LOCK_SCREEN.md + docs/design/03_SCREEN_REGISTRY.md
// MOS-LCK-004 "Recovery Login"):
//
//   Hosting: place inside MissionWindow (or MissionPage) content and
//   anchor to fill, e.g.  MissionWindow { RecoveryLogin { anchors.fill: parent } }
//   The component itself sizes to its implicit 1024x768 like MissionPage.
//
//   Layout (per wireframe): Wallpaper → Clock → Authentication Card →
//   Power Controls → Accessibility
//
// Components (per wireframe):
//   - User Avatar (preset token-colored avatar + initial; no image
//     asset is shipped — same inline approach as MOS-LCK-001/002/003)
//   - Recovery Key Field (the recovery credential replaces the
//     password/PIN fields of the other family screens; it is a masked
//     text field styled inline like every family field — the recovery
//     key is a printable secret generated during installation per
//     docs/engineering/SECURITY_ARCHITECTURE.md §LUKS "Optional:
//     recovery key (generated during installation, printable)" and
//     "Key slots: 1 (user passphrase) + 1 (recovery key) + 1 (TPM,
//     optional)")
//   - Accessibility entry button (Accessibility Menu content is
//     host-side, like MOS-LCK-001/002/003)
//   - Network Status + Battery Status indicators
//   - Power Menu (Shutdown / Restart / Suspend)
//
// States (per wireframe): locked · authenticating · incorrect ·
// recovery required. The family state vocabulary is shared so a host
// can drive all four screens with the same state machine. On the
// recovery screen itself the "recovery required" banner is not shown:
// this screen IS the recovery path (MOS-LCK-001/002/003 route here via
// recoveryRequested), so its states are locked · authenticating ·
// incorrect — "incorrect" renders the "Incorrect recovery key" error
// banner (docs/reference/07_RECOVERY_CENTER.md lists "incorrect
// recovery key" as a recovery state).
//
// What distinguishes Recovery Login (MOS-LCK-004) from the rest of the
// family:
//   Normal sign-in (password MOS-LCK-001/002, PIN MOS-LCK-003) is
//   unavailable; the user proves identity with the recovery key —
//   RUNTIME_ARCHITECTURE.md boot failure handling: "LUKS unlock fails →
//   Retry prompt. Recovery key option. Emergency shell" and the boot
//   flow "LUKS2 unlock (password, TPM, or recovery key)". The screen
//   collects the key and emits recoveryLoginRequested(recoveryKey); the
//   host verifies it (LUKS/cryptsetup or an equivalent recovery backend).
//
// Interpretation notes (documented — no authoritative source specifies
// further detail):
//   - No wallpaper asset is shipped yet, so the backdrop is a calm
//     token-only vertical gradient plus a subtle scrim; the host may
//     layer a real wallpaper behind the component (same as MOS-LCK-001).
//   - The clock ticks live from the system clock. Hosts that need to
//     pin the displayed text set clockTimeText/clockDateText and
//     clockRunning = false (the timer only overwrites when running).
//   - The recovery key field is masked (echoMode Password) like every
//     credential field in the family: recovery keys are secrets and
//     shoulder-surfing resistance matters more than the convenience of
//     reading the long printable string back.
//   - The key is submitted as entered (no auto-formatting): recovery
//     key formats are host/deployment-specific, and the installer may
//     export them grouped or continuous (SECURITY_ARCHITECTURE §LUKS).
//   - Authentication is host-driven: the screen collects the key and
//     emits recoveryLoginRequested(recoveryKey); real verification
//     (LUKS/cryptsetup) is the host's job. Normal sign-in is
//     MOS-LCK-001/002/003 territory — this screen only routes back
//     toward them via signInRequested (the mirror of PIN Entry's
//     passwordRequested route), it does not implement the password/PIN
//     forms.
//   - The entered key is NOT cleared automatically on "incorrect": the
//     Retry banner is the recovery path and the host decides whether to
//     clear (same blocked-while-error contract as every family screen
//     and every installer screen's Continue).
//   - Escape is deliberately unmapped (same contract as MOS-LCK-001/002/003
//     and the installer Completion screen): the recovery screen must not
//     dismiss itself — the host owns any escape behavior.
//
// Design-system compliance:
//   - Tokens only (Colors, Typography, Spacing, Radii, Motion, MissionTheme)
//   - Light + dark themes via MissionTheme (driven by host)
//   - Keyboard navigation with visible focus states; recovery key field
//     focused on load (keyboard-first, per wireframe accessibility)
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
    /// Authentication state: "locked" | "authenticating" | "incorrect"
    /// (family vocabulary; "recovery required" is not shown here — this
    /// screen IS the recovery path, see interpretation notes)
    property string authState: "locked"

    /// Reduced motion (accessibility)
    property bool reducedMotion: false

    /// Signed-in user display name shown with the avatar
    property string userName: ""

    /// Live clock time text (e.g. "14:32"). The component updates it
    /// from the system clock while clockRunning is true; hosts pin it
    /// by setting it and disabling the timer.
    property string clockTimeText: ""
    /// Live clock date text (e.g. "Wednesday, August 5"). See clockTimeText.
    property string clockDateText: ""
    /// When true, a 30s timer keeps the clock text current
    property bool clockRunning: true

    /// Network status label (e.g. "Connected" / "Offline") — host-driven
    property string networkStatusText: qsTr("Connected")
    /// Whether the network is up (drives the status dot color; the dot
    /// is never the only indicator — the label always carries the text)
    property bool networkConnected: true

    /// Battery status label (e.g. "100%") — host-driven
    property string batteryStatusText: "100%"
    /// Battery level 0-100 (drives the fill width + semantic color)
    property int batteryLevel: 100

    // ── Signals (host wiring) ──────────────────────────────────────
    /// User requested to regain access with the entered recovery key
    signal recoveryLoginRequested(string recoveryKey)
    /// User requested to go back to normal sign-in (MOS-LCK-001/002/003)
    signal signInRequested()
    /// User requested to retry after an incorrect recovery key
    signal retryRequested()
    /// User requested accessibility configuration
    signal accessibilityRequested()
    /// User requested system shutdown
    signal shutdownRequested()
    /// User requested system restart
    signal restartRequested()
    /// User requested system suspend
    signal suspendRequested()

    // Escape is deliberately unmapped (see interpretation notes): the
    // recovery screen must not dismiss itself. No Keys.onEscapePressed here.

    // ── Responsive helpers ─────────────────────────────────────────
    // No help panel on the lock family, so there is no wide-layout
    // variant (unlike the installer screens); compactLayout trims the
    // date line so the clock never crowds the auth card on narrow
    // widths (docs/design/14_RESPONSIVE_RULES.md reflow).
    readonly property bool compactLayout: root.width < 640

    // ── Derived helpers ────────────────────────────────────────────
    /// Avatar initial (first letter of the user name, or a neutral dot)
    readonly property string avatarInitial: root.userName.length > 0
                                            ? root.userName.charAt(0).toUpperCase()
                                            : "\u2022"
    /// Backdrop base color (theme-aware; test hook). Equivalent to the
    /// wallpaper gradient's top stop, which is bound to
    /// MissionTheme.background.
    readonly property color backdropColor: MissionTheme.background

    // ── Clock helpers ──────────────────────────────────────────────
    /// Refresh the clock text from the system clock (host wiring / tests)
    function updateClock() {
        var now = new Date()
        root.clockTimeText = Qt.formatTime(now, "HH:mm")
        root.clockDateText = Qt.formatDate(now, Qt.DefaultLocaleLongDate)
    }

    // ── Auth-state helpers ─────────────────────────────────────────
    /// Set the authentication state (host wiring; mirrors authState)
    function setAuthState(state) {
        root.authState = state
    }

    // ── Recovery helpers ───────────────────────────────────────────
    // The recovery key field is the single source of truth for the
    // entered key (same contract as the password fields on
    // MOS-LCK-001/002 — no mirrored property to drift).
    /// Clear the entered recovery key (while "locked"; host wiring / tests)
    function clearKey() {
        if (root.authState !== "locked")
            return
        root.recoveryKeyField.clear()
    }

    /// Submit the entered recovery key. Only emits while "locked"
    /// (keyboard-safe: Return on a blocked screen must not fire).
    function submitRecoveryKey() {
        if (root.authState !== "locked")
            return
        root.recoveryLoginRequested(root.recoveryKeyField.text)
    }

    // ── Test hooks (used by tests/tst_recovery_login.qml) ──────────
    property alias backdropRect: wallpaperRect
    property alias clockTimeLabel: clockTimeLabel
    property alias clockDateLabel: clockDateLabel
    property alias networkChip: networkChip
    property alias networkStatusLabel: networkStatusLabel
    property alias networkDot: networkDot
    property alias batteryChip: batteryChip
    property alias batteryStatusLabel: batteryStatusLabel
    property alias batteryFill: batteryFill
    property alias avatarPreview: avatarPreview
    property alias userNameLabel: userNameLabel
    property alias recoveryHintLabel: recoveryHintLabel
    property alias recoveryKeyField: recoveryKeyField
    property alias recoverButton: recoverButton
    property alias signInButton: signInButton
    property alias powerButton: powerButton
    property alias powerMenu: powerMenu
    property alias shutdownItem: shutdownItem
    property alias restartItem: restartItem
    property alias suspendItem: suspendItem
    property alias accessibilityButton: accessibilityButton
    property alias retryButton: retryButton
    property alias errorBanner: errorBanner
    property alias authenticatingIndicator: authenticatingIndicator

    // ── Wallpaper backdrop (token gradient + scrim) ────────────────
    Rectangle {
        id: wallpaperRect
        anchors.fill: parent
        // Calm token-only gradient standing in for the wallpaper until a
        // real wallpaper asset ships (see interpretation notes).
        gradient: Gradient {
            GradientStop { position: 0.0; color: MissionTheme.background }
            GradientStop { position: 1.0; color: MissionTheme.surfaceVariant }
        }

        // Subtle scrim improves contrast for the card + clock
        Rectangle {
            anchors.fill: parent
            color: Colors.scrim
            opacity: MissionTheme.darkMode ? 0.0 : 0.06
        }
    }

    // ══════════════════════════════════════════════════════════════
    // Centered stack: Clock → Status → Authentication Card
    // ══════════════════════════════════════════════════════════════
    Item {
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            bottom: bottomBar.top
        }

        Column {
            id: centerStack
            anchors.centerIn: parent
            width: Math.min(420, root.width - Spacing.paddingLarge * 2)
            spacing: Spacing.gapLarge

            // ── Clock ──
            // (Labels center themselves via width + horizontalAlignment;
            // QtQuick Column has no horizontalAlignment property.)
            Column {
                width: parent.width
                spacing: Spacing.gapTiny

                Label {
                    id: clockTimeLabel
                    objectName: "recoveryClockTime"
                    text: root.clockTimeText
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Typography.displayLarge.size
                    font.weight: Typography.displayLarge.weight
                    font.letterSpacing: Typography.letterSpacingTight
                    color: MissionTheme.textPrimary
                    Accessible.role: Accessible.StaticText
                    Accessible.name: qsTr("Current time: %1").arg(text)
                }

                Label {
                    id: clockDateLabel
                    objectName: "recoveryClockDate"
                    text: root.clockDateText
                    visible: !root.compactLayout
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Typography.bodyLarge.size
                    color: MissionTheme.textSecondary
                    Accessible.role: Accessible.StaticText
                    Accessible.name: qsTr("Current date: %1").arg(text)
                }
            }

            // ── Status indicators (Network + Battery) ──
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Spacing.gapMedium

                // Network status chip
                Rectangle {
                    id: networkChip
                    height: Spacing.minimumTouchTarget - Spacing.gapSmall * 2
                    width: networkRow.implicitWidth + Spacing.paddingMedium * 2
                    radius: Radii.chip
                    color: MissionTheme.surface
                    border.color: MissionTheme.outlineVariant
                    border.width: 1

                    RowLayout {
                        id: networkRow
                        anchors.centerIn: parent
                        spacing: Spacing.gapSmall

                        Rectangle {
                            id: networkDot
                            Layout.preferredWidth: 6
                            Layout.preferredHeight: 6
                            radius: 3
                            color: root.networkConnected ? MissionTheme.success
                                                         : MissionTheme.textTertiary
                        }
                        Label {
                            id: networkStatusLabel
                            objectName: "recoveryNetworkStatus"
                            text: root.networkStatusText
                            font.pixelSize: Typography.bodySmall.size
                            color: MissionTheme.textPrimary
                        }
                    }

                    Accessible.role: Accessible.Grouping
                    Accessible.name: qsTr("Network status: %1").arg(root.networkStatusText)
                }

                // Battery status chip
                Rectangle {
                    id: batteryChip
                    height: Spacing.minimumTouchTarget - Spacing.gapSmall * 2
                    width: batteryRow.implicitWidth + Spacing.paddingMedium * 2
                    radius: Radii.chip
                    color: MissionTheme.surface
                    border.color: MissionTheme.outlineVariant
                    border.width: 1

                    RowLayout {
                        id: batteryRow
                        anchors.centerIn: parent
                        spacing: Spacing.gapSmall

                        // Mini battery bar (token colors; label carries
                        // the text so color is never the only indicator)
                        Rectangle {
                            Layout.preferredWidth: 18
                            Layout.preferredHeight: 8
                            radius: 2
                            color: MissionTheme.surfaceDim
                            border.color: MissionTheme.outline
                            border.width: 1

                            Rectangle {
                                id: batteryFill
                                anchors {
                                    left: parent.left
                                    top: parent.top
                                    bottom: parent.bottom
                                    margins: 1
                                }
                                width: Math.max(2, (parent.width - 2) *
                                                   Math.min(1, Math.max(0, root.batteryLevel / 100)))
                                radius: 1
                                color: root.batteryLevel <= 20 ? MissionTheme.warning
                                                               : MissionTheme.success
                            }
                        }
                        Label {
                            id: batteryStatusLabel
                            objectName: "recoveryBatteryStatus"
                            text: root.batteryStatusText
                            font.pixelSize: Typography.bodySmall.size
                            color: MissionTheme.textPrimary
                        }
                    }

                    Accessible.role: Accessible.Grouping
                    Accessible.name: qsTr("Battery status: %1").arg(root.batteryStatusText)
                }
            }

            // ── Authentication Card ──
            Rectangle {
                width: parent.width
                radius: Radii.dialog
                color: MissionTheme.surface
                border.color: MissionTheme.outline
                border.width: 1
                // Explicit height from content (the proven pattern — a
                // plain layout would otherwise collapse the card).
                height: authColumn.height + Spacing.paddingLarge * 2

                Column {
                    id: authColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                    }
                    anchors.margins: Spacing.paddingLarge
                    spacing: Spacing.gapMedium

                    // ── User avatar + name ──
                    Rectangle {
                        id: avatarPreview
                        objectName: "recoveryAvatar"
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 64
                        height: 64
                        radius: 32
                        color: MissionTheme.primary

                        Label {
                            anchors.centerIn: parent
                            text: root.avatarInitial
                            font.pixelSize: Typography.titleLarge.size
                            font.weight: Typography.weightBold
                            color: MissionTheme.contentOnPrimary
                        }

                        Accessible.role: Accessible.Graphic
                        Accessible.name: root.userName.length > 0
                                         ? qsTr("User avatar for %1").arg(root.userName)
                                         : qsTr("User avatar")
                    }

                    Label {
                        id: userNameLabel
                        objectName: "recoveryUserName"
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.userName.length > 0 ? root.userName : qsTr("Guest")
                        font.pixelSize: Typography.subtitle.size
                        font.weight: Typography.subtitle.weight
                        color: MissionTheme.textPrimary
                        Accessible.role: Accessible.StaticText
                        Accessible.name: text
                    }

                    // ── Authenticating (non-blocking progress) ──
                    RowLayout {
                        id: authenticatingIndicator
                        visible: root.authState === "authenticating"
                        width: parent.width
                        spacing: Spacing.gapMedium

                        Label {
                            text: qsTr("Verifying recovery key…")
                            font.pixelSize: Typography.bodySmall.size
                            color: MissionTheme.textSecondary
                        }
                        Rectangle {
                            id: authLoadingTrack
                            Layout.fillWidth: true
                            Layout.preferredHeight: 4
                            radius: 2
                            color: MissionTheme.surfaceDim
                            Rectangle {
                                id: authLoadingFill
                                width: 96
                                height: 4
                                radius: 2
                                color: MissionTheme.primary
                                x: -96
                                NumberAnimation on x {
                                    running: root.authState === "authenticating" &&
                                             !root.reducedMotion
                                    from: -96
                                    to: authLoadingTrack.width
                                    duration: Motion.durationSlow
                                    loops: Animation.Infinite
                                }
                            }
                        }
                    }

                    // ── Incorrect recovery key (error + Retry) ──
                    Rectangle {
                        id: errorBanner
                        visible: root.authState === "incorrect"
                        width: parent.width
                        // Explicit height from content (proven pattern)
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
                                    text: qsTr("Incorrect recovery key")
                                    font.weight: Typography.weightSemibold
                                    color: Colors.contentOnErrorContainer
                                }
                                Label {
                                    text: qsTr("The recovery key you entered is incorrect. Try again.")
                                    font.pixelSize: Typography.bodySmall.size
                                    color: Colors.contentOnErrorContainer
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                            MissionButton {
                                id: retryButton
                                objectName: "recoveryRetry"
                                variant: MissionButton.Variant.Secondary
                                text: qsTr("Retry")
                                onClicked: root.retryRequested()
                            }
                        }
                    }

                    // ── Recovery key hint ──
                    Label {
                        id: recoveryHintLabel
                        objectName: "recoveryHint"
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: qsTr("Enter your recovery key")
                        font.pixelSize: Typography.bodyLarge.size
                        font.weight: Typography.weightMedium
                        color: MissionTheme.textPrimary
                        Accessible.role: Accessible.StaticText
                        Accessible.name: text
                    }

                    // ── Recovery key field (masked, like every family
                    //    credential field) ──
                    Column {
                        width: parent.width
                        spacing: Spacing.gapTiny

                        TextField {
                            id: recoveryKeyField
                            objectName: "recoveryKeyField"
                            width: parent.width
                            implicitHeight: Spacing.minimumTouchTarget
                            echoMode: TextInput.Password
                            placeholderText: qsTr("Recovery key")
                            font.pixelSize: Typography.body.size
                            color: MissionTheme.textPrimary
                            placeholderTextColor: MissionTheme.textTertiary
                            selectByMouse: true
                            leftPadding: Spacing.paddingMedium
                            rightPadding: Spacing.paddingMedium
                            enabled: root.authState === "locked"
                            // Keyboard-first: focused as soon as the
                            // screen shows (locked state only).
                            focus: root.authState === "locked"
                            // Enter submits (wireframe: keyboard-first)
                            onAccepted: root.submitRecoveryKey()
                            background: Rectangle {
                                radius: Radii.input
                                color: MissionTheme.surface
                                border.width: recoveryKeyField.activeFocus ? 2 : 1
                                border.color: recoveryKeyField.activeFocus ? MissionTheme.focusRing
                                                                           : MissionTheme.outline
                            }
                            Accessible.role: Accessible.EditableText
                            Accessible.name: qsTr("Recovery key")
                            Accessible.description: qsTr("Enter your recovery key to regain access")
                        }
                    }

                    // ── Recover access (primary action) ──
                    MissionButton {
                        id: recoverButton
                        objectName: "recoveryRecover"
                        anchors.horizontalCenter: parent.horizontalCenter
                        implicitWidth: 200
                        variant: MissionButton.Variant.Primary
                        text: qsTr("Recover access")
                        loading: root.authState === "authenticating"
                        enabled: root.authState === "locked"
                        onClicked: root.submitRecoveryKey()
                    }

                    // ── Back to sign-in (route to MOS-LCK-001/002/003) ──
                    MissionButton {
                        id: signInButton
                        objectName: "recoverySignIn"
                        anchors.horizontalCenter: parent.horizontalCenter
                        variant: MissionButton.Variant.Tertiary
                        text: qsTr("Back to sign-in")
                        enabled: root.authState === "locked"
                        onClicked: root.signInRequested()
                        Accessible.description: qsTr("Return to password or PIN sign-in")
                    }
                }
            }
        }
    }

    // ══════════════════════════════════════════════════════════════
    // Bottom bar: Power Controls + Accessibility (wireframe layout)
    // ══════════════════════════════════════════════════════════════
    Rectangle {
        id: bottomBar
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: Spacing.minimumTouchTarget + Spacing.paddingMedium * 2
        color: "transparent"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Spacing.paddingPage
            anchors.rightMargin: Spacing.paddingPage
            spacing: Spacing.gapMedium

            // Accessibility (left; wireframe lists it last — kept
            // reachable on every width)
            MissionButton {
                id: accessibilityButton
                objectName: "recoveryAccessibility"
                variant: MissionButton.Variant.Secondary
                text: qsTr("Accessibility")
                onClicked: root.accessibilityRequested()
            }

            Item { Layout.fillWidth: true }

            // Power menu (Shutdown / Restart / Suspend)
            MissionButton {
                id: powerButton
                objectName: "recoveryPower"
                variant: MissionButton.Variant.Secondary
                text: qsTr("Power")
                onClicked: powerMenu.popup(powerButton, 0, powerButton.height)
                Accessible.description: qsTr("Shutdown, restart, or suspend")
            }
        }
    }

    // ══════════════════════════════════════════════════════════════
    // Menus
    // ══════════════════════════════════════════════════════════════
    Menu {
        id: powerMenu
        title: qsTr("Power")
        background: Rectangle {
            radius: Radii.dialog
            color: MissionTheme.surface
            border.color: MissionTheme.outline
            border.width: 1
        }
        MissionMenuItem {
            id: shutdownItem
            objectName: "recoveryShutdown"
            text: qsTr("Shutdown")
            onTriggered: root.shutdownRequested()
        }
        MissionMenuItem {
            id: restartItem
            objectName: "recoveryRestart"
            text: qsTr("Restart")
            onTriggered: root.restartRequested()
        }
        MissionMenuItem {
            id: suspendItem
            objectName: "recoverySuspend"
            text: qsTr("Suspend")
            onTriggered: root.suspendRequested()
        }
    }

    // ── Clock timer (host-disabled via clockRunning) ───────────────
    Timer {
        id: clockTimer
        interval: 30000
        repeat: true
        running: root.clockRunning
        triggeredOnStart: true
        onTriggered: root.updateClock()
    }

    Component.onCompleted: {
        // Seed the clock once so it is never empty at first paint
        root.updateClock()
    }
}
