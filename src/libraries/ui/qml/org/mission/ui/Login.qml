// Mission OS — Login (MOS-LCK-002)
//
// Second screen of the Mission OS lock/login family.
// Implements the source-defined Login structure
// (docs/wireframes/02_LOCK_SCREEN.md + docs/design/03_SCREEN_REGISTRY.md
// MOS-LCK-002 "Login" + docs/engineering/RUNTIME_ARCHITECTURE.md §4.1):
//
//   Hosting: place inside MissionWindow (or MissionPage) content and
//   anchor to fill, e.g.  MissionWindow { Login { anchors.fill: parent } }
//   The component itself sizes to its implicit 1024x768 like MissionPage.
//
//   Layout (per wireframe): Wallpaper → Clock → Authentication Card →
//   Power Controls → Accessibility
//
// Components (per wireframe):
//   - User Avatar (per-account token-colored avatar + initial; no image
//     asset is shipped — same inline approach as MOS-LCK-001 and the
//     installer UserAccount avatar selector)
//   - Password Field (stock QtQuick.Controls.TextField styled inline —
//     Password Field is listed in docs/design/05_COMPONENT_LIBRARY.md
//     but not yet shipped; same inline pattern as every installer field
//     and MOS-LCK-001)
//   - Accessibility entry button (Accessibility Menu content is
//     host-side, like the installer Welcome's Accessibility button)
//   - Network Status + Battery Status indicators
//   - Power Menu (Shutdown / Restart / Suspend)
//
// States (per wireframe): locked · authenticating · incorrect ·
// recovery required. The login screen shares the family state
// vocabulary with MOS-LCK-001 so a host can drive both screens with the
// same state machine; here "locked" means "awaiting credentials" — no
// attempt has been submitted yet (documented interpretation).
//
// What distinguishes Login (MOS-LCK-002) from Lock Screen (MOS-LCK-001):
//   RUNTIME_ARCHITECTURE.md §4.1 (Login Flow): "User selects user →
//   enters credentials". Before a session exists the greeter must let
//   the user choose which account to sign in to. MOS-LCK-001 assumes a
//   single signed-in user (the locked session) and has no account
//   selection; this screen adds a per-account chooser and emits
//   loginRequested(userName, password) for the selected account.
//
// Interpretation notes (documented — no authoritative source specifies
// further detail):
//   - No wallpaper asset is shipped yet, so the backdrop is a calm
//     token-only vertical gradient plus a subtle scrim; the host may
//     layer a real wallpaper behind the component (same as MOS-LCK-001).
//   - The clock ticks live from the system clock. Hosts that need to
//     pin the displayed text set clockTimeText/clockDateText and
//     clockRunning = false (the timer only overwrites when running).
//   - `users` is host-driven: each entry is { name, displayName? }.
//     The account chooser row is shown when more than one account
//     exists; single-account systems get the compact card (avatar +
//     name only, like MOS-LCK-001). The big avatar always reflects the
//     selected account.
//   - Switching accounts clears the password field: credentials typed
//     for one account must never be submitted to another account
//     (greeter security behavior; documented as an interpretation).
//   - Authentication is host-driven: the screen collects the selected
//     account name + password and emits loginRequested(userName,
//     password); real credential verification (PAM/accounts) is the
//     host's job. PIN entry is MOS-LCK-003 and Recovery Login is
//     MOS-LCK-004 — this screen only routes toward them via signals
//     (recoveryRequested), it does not implement them.
//   - Escape is deliberately unmapped (same contract as MOS-LCK-001 and
//     the installer Completion screen): the login screen must not
//     dismiss itself — the host owns any escape behavior.
//   - While "incorrect", Login stays disabled and the banner's Retry
//     is the recovery path (same blocked-while-error contract as every
//     installer screen's Continue).
//
// Design-system compliance:
//   - Tokens only (Colors, Typography, Spacing, Radii, Motion, MissionTheme)
//   - Light + dark themes via MissionTheme (driven by host)
//   - Keyboard navigation with visible focus states; password field
//     focused on load (keyboard-first, per wireframe accessibility);
//     the account chooser is Tab + arrow-key navigable (Left/Right move
//     between accounts, Enter/Space selects)
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
    ///  Recovery Required; "locked" = awaiting credentials on Login)
    property string authState: "locked"

    /// Reduced motion (accessibility)
    property bool reducedMotion: false

    /// Available user accounts. Each entry: { name, displayName? }.
    /// Host-driven (the account database lives outside this component).
    /// The account name is what loginRequested carries.
    property var users: []

    /// Index of the selected account within `users` (host may preset
    /// it; derived helpers clamp out-of-range values)
    property int selectedUserIndex: 0

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
    /// User requested to sign in with the selected account + password
    signal loginRequested(string userName, string password)
    /// User changed the selected account (index into `users`)
    signal userSelected(int index)
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
    // login screen must not dismiss itself. No Keys.onEscapePressed here.

    // ── Responsive helpers ─────────────────────────────────────────
    // No help panel on the login screen, so there is no wide-layout
    // variant (unlike the installer screens); compactLayout trims the
    // date line so the clock never crowds the auth card on narrow
    // widths (docs/design/14_RESPONSIVE_RULES.md reflow).
    readonly property bool compactLayout: root.width < 640

    // ── Derived helpers ────────────────────────────────────────────
    /// Whether the account chooser row is shown. Multi-account systems
    /// get the selectable row; a single account renders the compact
    /// card (avatar + name only) like MOS-LCK-001.
    readonly property bool showAccountChooser: root.users.length > 1

    /// The selected account object (null when users is empty)
    readonly property var selectedUser: root.selectedUserIndex >= 0 &&
                                        root.selectedUserIndex < root.users.length
                                        ? root.users[root.selectedUserIndex] : null

    /// Selected account name (the identifier carried by loginRequested)
    readonly property string selectedUserName: root.selectedUser !== null
                                               ? String(root.selectedUser.name) : ""

    /// Backdrop base color (theme-aware; test hook). Equivalent to the
    /// wallpaper gradient's top stop, which is bound to
    /// MissionTheme.background.
    readonly property color backdropColor: MissionTheme.background

    /// Display name for a user entry (falls back to the account name)
    function displayNameFor(userEntry) {
        if (userEntry === null || userEntry === undefined)
            return ""
        var dn = userEntry.displayName !== undefined ? String(userEntry.displayName) : ""
        return dn.length > 0 ? dn : String(userEntry.name)
    }

    /// Avatar initial for a user entry (first letter of the display
    /// name, or a neutral dot when none is available)
    function avatarInitialFor(userEntry) {
        var dn = root.displayNameFor(userEntry)
        return dn.length > 0 ? dn.charAt(0).toUpperCase() : "\u2022"
    }

    /// Display name of the selected account (falls back to the name)
    readonly property string selectedDisplayName: root.displayNameFor(root.selectedUser)

    /// Avatar initial for the selected account
    readonly property string selectedAvatarInitial: root.avatarInitialFor(root.selectedUser)

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

    // ── User-selection helpers ─────────────────────────────────────
    /// Select an account by index into `users` (clamped). Emits
    /// userSelected(index). The password field is cleared on switch:
    /// credentials typed for one account must never be submitted to
    /// another (see interpretation notes).
    function selectUser(index) {
        if (root.users.length === 0)
            return
        var clamped = Math.max(0, Math.min(index, root.users.length - 1))
        if (clamped === root.selectedUserIndex)
            return
        root.selectedUserIndex = clamped
        // Credentials typed for one account must never be submitted to
        // another (see interpretation notes) — cleared on every switch.
        root.passwordField.clear()
        // Keyboard-first: after choosing an account the user types the
        // password next. Only moved when the field is actually enabled
        // (the field is disabled while authenticating / after an error).
        if (root.authState === "locked")
            root.passwordField.forceActiveFocus()
        root.userSelected(root.selectedUserIndex)
    }

    // Hosts may swap `users` at runtime (e.g. an account refresh); keep
    // the selection valid so the chooser never points past the list.
    // Host-driven changes do not emit userSelected (same contract as a
    // host writing selectedUserIndex directly).
    onUsersChanged: {
        if (root.users.length > 0 && root.selectedUserIndex >= root.users.length)
            root.selectedUserIndex = root.users.length - 1
    }

    // ── Test hooks (used by tests/tst_login.qml) ───────────────────
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
    property alias accountNameLabel: accountNameLabel
    property alias accountChooserRow: accountChooserRow
    property alias accountChooser: accountChooser
    property alias passwordField: passwordField
    property alias loginButton: loginButton
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
                    objectName: "loginClockTime"
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
                    objectName: "loginClockDate"
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
                            objectName: "loginNetworkStatus"
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
                            objectName: "loginBatteryStatus"
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

                    // ── Selected user avatar + name ──
                    Rectangle {
                        id: avatarPreview
                        objectName: "loginAvatar"
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 64
                        height: 64
                        radius: 32
                        color: MissionTheme.primary

                        Label {
                            anchors.centerIn: parent
                            text: root.selectedAvatarInitial
                            font.pixelSize: Typography.titleLarge.size
                            font.weight: Typography.weightBold
                            color: MissionTheme.contentOnPrimary
                        }

                        Accessible.role: Accessible.Graphic
                        Accessible.name: root.selectedDisplayName.length > 0
                                         ? qsTr("User avatar for %1").arg(root.selectedDisplayName)
                                         : qsTr("User avatar")
                    }

                    Label {
                        id: userNameLabel
                        objectName: "loginUserName"
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.selectedDisplayName.length > 0
                              ? root.selectedDisplayName : qsTr("Sign in")
                        font.pixelSize: Typography.subtitle.size
                        font.weight: Typography.subtitle.weight
                        color: MissionTheme.textPrimary
                        Accessible.role: Accessible.StaticText
                        Accessible.name: text
                    }

                    Label {
                        id: accountNameLabel
                        objectName: "loginAccountName"
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: root.selectedUserName.length > 0
                        text: root.selectedUserName
                        font.pixelSize: Typography.caption.size
                        color: MissionTheme.textTertiary
                        Accessible.role: Accessible.StaticText
                        Accessible.name: text
                    }

                    // ── Account chooser (multi-account systems) ──
                    Flow {
                        id: accountChooserRow
                        visible: root.showAccountChooser
                        width: parent.width
                        spacing: Spacing.gapSmall
                        Accessible.role: Accessible.Grouping
                        Accessible.name: qsTr("Accounts")

                        Repeater {
                            id: accountChooser
                            model: root.users

                            delegate: Rectangle {
                                id: userChip
                                required property var modelData
                                required property int index

                                objectName: "loginUserChip" + index
                                height: Spacing.minimumTouchTarget
                                width: userChipRow.implicitWidth + Spacing.paddingMedium * 2
                                radius: Radii.chip
                                color: index === root.selectedUserIndex
                                     ? (MissionTheme.darkMode ? MissionTheme.primary
                                                             : MissionTheme.primaryContainer)
                                     : (userChipMouse.containsMouse ? MissionTheme.surfaceVariant
                                                                   : MissionTheme.surface)
                                border.width: index === root.selectedUserIndex ? 0 : 1
                                border.color: MissionTheme.outline
                                activeFocusOnTab: true

                                Behavior on color {
                                    enabled: !root.reducedMotion
                                    // Ubuntu Qt 6.10 toolchain: Behavior
                                    // `duration` convenience property is
                                    // rejected; use the equivalent
                                    // `animation:` group property.
                                    animation: ColorAnimation { duration: Motion.colorChange }
                                }

                                // Visible focus ring (keyboard navigation)
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: -2
                                    radius: Radii.chip + 2
                                    color: "transparent"
                                    border.color: MissionTheme.focusRing
                                    border.width: 2
                                    visible: userChip.activeFocus
                                }

                                RowLayout {
                                    id: userChipRow
                                    anchors.centerIn: parent
                                    spacing: Spacing.gapSmall

                                    // Mini avatar (same inline treatment as
                                    // the selected-user avatar; outline keeps
                                    // the circle distinct on the selected
                                    // chip in dark mode)
                                    Rectangle {
                                        Layout.preferredWidth: 28
                                        Layout.preferredHeight: 28
                                        radius: 14
                                        color: MissionTheme.primary
                                        border.width: 1
                                        border.color: MissionTheme.outlineVariant

                                        Label {
                                            anchors.centerIn: parent
                                            text: root.avatarInitialFor(modelData)
                                            font.pixelSize: Typography.bodySmall.size
                                            font.weight: Typography.weightSemibold
                                            color: MissionTheme.contentOnPrimary
                                        }
                                    }

                                    Label {
                                        text: root.displayNameFor(modelData)
                                        font.pixelSize: Typography.bodySmall.size
                                        font.weight: index === root.selectedUserIndex
                                                     ? Typography.weightSemibold : Typography.weightRegular
                                        color: index === root.selectedUserIndex
                                             ? (MissionTheme.darkMode ? MissionTheme.contentOnPrimary
                                                                     : MissionTheme.contentOnPrimaryContainer)
                                             : MissionTheme.textPrimary
                                    }
                                }

                                MouseArea {
                                    id: userChipMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        userChip.forceActiveFocus()
                                        root.selectUser(index)
                                    }
                                }

                                // Keyboard-first: Left/Right move between
                                // accounts, Enter/Space selects. Up/Down are
                                // deliberately unmapped because the chips
                                // wrap (Flow) — rows are ambiguous.
                                Keys.onLeftPressed: {
                                    if (index > 0)
                                        accountChooser.itemAt(index - 1).forceActiveFocus()
                                }
                                Keys.onRightPressed: {
                                    if (index < root.users.length - 1)
                                        accountChooser.itemAt(index + 1).forceActiveFocus()
                                }
                                Keys.onReturnPressed: root.selectUser(index)
                                Keys.onSpacePressed: root.selectUser(index)

                                Accessible.role: Accessible.RadioButton
                                Accessible.name: root.displayNameFor(modelData)
                                Accessible.checked: index === root.selectedUserIndex
                            }
                        }
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
                                objectName: "loginRetry"
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
                                objectName: "loginRecovery"
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
                            objectName: "loginPassword"
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
                            onAccepted: root.loginRequested(root.selectedUserName,
                                                            root.passwordField.text)
                            background: Rectangle {
                                radius: Radii.input
                                color: MissionTheme.surface
                                border.width: passwordField.activeFocus ? 2 : 1
                                border.color: passwordField.activeFocus ? MissionTheme.focusRing
                                                                        : MissionTheme.outline
                            }
                            Accessible.role: Accessible.EditableText
                            Accessible.name: qsTr("Password")
                            Accessible.description: qsTr("Enter your password to sign in")
                        }
                    }

                    // ── Login (primary action) ──
                    MissionButton {
                        id: loginButton
                        objectName: "loginLogin"
                        anchors.horizontalCenter: parent.horizontalCenter
                        implicitWidth: 160
                        variant: MissionButton.Variant.Primary
                        text: qsTr("Login")
                        loading: root.authState === "authenticating"
                        enabled: root.authState === "locked"
                        onClicked: root.loginRequested(root.selectedUserName,
                                                       root.passwordField.text)
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
                objectName: "loginAccessibility"
                variant: MissionButton.Variant.Secondary
                text: qsTr("Accessibility")
                onClicked: root.accessibilityRequested()
            }

            Item { Layout.fillWidth: true }

            // Power menu (Shutdown / Restart / Suspend)
            MissionButton {
                id: powerButton
                objectName: "loginPower"
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
            objectName: "loginShutdown"
            text: qsTr("Shutdown")
            onTriggered: root.shutdownRequested()
        }
        MissionMenuItem {
            id: restartItem
            objectName: "loginRestart"
            text: qsTr("Restart")
            onTriggered: root.restartRequested()
        }
        MissionMenuItem {
            id: suspendItem
            objectName: "loginSuspend"
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
