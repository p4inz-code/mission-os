// Mission OS — Lock Screen (MOS-LCK-001)
//
// First screen of the Mission OS lock/login family.
// Implements the source-defined Lock Screen structure
// (docs/wireframes/02_LOCK_SCREEN.md + docs/design/03_SCREEN_REGISTRY.md
// MOS-LCK-001 "Lock Screen"):
//
//   Hosting: place inside MissionWindow (or MissionPage) content and
//   anchor to fill, e.g.  MissionWindow { LockScreen { anchors.fill: parent } }
//   The component itself sizes to its implicit 1024x768 like MissionPage.
//
//   Layout (per wireframe): Wallpaper → Clock → Authentication Card →
//   Power Controls → Accessibility
//
// Components (per wireframe):
//   - User Avatar (preset token-colored avatar + initial; no image
//     asset is shipped — same inline approach as the installer
//     UserAccount avatar selector)
//   - Password Field (stock QtQuick.Controls.TextField styled inline —
//     Password Field is listed in docs/design/05_COMPONENT_LIBRARY.md
//     but not yet shipped; same inline pattern as every installer field)
//   - Accessibility entry button (Accessibility Menu content is
//     host-side, like the installer Welcome's Accessibility button)
//   - Network Status + Battery Status indicators
//   - Power Menu (Shutdown / Restart / Suspend)
//
// States (per wireframe): locked · authenticating · incorrect ·
// recovery required
//
// Interpretation notes (documented — no authoritative source specifies
// further detail):
//   - No wallpaper asset is shipped yet, so the backdrop is a calm
//     token-only vertical gradient plus a subtle scrim; the host may
//     layer a real wallpaper behind the component (background is
//     otherwise transparent only behind the gradient stops).
//   - The clock ticks live from the system clock. Hosts that need to
//     pin the displayed text set clockTimeText/clockDateText and
//     clockRunning = false (the timer only overwrites when running).
//   - Authentication is host-driven: the screen collects the password
//     and emits unlockRequested(password); real credential verification
//     (PAM/accounts) is the host's job. PIN entry is MOS-LCK-003 and
//     Recovery Login is MOS-LCK-004 — this screen only routes toward
//     them via signals (recoveryRequested), it does not implement them.
//   - Escape is deliberately unmapped (same contract as the terminal
//     Completion screen): the lock screen must not dismiss itself — the
//     host owns any escape behavior.
//   - While "incorrect", Unlock stays disabled and the banner's Retry
//     is the recovery path (same blocked-while-error contract as every
//     installer screen's Continue).
//
// Design-system compliance:
//   - Tokens only (Colors, Typography, Spacing, Radii, Motion, MissionTheme)
//   - Light + dark themes via MissionTheme (driven by host)
//   - Keyboard navigation with visible focus states; password field
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
    /// Authentication state: "locked" | "authenticating" | "incorrect" | "recovery"
    /// (wireframe states: Locked · Authenticating · Incorrect Password ·
    ///  Recovery Required)
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

    /// Network status label ("Connected" / "Offline") — host-driven;
    /// empty (default) renders neutral until the host supplies state
    property string networkStatusText: ""
    /// Whether the network is up (drives the status dot color; the dot
    /// is never the only indicator — the label always carries the text).
    /// Default false = neutral (no fabricated "connected" claim)
    property bool networkConnected: false

    /// Battery status label (e.g. "10%") — host-driven; empty (default)
    /// renders neutral until the host supplies state (FABRICATION-9)
    property string batteryStatusText: ""
    /// Battery level 0-100 (drives the fill width + semantic color);
    /// -1 = unknown (fill hidden) until the host supplies state
    property int batteryLevel: -1

    // ── Signals (host wiring) ──────────────────────────────────────
    /// User requested to unlock with the entered password
    signal unlockRequested(string password)
    /// User requested to retry after an incorrect password
    signal retryRequested()
    /// User requested recovery options (routes to MOS-LCK-004)
    signal recoveryRequested()
    /// User requested accessibility configuration
    signal accessibilityRequested()
    /// User requested system shutdown
    signal shutdownRequested()
    /// User requested system restart
    signal restartRequested()
    /// User requested system suspend
    signal suspendRequested()

    // Escape is deliberately unmapped (see interpretation notes): the
    // lock screen must not dismiss itself. No Keys.onEscapePressed here.

    // ── Responsive helpers ─────────────────────────────────────────
    // No help panel on the lock screen, so there is no wide-layout
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

    // ── Test hooks (used by tests/tst_lock_screen.qml) ─────────────
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
    property alias passwordField: passwordField
    property alias unlockButton: unlockButton
    property alias powerButton: powerButton
    property alias powerMenu: powerMenu
    property alias shutdownItem: shutdownItem
    property alias restartItem: restartItem
    property alias suspendItem: suspendItem
    property alias accessibilityButton: accessibilityButton
    property alias retryButton: retryButton
    property alias recoveryButton: recoveryButton
    property alias errorBanner: errorBanner
    property alias recoveryBanner: recoveryBanner
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
                    objectName: "lockClockTime"
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
                    objectName: "lockClockDate"
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
                            objectName: "lockNetworkStatus"
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
                                visible: root.batteryLevel >= 0
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
                            objectName: "lockBatteryStatus"
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
                        objectName: "lockAvatar"
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
                        objectName: "lockUserName"
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
                            text: qsTr("Verifying credentials…")
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

                    // ── Incorrect password (error + Retry) ──
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
                                    text: qsTr("Incorrect password")
                                    font.weight: Typography.weightSemibold
                                    color: Colors.contentOnErrorContainer
                                }
                                Label {
                                    text: qsTr("The password you entered is incorrect. Try again.")
                                    font.pixelSize: Typography.bodySmall.size
                                    color: Colors.contentOnErrorContainer
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                            MissionButton {
                                id: retryButton
                                objectName: "lockRetry"
                                variant: MissionButton.Variant.Secondary
                                text: qsTr("Retry")
                                onClicked: root.retryRequested()
                            }
                        }
                    }

                    // ── Recovery required (info + route to MOS-LCK-004) ──
                    Rectangle {
                        id: recoveryBanner
                        visible: root.authState === "recovery"
                        width: parent.width
                        height: recoveryLayout.implicitHeight + Spacing.paddingMedium * 2
                        radius: Radii.card
                        color: MissionTheme.surfaceVariant

                        RowLayout {
                            id: recoveryLayout
                            anchors.fill: parent
                            anchors.margins: Spacing.paddingMedium
                            spacing: Spacing.gapMedium

                            Rectangle {
                                Layout.preferredWidth: 12
                                Layout.preferredHeight: 12
                                radius: 6
                                color: MissionTheme.warning
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Spacing.gapTiny
                                Label {
                                    text: qsTr("Recovery required")
                                    font.weight: Typography.weightSemibold
                                    color: MissionTheme.textPrimary
                                }
                                Label {
                                    text: qsTr("Sign-in with your password is not available right now. You can use the recovery options to regain access.")
                                    font.pixelSize: Typography.bodySmall.size
                                    color: MissionTheme.textSecondary
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                            MissionButton {
                                id: recoveryButton
                                objectName: "lockRecovery"
                                variant: MissionButton.Variant.Secondary
                                text: qsTr("Recovery options")
                                onClicked: root.recoveryRequested()
                            }
                        }
                    }

                    // ── Password field ──
                    Column {
                        width: parent.width
                        spacing: Spacing.gapTiny

                        TextField {
                            id: passwordField
                            objectName: "lockPassword"
                            width: parent.width
                            implicitHeight: Spacing.minimumTouchTarget
                            echoMode: TextInput.Password
                            placeholderText: qsTr("Password")
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
                            onAccepted: root.unlockRequested(root.passwordField.text)
                            background: Rectangle {
                                radius: Radii.input
                                color: MissionTheme.surface
                                border.width: passwordField.activeFocus ? 2 : 1
                                border.color: passwordField.activeFocus ? MissionTheme.focusRing
                                                                        : MissionTheme.outline
                            }
                            Accessible.role: Accessible.EditableText
                            Accessible.name: qsTr("Password")
                            Accessible.description: qsTr("Enter your password to unlock this computer")
                        }
                    }

                    // ── Unlock (primary action) ──
                    MissionButton {
                        id: unlockButton
                        objectName: "lockUnlock"
                        anchors.horizontalCenter: parent.horizontalCenter
                        implicitWidth: 160
                        variant: MissionButton.Variant.Primary
                        text: qsTr("Unlock")
                        loading: root.authState === "authenticating"
                        enabled: root.authState === "locked"
                        onClicked: root.unlockRequested(root.passwordField.text)
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
                objectName: "lockAccessibility"
                variant: MissionButton.Variant.Secondary
                text: qsTr("Accessibility")
                onClicked: root.accessibilityRequested()
            }

            Item { Layout.fillWidth: true }

            // Power menu (Shutdown / Restart / Suspend)
            MissionButton {
                id: powerButton
                objectName: "lockPower"
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
            objectName: "lockShutdown"
            text: qsTr("Shutdown")
            onTriggered: root.shutdownRequested()
        }
        MissionMenuItem {
            id: restartItem
            objectName: "lockRestart"
            text: qsTr("Restart")
            onTriggered: root.restartRequested()
        }
        MissionMenuItem {
            id: suspendItem
            objectName: "lockSuspend"
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
