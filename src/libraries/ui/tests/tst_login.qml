// Mission OS — Login (MOS-LCK-002) QtTest suite
//
// Runtime validation of the Login screen. Follows the foundation
// smoke-test pattern (tests/tst_smoke.qml), the Lock Screen suite
// (tests/tst_lock_screen.qml) and docs/engineering/TESTING_STRATEGY.md
// (QML → Qt Test / qmltestrunner).
//
// Coverage:
//   - screen loads without QML errors (token singletons resolve)
//   - MissionTheme works; light/dark rendering bindings re-evaluate
//   - primary actions exist (Login / Power / Accessibility / Retry /
//     Recovery) and carry the right variants
//   - wireframe auth states: locked · authenticating · incorrect ·
//     recovery required — banners render, Login never fires while
//     blocked
//   - login emits loginRequested(userName, password) from Enter and from
//     the Login button with the selected account name
//   - user selection (runtime arch §4.1 "User selects user → enters
//     credentials"): default selection, selectUser(), chip click,
//     arrow-key navigation, Enter/Space selection, userSelected signal,
//     avatar initials, password cleared on account switch
//   - empty-user fallback renders without errors
//   - power menu (Shutdown / Restart / Suspend) routes to its signals
//   - network/battery status indicators react to host properties
//   - clock text is host-pinnable and seeded at load
//   - keyboard focus reaches the password field first, then the action
//     controls and the account chooser; Escape is deliberately unmapped
//     (no signal fires)
//   - MissionPage / MissionWindow integration introduces no runtime errors
//   - accessibility roles (clock, avatar, password field, status chips,
//     account chips)
//   - reduced motion does not break rendering
//
// Run via qmltestrunner (see CMakeLists.txt CTest registration):
//   qmltestrunner -import <build>/src/libraries/ui/qml \
//                 -input src/libraries/ui/tests/tst_login.qml
//
// Exit code: 0 = all checks passed; non-zero = failure (CI gate).

import QtQuick
import QtTest
import org.mission.ui 1.0

