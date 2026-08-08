// Mission OS — PIN Entry (MOS-LCK-003)
//
// Third screen of the Mission OS lock/login family.
// Implements the source-defined PIN structure
// (docs/wireframes/02_LOCK_SCREEN.md + docs/design/03_SCREEN_REGISTRY.md
// MOS-LCK-003 "PIN Entry"):
//
//   Hosting: place inside MissionWindow (or MissionPage) content and
//   anchor to fill, e.g.  MissionWindow { PinEntry { anchors.fill: parent } }
//   The component itself sizes to its implicit 1024x768 like MissionPage.
//
//   Layout (per wireframe): Wallpaper → Clock → Authentication Card →
//   Power Controls → Accessibility
//
// Components (per wireframe):
//   - User Avatar (preset token-colored avatar + initial; no image
//     asset is shipped — same inline approach as MOS-LCK-001/002 and
//     the installer UserAccount avatar selector)
//   - PIN Input (the wireframe lists "PIN Input" as a lock-family
//     component; the component library has no shipped PIN input, so it
//     is built inline from tokens like every installer field — a masked
//     dot display plus a 3×4 numeric keypad: 1–9, Backspace, 0, Unlock)
//   - Accessibility entry button (Accessibility Menu content is
//     host-side, like MOS-LCK-001/002)
//   - Network Status + Battery Status indicators
//   - Power Menu (Shutdown / Restart / Suspend)
//
// States (per wireframe): locked · authenticating · incorrect ·
// recovery required. The screen shares the family state vocabulary
// with MOS-LCK-001/002 so a host can drive the whole family with the
// same state machine; here "locked" means "awaiting PIN" — no attempt
// has been submitted yet.
//
// What distinguishes PIN Entry (MOS-LCK-003) from Lock Screen
// (MOS-LCK-001) / Login (MOS-LCK-002):
//   Those screens collect a password. This screen collects a numeric
//   PIN through a keypad instead of a text field and emits
//   pinSubmitted(pin) with the entered digits; the host verifies
//   against its PIN backend (docs/engineering/SECURITY_ARCHITECTURE.md
//   § "PIN (optional convenience, secondary authentication)").
//
// Interpretation notes (documented — no authoritative source specifies
// further detail):
//   - No wallpaper asset is shipped yet, so the backdrop is a calm
//     token-only vertical gradient plus a subtle scrim; the host may
//     layer a real wallpaper behind the component (same as MOS-LCK-001).
//   - The clock ticks live from the system clock. Hosts that need to
//     pin the displayed text set clockTimeText/clockDateText and
//     clockRunning = false (the timer only overwrites when running).
//   - PINs are numeric only (the keypad exposes 0–9); the host
//     configures the maximum entry length via pinMaxLength (default 8),
//     which bounds both the keypad and the masked dot display.
//   - Authentication is host-driven: the screen collects the digits and
//     emits pinSubmitted(pin); real credential verification is the
//     host's job. The password route is MOS-LCK-001/002 territory — this
//     screen only routes toward it via passwordRequested (the family
//     wireframe lists Password Field alongside PIN Input; a host greeter
//     typically offers the password fallback), it does not implement the
//     password form. Recovery Login is MOS-LCK-004 — this screen only
//     routes toward it via recoveryRequested (same contract as
//     MOS-LCK-001/002), it does not implement it.
//   - The entered digits are NOT cleared automatically on "incorrect":
//     the Retry banner is the recovery path and the host decides whether
//     to clear (same blocked-while-error contract as every installer
//     screen's Continue and as MOS-LCK-001/002).
//   - Escape is deliberately unmapped (same contract as MOS-LCK-001/002
//     and the installer Completion screen): the PIN screen must not
//     dismiss itself — the host owns any escape behavior.
//   - Keyboard-first: the root FocusScope holds initial focus while
//     "locked"; the number keys 0–9, Backspace and Return are captured
//     screen-wide (the key handler lives on the root and key events
//     propagate to it from any focused keypad key), so typing works no
//     matter where focus is. Return activates a focused keypad key (e.g.
//     Unlock submits) or submits when no key consumes it.
//
// Design-system compliance:
//   - Tokens only (Colors, Typography, Spacing, Radii, Motion, MissionTheme)
//   - Light + dark themes via MissionTheme (driven by host)
//   - Keyboard navigation with visible focus states; keypad keys are
//     full 44px touch targets (Spacing.minimumTouchTarget)
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

    /// Entered PIN digits (numeric; readable by hosts and tests).
    /// Appended by the keypad and the number keys while "locked".
    property string pinText: ""

    /// Maximum PIN length (host-configurable; bounds the keypad and the
    /// masked dot display). PIN lengths are deployment-specific
    /// (4–8 digits is the common range), so the host decides.
    property int pinMaxLength: 8

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
    /// User requested to unlock with the entered PIN digits
    signal pinSubmitted(string pin)
    /// User requested the password route instead (MOS-LCK-001/002)
    signal passwordRequested()
    /// User requested to retry after an incorrect PIN
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
    // PIN screen must not dismiss itself. No Keys.onEscapePressed here.

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

    /// Number of digits currently entered
    readonly property int pinLength: root.pinText.length

    /// Whether more digits may be appended (bounds pinText)
    readonly property bool pinFull: root.pinLength >= root.pinMaxLength

    // ── Keypad model (3×4: 1–9, Backspace, 0, Unlock) ─────────────
    // value "backspace"/"submit" are commands; everything else is a
    // digit to append. The ⌫ glyph carries the Accessible name
    // "Backspace" so screen readers announce it correctly.
    readonly property var keypadModel: [
        { label: "1", value: "1" }, { label: "2", value: "2" }, { label: "3", value: "3" },
        { label: "4", value: "4" }, { label: "5", value: "5" }, { label: "6", value: "6" },
        { label: "7", value: "7" }, { label: "8", value: "8" }, { label: "9", value: "9" },
        { label: "\u232B", value: "backspace" },
        { label: "0", value: "0" },
        { label: "Unlock", value: "submit" }
    ]

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

    // ── PIN helpers ────────────────────────────────────────────────
    /// Append a digit (0-9) while "locked" and the PIN is not full.
    /// No-op in every other auth state so key events can never type
    /// into a blocked screen (keyboard-safe, same contract as the
    /// disabled password fields on MOS-LCK-001/002).
    function appendDigit(digit) {
        if (root.authState !== "locked")
            return
        if (root.pinFull)
            return
        var d = String(digit)
        if (d.length !== 1 || d < "0" || d > "9")
            return
        root.pinText = root.pinText + d
    }

    /// Remove the last entered digit (while "locked")
    function backspaceDigit() {
        if (root.authState !== "locked")
            return
        root.pinText = root.pinText.slice(0, -1)
    }

    /// Clear all entered digits (while "locked"; host wiring / tests)
    function clearPin() {
        if (root.authState !== "locked")
            return
        root.pinText = ""
    }

    /// Submit the entered PIN. Only emits while "locked" (keyboard-safe:
    /// Return on a blocked screen must not fire pinSubmitted).
    function submitPin() {
        if (root.authState !== "locked")
            return
        root.pinSubmitted(root.pinText)
    }

    // ── Keyboard capture (keyboard-first, per wireframe) ───────────
    // The number keys, Backspace and Return are handled on the root
    // FocusScope. Key events propagate here from any focused child that
    // does not consume them, so typing works no matter where focus is.
    // Return activates a focused keypad key first (standard button
    // behavior); when nothing consumes it, it submits. Escape is
    // deliberately NOT handled (see interpretation notes).
    Keys.onPressed: (event) => {
        if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9) {
            root.appendDigit(String(event.key - Qt.Key_0))
            event.accepted = true
        } else if (event.key === Qt.Key_Backspace) {
            root.backspaceDigit()
            event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.submitPin()
            event.accepted = true
        }
    }

    // ── Test hooks (used by tests/tst_pin_entry.qml) ───────────────
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
    property alias pinHintLabel: pinHintLabel
    property alias pinDisplay: pinDisplayRow
    property alias pinSlots: pinSlots
    property alias keypadGrid: keypadGrid
    property alias keypad: keypadRepeater
    property alias passwordButton: passwordButton
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

    // Initial focus while awaiting a PIN (keyboard-first, like the
    // password fields on MOS-LCK-001/002)
    focus: root.authState === "locked"

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
                    objectName: "pinClockTime"
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
                    objectName: "pinClockDate"
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
                            objectName: "pinNetworkStatus"
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
                            objectName: "pinBatteryStatus"
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
                        objectName: "pinAvatar"
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
                        objectName: "pinUserName"
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
                            text: qsTr("Verifying PIN…")
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

                    // ── Incorrect PIN (error + Retry) ──
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
                                    text: qsTr("Incorrect PIN")
                                    font.weight: Typography.weightSemibold
                                    color: Colors.contentOnErrorContainer
                                }
                                Label {
                                    text: qsTr("The PIN you entered is incorrect. Try again.")
                                    font.pixelSize: Typography.bodySmall.size
                                    color: Colors.contentOnErrorContainer
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                            MissionButton {
                                id: retryButton
                                objectName: "pinRetry"
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
                                    text: qsTr("Sign-in with your PIN is not available right now. You can use the recovery options to regain access.")
                                    font.pixelSize: Typography.bodySmall.size
                                    color: MissionTheme.textSecondary
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                            MissionButton {
                                id: recoveryButton
                                objectName: "pinRecovery"
                                variant: MissionButton.Variant.Secondary
                                text: qsTr("Recovery options")
                                onClicked: root.recoveryRequested()
                            }
                        }
                    }

                    // ── PIN hint ──
                    Label {
                        id: pinHintLabel
                        objectName: "pinHint"
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: qsTr("Enter your PIN")
                        font.pixelSize: Typography.bodyLarge.size
                        font.weight: Typography.weightMedium
                        color: MissionTheme.textPrimary
                        Accessible.role: Accessible.StaticText
                        Accessible.name: text
                    }

                    // ── Masked PIN display (dot slots) ──
                    // One slot per pinMaxLength position; filled slots
                    // show entered digits (color is never the only
                    // indicator — the Accessible name carries the count).
                    // Keyboard digits are captured by the root handler
                    // regardless of focus, so no focusable surface is
                    // needed here (it sits outside the Tab chain).
                    Item {
                        width: pinDisplayRow.width
                        height: pinDisplayRow.height

                        Row {
                            id: pinDisplayRow
                            objectName: "pinDisplay"
                            anchors.centerIn: parent
                            spacing: Spacing.gapSmall

                            Repeater {
                                id: pinSlots
                                model: root.pinMaxLength

                                Rectangle {
                                    required property int index
                                    width: 14
                                    height: 14
                                    radius: 7
                                    color: index < root.pinLength ? MissionTheme.primary
                                                                  : "transparent"
                                    border.width: index < root.pinLength ? 0 : 1
                                    border.color: MissionTheme.outline
                                }
                            }

                            Accessible.role: Accessible.StaticText
                            Accessible.name: qsTr("PIN entry: %1 of %2 digits entered")
                                             .arg(root.pinLength).arg(root.pinMaxLength)
                        }
                    }

                    // ── Keypad (3×4) ──
                    GridLayout {
                        id: keypadGrid
                        objectName: "pinKeypad"
                        width: parent.width
                        columns: 3
                        rowSpacing: Spacing.gapSmall
                        columnSpacing: Spacing.gapSmall

                        Repeater {
                            id: keypadRepeater
                            model: root.keypadModel

                            delegate: MissionButton {
                                required property var modelData
                                required property int index

                                objectName: "pinKey" + index
                                Layout.fillWidth: true
                                Layout.preferredHeight: Spacing.minimumTouchTarget
                                variant: modelData.value === "submit"
                                         ? MissionButton.Variant.Primary
                                         : MissionButton.Variant.Secondary
                                text: modelData.label
                                enabled: root.authState === "locked"
                                loading: modelData.value === "submit" &&
                                         root.authState === "authenticating"
                                Accessible.name: modelData.value === "backspace"
                                                 ? qsTr("Backspace")
                                                 : (modelData.value === "submit"
                                                    ? qsTr("Unlock with PIN")
                                                    : modelData.label)

                                onClicked: {
                                    if (modelData.value === "backspace") {
                                        root.backspaceDigit()
                                    } else if (modelData.value === "submit") {
                                        root.submitPin()
                                    } else {
                                        root.appendDigit(modelData.value)
                                    }
                                }
                            }
                        }
                    }

                    // ── Use password (route to MOS-LCK-001/002) ──
                    MissionButton {
                        id: passwordButton
                        objectName: "pinPassword"
                        anchors.horizontalCenter: parent.horizontalCenter
                        variant: MissionButton.Variant.Tertiary
                        text: qsTr("Use password")
                        enabled: root.authState === "locked"
                        onClicked: root.passwordRequested()
                        Accessible.description: qsTr("Sign in with your password instead")
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
                objectName: "pinAccessibility"
                variant: MissionButton.Variant.Secondary
                text: qsTr("Accessibility")
                onClicked: root.accessibilityRequested()
            }

            Item { Layout.fillWidth: true }

            // Power menu (Shutdown / Restart / Suspend)
            MissionButton {
                id: powerButton
                objectName: "pinPower"
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
            objectName: "pinShutdown"
            text: qsTr("Shutdown")
            onTriggered: root.shutdownRequested()
        }
        MissionMenuItem {
            id: restartItem
            objectName: "pinRestart"
            text: qsTr("Restart")
            onTriggered: root.restartRequested()
        }
        MissionMenuItem {
            id: suspendItem
            objectName: "pinSuspend"
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