TestCase {
    id: root
    name: "Login"

    // ── Helpers ────────────────────────────────────────────────────
    // The qmltestrunner harness does not show its own test window, so
    // items hosted directly under the TestCase report visible=false on
    // this Qt build (verified empirically). To validate real
    // visibility and keyboard-focus behavior, every screen under test
    // is hosted inside an explicit visible Window; cleanup() destroys
    // the host windows afterwards.
    property var _hostWindows: []

    // Two-account fixture used by the user-selection tests
    property var _fixtureUsers: [
        { name: "alex", displayName: "Alex" },
        { name: "sam", displayName: "Sam" }
    ]

    // ── Typing helper ──────────────────────────────────────────────
    // This toolchain's qmltestrunner does not ship TestCase.keyClicks
    // (unverified runtime API here), so typing follows the established
    // per-character pattern used by tst_user_account.qml / tst_keyboard.qml
    // (keyClick per character, lowercase only — the validated suites
    // never exercise Shift-modified uppercase, and neither does this one).
    // Handles a-z and 0-9, which is all the test passwords need.
    function typeChars(text) {
        for (var i = 0; i < text.length; ++i) {
            var ch = text.charAt(i)
            if (ch >= "a" && ch <= "z") {
                keyClick(0x41 + (ch.charCodeAt(0) - 97), Qt.NoModifier)
            } else if (ch >= "0" && ch <= "9") {
                keyClick(Qt.Key_0 + (ch.charCodeAt(0) - 48), Qt.NoModifier)
            }
        }
    }

    function createScreen(extra) {
        var source = "import QtQuick\n" +
                     "import org.mission.ui 1.0\n" +
                     "Window {\n" +
                     "    width: 1024; height: 768; visible: true\n" +
                     "    property alias screen: screen\n" +
                     "    Login { id: screen; width: 1024; height: 768; " +
                     (extra || "") + " }\n" +
                     "}"
        var host = Qt.createQmlObject(source, root, "loginHost")
        _hostWindows.push(host)
        return host.screen
    }

    // ── Screen loads; tokens resolve; no QML errors ────────────────
    function test_screenLoads() {
        var screen = createScreen()
        verify(screen !== null)
        verify(screen.height > 0)
        // Token singletons must resolve through the screen's bindings
        verify(Qt.colorEqual(screen.backdropColor, Colors.background))
        // Clock is seeded at load (Component.onCompleted)
        verify(screen.clockTimeLabel.text.length > 0)
        verify(screen.clockDateLabel.text.length > 0)
        // Core components exist
        verify(screen.passwordField !== null)
        verify(screen.loginButton.text.length > 0)
        verify(screen.avatarPreview !== null)
        screen.destroy()
    }

    // ── MissionTheme light/dark rendering bindings ─────────────────
    function test_themeLightAndDark() {
        var screen = createScreen()
        MissionTheme.darkMode = false
        verify(Qt.colorEqual(screen.backdropColor, Colors.background))
        verify(Qt.colorEqual(screen.backdropColor, MissionTheme.background))
        verify(Qt.colorEqual(screen.clockTimeLabel.color, MissionTheme.textPrimary))
        verify(Qt.colorEqual(screen.userNameLabel.color, MissionTheme.textPrimary))

        MissionTheme.darkMode = true
        verify(Qt.colorEqual(screen.backdropColor, Colors.darkBackground))
        verify(Qt.colorEqual(screen.backdropColor, MissionTheme.background))
        verify(Qt.colorEqual(screen.clockTimeLabel.color, MissionTheme.textPrimary))
        verify(Qt.colorEqual(screen.userNameLabel.color, MissionTheme.textPrimary))

        MissionTheme.darkMode = false
        verify(Qt.colorEqual(screen.backdropColor, Colors.background))
        screen.destroy()
    }

    // ── Primary actions exist ──────────────────────────────────────
    function test_primaryActionsExist() {
        var screen = createScreen("users: [ { name: 'alex', displayName: 'Alex' }, " +
                                           "{ name: 'sam', displayName: 'Sam' } ]")
        verify(screen.loginButton !== null)
        verify(screen.powerButton !== null)
        verify(screen.accessibilityButton !== null)
        verify(screen.retryButton !== null)
        verify(screen.recoveryButton !== null)
        verify(screen.passwordField !== null)
        verify(screen.loginButton.visible)
        verify(screen.loginButton.enabled)
        // Login is the primary action; Power/Accessibility are secondary
        compare(screen.loginButton.variant, MissionButton.Variant.Primary)
        compare(screen.loginButton.text, "Login")
        compare(screen.powerButton.variant, MissionButton.Variant.Secondary)
        compare(screen.accessibilityButton.variant, MissionButton.Variant.Secondary)
        // Wireframe components: user avatar + status indicators present
        verify(screen.avatarPreview.visible)
        verify(screen.networkStatusLabel.text.length > 0)
        verify(screen.batteryStatusLabel.text.length > 0)
        // Multi-account systems show the chooser with one chip per user
        verify(screen.showAccountChooser)
        verify(screen.accountChooserRow.visible)
        verify(screen.accountChooser.count === 2)
        verify(screen.accountChooser.itemAt(0) !== null)
        verify(screen.accountChooser.itemAt(1) !== null)
        screen.destroy()
    }

    // ── Auth states (wireframe: Locked · Authenticating · Incorrect ·
    //    Recovery Required) ─────────────────────────────────────────
    function test_authStateTransitions() {
        var screen = createScreen("users: [ { name: 'alex', displayName: 'Alex' } ]")
        // locked (default): field + Login enabled, no banners
        verify(screen.passwordField.enabled)
        verify(screen.loginButton.enabled)
        verify(!screen.authenticatingIndicator.visible)
        verify(!screen.errorBanner.visible)
        verify(!screen.recoveryBanner.visible)

        // authenticating: progress shown, Login + field blocked
        screen.authState = "authenticating"
        verify(screen.authenticatingIndicator.visible)
        verify(screen.loginButton.loading)
        verify(!screen.loginButton.enabled)
        verify(!screen.passwordField.enabled)
        verify(!screen.errorBanner.visible)

        // incorrect: error banner + Retry, Login blocked
        screen.authState = "incorrect"
        verify(screen.errorBanner.visible)
        verify(screen.errorBanner.height > 0,
               "error banner must render with positive height (banner-height bug regression)")
        verify(screen.retryButton.visible)
        verify(!screen.loginButton.enabled)
        verify(!screen.passwordField.enabled)

        // recovery: recovery banner + Recovery button, Login blocked
        screen.authState = "recovery"
        verify(screen.recoveryBanner.visible)
        verify(screen.recoveryBanner.height > 0,
               "recovery banner must render with positive height (banner-height bug regression)")
        verify(screen.recoveryButton.visible)
        verify(!screen.loginButton.enabled)
        verify(!screen.passwordField.enabled)

        // back to locked clears everything
        screen.authState = "locked"
        verify(screen.passwordField.enabled)
        verify(screen.loginButton.enabled)
        verify(!screen.authenticatingIndicator.visible)
        verify(!screen.errorBanner.visible)
        verify(!screen.recoveryBanner.visible)

        screen.destroy()
    }

    // ── Login must not fire while blocked (keyboard-safe) ──────────
    function test_loginBlockedWhileAuthenticating() {
        var screen = createScreen("users: [ { name: 'alex', displayName: 'Alex' } ]")
        wait(100) // let the hosted window activate so key events reach it
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'loginRequested' }",
            screen, "loginSpyBlocked")
        spy.target = screen

        // Authenticating: Login disabled → no signal from keyboard
        screen.authState = "authenticating"
        verify(!screen.loginButton.enabled)
        screen.loginButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spy.count, 0)

        // Incorrect: Login disabled → no signal
        screen.authState = "incorrect"
        verify(!screen.loginButton.enabled)
        screen.loginButton.forceActiveFocus()
        keyClick(Qt.Key_Return)
        compare(spy.count, 0)

        // Locked: Login enabled → keyboard input signs in
        screen.authState = "locked"
        verify(screen.loginButton.enabled)
        screen.loginButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spy.count, 1)

        screen.destroy()
    }

    // ── Login signal carries the selected account + password ───────
    function test_loginSignalCarriesCredentials() {
        var screen = createScreen("users: [ { name: 'alex', displayName: 'Alex' }, " +
                                           "{ name: 'sam', displayName: 'Sam' } ]")
        wait(100) // window activation for key delivery
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'loginRequested' }",
            screen, "loginSpyPassword")
        spy.target = screen

        // Typing into the password field, then Enter → login with the
        // pre-selected account (alex)
        screen.passwordField.forceActiveFocus()
        typeChars("mission1")
        compare(screen.passwordField.text, "mission1")
        keyClick(Qt.Key_Return)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "alex")
        compare(spy.signalArguments[0][1], "mission1")

        // Switch to the second account, then submit via the Login
        // button — the signal must carry the new account name.
        screen.selectUser(1)
        screen.passwordField.forceActiveFocus()
        typeChars("secret2")
        compare(screen.passwordField.text, "secret2")
        screen.loginButton.clicked()
        compare(spy.count, 2)
        compare(spy.signalArguments[1][0], "sam")
        compare(spy.signalArguments[1][1], "secret2")

        screen.destroy()
    }

    // ── User selection (runtime arch §4.1) ─────────────────────────
    function test_userSelection() {
        var screen = createScreen("users: [ { name: 'alex', displayName: 'Alex' }, " +
                                           "{ name: 'sam', displayName: 'Sam' } ]")
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'userSelected' }",
            screen, "userSpy")
        spy.target = screen

        // Default: first account selected, chooser visible
        verify(screen.showAccountChooser)
        verify(screen.accountChooserRow.visible)
        compare(screen.selectedUserIndex, 0)
        compare(screen.selectedUserName, "alex")
        compare(screen.selectedDisplayName, "Alex")
        compare(screen.selectedAvatarInitial, "A")
        compare(screen.userNameLabel.text, "Alex")
        compare(screen.accountNameLabel.text, "alex")
        compare(spy.count, 0) // no signal on load

        // Programmatic selection emits userSelected with the new index
        screen.selectUser(1)
        compare(screen.selectedUserIndex, 1)
        compare(screen.selectedUserName, "sam")
        compare(screen.selectedDisplayName, "Sam")
        compare(screen.selectedAvatarInitial, "S")
        compare(screen.userNameLabel.text, "Sam")
        compare(screen.accountNameLabel.text, "sam")
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], 1)

        // Chip clicks select (mouse path). The chips are Rectangles
        // with a MouseArea (not Buttons), so the click is delivered via
        // a real mouse event at the chip center.
        var chip0 = screen.accountChooser.itemAt(0)
        verify(chip0 !== null)
        mouseClick(chip0, chip0.width / 2, chip0.height / 2)
        compare(screen.selectedUserIndex, 0)
        compare(spy.count, 2)
        compare(spy.signalArguments[1][0], 0)

        screen.destroy()
    }

    // ── Keyboard selection: arrows move, Enter/Space selects ───────
    function test_userSelectionKeyboard() {
        var screen = createScreen("users: [ { name: 'alex', displayName: 'Alex' }, " +
                                           "{ name: 'sam', displayName: 'Sam' } ]")
        wait(100) // window activation for key delivery
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'userSelected' }",
            screen, "userKbdSpy")
        spy.target = screen
        var chip0 = screen.accountChooser.itemAt(0)
        var chip1 = screen.accountChooser.itemAt(1)
        verify(chip0 !== null)
        verify(chip1 !== null)

        // Right arrow from the first chip focuses the second
        chip0.forceActiveFocus()
        keyClick(Qt.Key_Right)
        verify(chip1.activeFocus, "Right arrow must move focus to the next account")
        compare(screen.selectedUserIndex, 0) // focus moved, selection unchanged yet

        // Enter on the focused chip selects it (selectUser moves focus
        // to the password field afterwards, per greeter keyboard flow)
        keyClick(Qt.Key_Return)
        compare(screen.selectedUserIndex, 1)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], 1)

        // Left arrow back, Space selects the first account. The chip
        // must be refocused first: Return above handed focus to the
        // password field.
        chip1.forceActiveFocus()
        keyClick(Qt.Key_Left)
        verify(chip0.activeFocus, "Left arrow must move focus to the previous account")
        keyClick(Qt.Key_Space)
        compare(screen.selectedUserIndex, 0)
        compare(spy.count, 2)

        screen.destroy()
    }

    // ── Switching accounts clears the password field ───────────────
    function test_userSwitchClearsPassword() {
        var screen = createScreen("users: [ { name: 'alex', displayName: 'Alex' }, " +
                                           "{ name: 'sam', displayName: 'Sam' } ]")
        wait(100) // window activation for key delivery (first key is
                  // otherwise dropped before the window activates)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'loginRequested' }",
            screen, "clearSpy")
        spy.target = screen

        screen.passwordField.forceActiveFocus()
        typeChars("mission1")
        compare(screen.passwordField.text, "mission1")

        // Switching accounts must not submit anything, just clear
        screen.selectUser(1)
        compare(spy.count, 0)
        compare(screen.passwordField.text, "", "password must be cleared on account switch")

        // Selecting the same account again is a no-op (no clear loop)
        screen.passwordField.forceActiveFocus()
        typeChars("again")
        compare(screen.passwordField.text, "again")
        screen.selectUser(1)
        compare(screen.passwordField.text, "again",
               "re-selecting the current account must not clear the field")

        screen.destroy()
    }

    // ── Host refresh of `users` keeps the selection valid ──────────
    function test_usersChangedClamp() {
        var screen = createScreen("users: [ { name: 'a', displayName: 'A' }, " +
                                           "{ name: 'b', displayName: 'B' }, " +
                                           "{ name: 'c', displayName: 'C' } ]")
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'userSelected' }",
            screen, "clampSpy")
        spy.target = screen

        screen.selectUser(2)
        compare(screen.selectedUserIndex, 2)
        compare(screen.selectedUserName, "c")

        // Host replaces the account list with a single entry: the index
        // must re-clamp (host-driven, so no userSelected is emitted).
        screen.users = [ { name: 'd', displayName: 'D' } ]
        compare(screen.selectedUserIndex, 0)
        compare(screen.selectedUserName, "d")
        compare(spy.count, 1, "host-driven users change must not emit userSelected")

        // Empty list: derived helpers degrade to empty strings
        screen.users = []
        compare(screen.selectedUserName, "")
        compare(screen.selectedAvatarInitial, "\u2022")
        compare(spy.count, 1)

        screen.destroy()
    }

    // ── Empty users degrade gracefully ─────────────────────────────
    function test_emptyUsersFallback() {
        var screen = createScreen()
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'loginRequested' }",
            screen, "emptySpy")
        spy.target = screen

        verify(!screen.showAccountChooser)
        verify(!screen.accountChooserRow.visible)
        compare(screen.selectedUserName, "")
        compare(screen.selectedAvatarInitial, "\u2022")
        compare(screen.userNameLabel.text, "Sign in")
        verify(!screen.accountNameLabel.visible)

        // The screen still collects a password for the host to decide
        screen.passwordField.forceActiveFocus()
        typeChars("mission1")
        keyClick(Qt.Key_Return)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "")
        compare(spy.signalArguments[0][1], "mission1")

        screen.destroy()
    }

    // ── Power menu (Shutdown / Restart / Suspend) ──────────────────
    function test_powerMenuActions() {
        var screen = createScreen()
        var spies = []
        var names = ["shutdownRequested", "restartRequested", "suspendRequested"]
        for (var i = 0; i < names.length; ++i) {
            var spy = Qt.createQmlObject(
                "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: '" +
                names[i] + "' }", screen, "powerSpy" + i)
            spy.target = screen
            spies.push(spy)
        }

        // Menu items exist and are wired to the requested signals
        verify(screen.shutdownItem !== null)
        verify(screen.restartItem !== null)
        verify(screen.suspendItem !== null)
        verify(screen.shutdownItem.text.length > 0)
        verify(screen.restartItem.text.length > 0)
        verify(screen.suspendItem.text.length > 0)

        screen.shutdownItem.triggered()
        screen.restartItem.triggered()
        screen.suspendItem.triggered()
        compare(spies[0].count, 1)
        compare(spies[1].count, 1)
        compare(spies[2].count, 1)

        screen.destroy()
    }

    // ── Accessibility entry ────────────────────────────────────────
    function test_accessibilitySignal() {
        var screen = createScreen()
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'accessibilityRequested' }",
            screen, "a11ySpy")
        spy.target = screen
        screen.accessibilityButton.clicked()
        compare(spy.count, 1)
        screen.destroy()
    }

    // ── Retry + Recovery route to their signals ────────────────────
    function test_retryAndRecoverySignals() {
        var screen = createScreen()
        var retrySpy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'retryRequested' }",
            screen, "retrySpy")
        retrySpy.target = screen
        var recoverySpy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'recoveryRequested' }",
            screen, "recoverySpy")
        recoverySpy.target = screen

        screen.authState = "incorrect"
        screen.retryButton.clicked()
        compare(retrySpy.count, 1)

        screen.authState = "recovery"
        screen.recoveryButton.clicked()
        compare(recoverySpy.count, 1)

        screen.destroy()
    }

    // ── Status indicators react to host properties ─────────────────
    function test_statusIndicators() {
        var screen = createScreen()
        screen.networkStatusText = "Offline"
        screen.networkConnected = false
        compare(screen.networkStatusLabel.text, "Offline")
        verify(Qt.colorEqual(screen.networkDot.color, MissionTheme.textTertiary))

        screen.networkConnected = true
        verify(Qt.colorEqual(screen.networkDot.color, MissionTheme.success))

        screen.batteryStatusText = "10%"
        screen.batteryLevel = 10
        compare(screen.batteryStatusLabel.text, "10%")
        verify(Qt.colorEqual(screen.batteryFill.color, MissionTheme.warning))

        screen.batteryLevel = 80
        verify(Qt.colorEqual(screen.batteryFill.color, MissionTheme.success))

        screen.destroy()
    }

    // ── Clock: seeded at load, host-pinnable ───────────────────────
    function test_clockHostPin() {
        var screen = createScreen()
        // Host pins the displayed text and stops the live timer
        screen.clockTimeText = "06:15"
        screen.clockDateText = "Monday, January 1"
        screen.clockRunning = false
        compare(screen.clockTimeLabel.text, "06:15")
        compare(screen.clockDateLabel.text, "Monday, January 1")

        // updateClock() refreshes from the system clock on demand
        screen.updateClock()
        verify(screen.clockTimeLabel.text.length > 0)
        verify(screen.clockDateLabel.text.length > 0)

        screen.destroy()
    }

    // ── Keyboard focus reaches actionable controls ─────────────────
    function test_keyboardFocus() {
        var screen = createScreen("users: [ { name: 'alex', displayName: 'Alex' }, " +
                                           "{ name: 'sam', displayName: 'Sam' } ]")
        wait(100) // let the hosted window activate so Tab reaches the controls
        var hostWindow = _hostWindows[_hostWindows.length - 1]
        var controls = ["loginPassword", "loginLogin", "loginPower", "loginAccessibility",
                        "loginUserChip0"]
        var found = {}
        for (var i = 0; i < controls.length; ++i)
            found[controls[i]] = false

        for (var tab = 0; tab < 40; ++tab) {
            keyClick(Qt.Key_Tab)
            var focusItem = hostWindow.activeFocusItem
            if (focusItem && focusItem.objectName)
                found[focusItem.objectName] = true
        }

        for (var c = 0; c < controls.length; ++c)
            verify(found[controls[c]], "focus must reach " + controls[c])

        screen.destroy()
    }

    // ── Escape is deliberately unmapped (no signal fires) ──────────
    function test_noEscapeMapping() {
        var screen = createScreen("users: [ { name: 'alex', displayName: 'Alex' } ]")
        wait(100)
        var spies = []
        var names = ["loginRequested", "retryRequested", "recoveryRequested",
                     "accessibilityRequested", "shutdownRequested", "userSelected"]
        for (var i = 0; i < names.length; ++i) {
            var spy = Qt.createQmlObject(
                "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: '" +
                names[i] + "' }", screen, "escSpy" + i)
            spy.target = screen
            spies.push(spy)
        }

        // Escape with the password field focused must not dismiss the
        // login screen (host owns any escape behavior)
        screen.passwordField.forceActiveFocus()
        keyClick(Qt.Key_Escape)
        for (var s = 0; s < spies.length; ++s)
            compare(spies[s].count, 0, names[s] + " must not fire on Escape")

        // Escape on an account chip must not change the selection either
        screen.accountChooser.itemAt(0).forceActiveFocus()
        keyClick(Qt.Key_Escape)
        compare(screen.selectedUserIndex, 0)
        compare(spies[5].count, 0)

        screen.destroy()
    }

    // ── MissionPage / MissionWindow integration ────────────────────
    function test_missionPageIntegration() {
        var page = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionPage { pageTitle: 'Login'; Login { objectName: 'loginInPage' } }",
            root, "loginInPage")
        verify(page !== null)
        verify(page.data.length > 0)
        page.destroy()
    }

    function test_missionWindowIntegration() {
        var screen = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionWindow { width: 1024; height: 768; Login { objectName: 'loginInWindow' } }",
            root, "loginInWindow")
        verify(screen !== null)
        verify(screen.width > 0)
        screen.destroy()
    }

    // ── Accessibility roles ────────────────────────────────────────
    function test_accessibleRoles() {
        var screen = createScreen("users: [ { name: 'alex', displayName: 'Alex' }, " +
                                           "{ name: 'sam', displayName: 'Sam' } ]")
        // Clock + user name announced as static text
        verify(screen.clockTimeLabel.Accessible.role === Accessible.StaticText)
        verify(screen.clockTimeLabel.Accessible.name.length > 0)
        verify(screen.clockDateLabel.Accessible.role === Accessible.StaticText)
        verify(screen.clockDateLabel.Accessible.name.length > 0)
        verify(screen.userNameLabel.Accessible.role === Accessible.StaticText)
        // Avatar announced as a graphic with a name
        verify(screen.avatarPreview.Accessible.role === Accessible.Graphic)
        verify(screen.avatarPreview.Accessible.name.length > 0)
        // Password field announced as editable text
        verify(screen.passwordField.Accessible.role === Accessible.EditableText)
        verify(screen.passwordField.Accessible.name.length > 0)
        // Status indicators announced as named groups
        verify(screen.networkChip.Accessible.role === Accessible.Grouping)
        verify(screen.networkChip.Accessible.name.length > 0)
        verify(screen.batteryChip.Accessible.role === Accessible.Grouping)
        verify(screen.batteryChip.Accessible.name.length > 0)
        // Account chips announced as radios with checked state
        var chip0 = screen.accountChooser.itemAt(0)
        var chip1 = screen.accountChooser.itemAt(1)
        verify(chip0.Accessible.role === Accessible.RadioButton)
        verify(chip0.Accessible.name.length > 0)
        verify(chip0.Accessible.checked)
        verify(!chip1.Accessible.checked)
        screen.destroy()
    }

    // ── Reduced motion does not break rendering ────────────────────
    function test_reducedMotion() {
        var screen = createScreen("users: [ { name: 'alex', displayName: 'Alex' } ]")
        screen.reducedMotion = true
        screen.authState = "authenticating"
        verify(screen.authenticatingIndicator.visible)
        verify(!screen.loginButton.enabled)
        screen.authState = "locked"
        verify(screen.loginButton.enabled)
        screen.reducedMotion = false
        screen.destroy()
    }

    // Reset theme mode and destroy hosted test windows after each test
    // so tests never leak state or stray windows.
    function cleanup() {
        for (var i = 0; i < _hostWindows.length; ++i)
            _hostWindows[i].destroy()
        _hostWindows = []
        MissionTheme.darkMode = false
    }
}
