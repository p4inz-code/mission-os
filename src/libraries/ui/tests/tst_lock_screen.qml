// Mission OS — Lock Screen (MOS-LCK-001) QtTest suite
//
// Runtime validation of the Lock Screen. Follows the foundation
// smoke-test pattern (tests/tst_smoke.qml), the Installer Welcome suite
// (tests/tst_installer_welcome.qml) and docs/engineering/TESTING_STRATEGY.md
// (QML → Qt Test / qmltestrunner).
//
// Coverage:
//   - screen loads without QML errors (token singletons resolve)
//   - MissionTheme works; light/dark rendering bindings re-evaluate
//   - primary actions exist (Unlock / Power / Accessibility / Retry /
//     Recovery) and carry the right variants
//   - wireframe auth states: locked · authenticating · incorrect ·
//     recovery required — banners render, Unlock never fires while
//     blocked
//   - unlocking emits unlockRequested(password) from Enter and from the
//     Unlock button; typing is captured by the password field
//   - power menu (Shutdown / Restart / Suspend) routes to its signals
//   - network/battery status indicators react to host properties
//   - clock text is host-pinnable and seeded at load
//   - keyboard focus reaches the password field first, then the action
//     controls; Escape is deliberately unmapped (no signal fires)
//   - MissionPage / MissionWindow integration introduces no runtime errors
//   - accessibility roles (clock, avatar, password field, status chips)
//   - reduced motion does not break rendering
//
// Run via qmltestrunner (see CMakeLists.txt CTest registration):
//   qmltestrunner -import <build>/src/libraries/ui/qml \
//                 -input src/libraries/ui/tests/tst_lock_screen.qml
//
// Exit code: 0 = all checks passed; non-zero = failure (CI gate).

import QtQuick
import QtTest
import org.mission.ui 1.0

TestCase {
    id: root
    name: "LockScreen"

    // ── Helpers ────────────────────────────────────────────────────
    // The qmltestrunner harness does not show its own test window, so
    // items hosted directly under the TestCase report visible=false on
    // this Qt build (verified empirically). To validate real
    // visibility and keyboard-focus behavior, every screen under test
    // is hosted inside an explicit visible Window; cleanup() destroys
    // the host windows afterwards.
    property var _hostWindows: []

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
                     "    LockScreen { id: screen; width: 1024; height: 768; " +
                     (extra || "") + " }\n" +
                     "}"
        var host = Qt.createQmlObject(source, root, "lockHost")
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
        verify(screen.unlockButton.text.length > 0)
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
        var screen = createScreen()
        verify(screen.unlockButton !== null)
        verify(screen.powerButton !== null)
        verify(screen.accessibilityButton !== null)
        verify(screen.retryButton !== null)
        verify(screen.recoveryButton !== null)
        verify(screen.passwordField !== null)
        verify(screen.unlockButton.visible)
        verify(screen.unlockButton.enabled)
        // Unlock is the primary action; Power/Accessibility are secondary
        compare(screen.unlockButton.variant, MissionButton.Variant.Primary)
        compare(screen.powerButton.variant, MissionButton.Variant.Secondary)
        compare(screen.accessibilityButton.variant, MissionButton.Variant.Secondary)
        // Wireframe components: user avatar + status indicators present
        verify(screen.avatarPreview.visible)
        // Status indicators present but NEUTRAL until host data (FABRICATION-9)
        verify(screen.networkStatusLabel.text.length === 0)
        verify(screen.batteryStatusLabel.text.length === 0)
        screen.destroy()
    }

    // ── Auth states (wireframe: Locked · Authenticating · Incorrect ·
    //    Recovery Required) ─────────────────────────────────────────
    function test_authStateTransitions() {
        var screen = createScreen()
        // locked (default): field + Unlock enabled, no banners
        verify(screen.passwordField.enabled)
        verify(screen.unlockButton.enabled)
        verify(!screen.authenticatingIndicator.visible)
        verify(!screen.errorBanner.visible)
        verify(!screen.recoveryBanner.visible)

        // authenticating: progress shown, Unlock + field blocked
        screen.authState = "authenticating"
        verify(screen.authenticatingIndicator.visible)
        verify(screen.unlockButton.loading)
        verify(!screen.unlockButton.enabled)
        verify(!screen.passwordField.enabled)
        verify(!screen.errorBanner.visible)

        // incorrect: error banner + Retry, Unlock blocked
        screen.authState = "incorrect"
        verify(screen.errorBanner.visible)
        verify(screen.errorBanner.height > 0,
               "error banner must render with positive height (banner-height bug regression)")
        verify(screen.retryButton.visible)
        verify(!screen.unlockButton.enabled)
        verify(!screen.passwordField.enabled)

        // recovery: recovery banner + Recovery button, Unlock blocked
        screen.authState = "recovery"
        verify(screen.recoveryBanner.visible)
        verify(screen.recoveryBanner.height > 0,
               "recovery banner must render with positive height (banner-height bug regression)")
        verify(screen.recoveryButton.visible)
        verify(!screen.unlockButton.enabled)
        verify(!screen.passwordField.enabled)

        // back to locked clears everything
        screen.authState = "locked"
        verify(screen.passwordField.enabled)
        verify(screen.unlockButton.enabled)
        verify(!screen.authenticatingIndicator.visible)
        verify(!screen.errorBanner.visible)
        verify(!screen.recoveryBanner.visible)

        screen.destroy()
    }

    // ── Unlock must not fire while blocked (keyboard-safe) ─────────
    function test_unlockBlockedWhileAuthenticating() {
        var screen = createScreen()
        wait(100) // let the hosted window activate so key events reach it
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'unlockRequested' }",
            screen, "unlockSpyBlocked")
        spy.target = screen

        // Authenticating: Unlock disabled → no signal from keyboard
        screen.authState = "authenticating"
        verify(!screen.unlockButton.enabled)
        screen.unlockButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spy.count, 0)

        // Incorrect: Unlock disabled → no signal
        screen.authState = "incorrect"
        verify(!screen.unlockButton.enabled)
        screen.unlockButton.forceActiveFocus()
        keyClick(Qt.Key_Return)
        compare(spy.count, 0)

        // Locked: Unlock enabled → keyboard input unlocks
        screen.authState = "locked"
        verify(screen.unlockButton.enabled)
        screen.unlockButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spy.count, 1)

        screen.destroy()
    }

    // ── Unlock signal carries the entered password ─────────────────
    function test_unlockSignalWithPassword() {
        var screen = createScreen()
        wait(100) // window activation for key delivery
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'unlockRequested' }",
            screen, "unlockSpyPassword")
        spy.target = screen

        // Typing into the password field, then Enter → unlock with text
        screen.passwordField.forceActiveFocus()
        typeChars("mission1")
        compare(screen.passwordField.text, "mission1")
        keyClick(Qt.Key_Return)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "mission1")

        // The Unlock button also submits the current field text.
        // Clear the field first — typeChars appends, and TextField does
        // not clear on accepted (otherwise this would send "mission1secret2").
        screen.passwordField.clear()
        screen.passwordField.forceActiveFocus()
        typeChars("secret2")
        compare(screen.passwordField.text, "secret2")
        screen.unlockButton.clicked()
        compare(spy.count, 2)
        compare(spy.signalArguments[1][0], "secret2")

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

    // ── Host-absent defaults are neutral (FABRICATION-9 regression) ─
    function test_hostAbsentDefaultsNeutral() {
        var screen = createScreen()
        compare(screen.batteryStatusText, "")
        compare(screen.networkStatusText, "")
        verify(!screen.networkConnected)
        verify(screen.batteryLevel < 0)
        verify(!screen.batteryFill.visible, "battery fill must be hidden when the level is unknown")
        compare(screen.batteryStatusLabel.text, "")
        compare(screen.networkStatusLabel.text, "")
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

    // ── Avatar reflects the signed-in user ─────────────────────────
    function test_avatarInitial() {
        var screen = createScreen()
        verify(screen.avatarInitial === "\u2022") // neutral dot while no user
        screen.userName = "Alex"
        compare(screen.avatarInitial, "A")
        compare(screen.userNameLabel.text, "Alex")
        screen.userName = ""
        verify(screen.avatarInitial === "\u2022")
        compare(screen.userNameLabel.text, "Guest")
        screen.destroy()
    }

    // ── Keyboard focus reaches actionable controls ─────────────────
    function test_keyboardFocus() {
        var screen = createScreen()
        wait(100) // let the hosted window activate so Tab reaches the controls
        var hostWindow = _hostWindows[_hostWindows.length - 1]
        var controls = ["lockPassword", "lockUnlock", "lockPower", "lockAccessibility"]
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
        var screen = createScreen()
        wait(100)
        var spies = []
        var names = ["unlockRequested", "retryRequested", "recoveryRequested",
                     "accessibilityRequested", "shutdownRequested"]
        for (var i = 0; i < names.length; ++i) {
            var spy = Qt.createQmlObject(
                "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: '" +
                names[i] + "' }", screen, "escSpy" + i)
            spy.target = screen
            spies.push(spy)
        }

        // Escape with the password field focused must not dismiss the
        // lock screen (host owns any escape behavior)
        screen.passwordField.forceActiveFocus()
        keyClick(Qt.Key_Escape)
        for (var s = 0; s < spies.length; ++s)
            compare(spies[s].count, 0, names[s] + " must not fire on Escape")

        screen.destroy()
    }

    // ── MissionPage / MissionWindow integration ────────────────────
    function test_missionPageIntegration() {
        var page = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionPage { pageTitle: 'Lock'; LockScreen { objectName: 'lockInPage' } }",
            root, "lockInPage")
        verify(page !== null)
        verify(page.data.length > 0)
        page.destroy()
    }

    function test_missionWindowIntegration() {
        var screen = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionWindow { width: 1024; height: 768; LockScreen { objectName: 'lockInWindow' } }",
            root, "lockInWindow")
        verify(screen !== null)
        verify(screen.width > 0)
        screen.destroy()
    }

    // ── Accessibility roles ────────────────────────────────────────
    function test_accessibleRoles() {
        var screen = createScreen()
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
        screen.destroy()
    }

    // ── Reduced motion does not break rendering ────────────────────
    function test_reducedMotion() {
        var screen = createScreen()
        screen.reducedMotion = true
        screen.authState = "authenticating"
        verify(screen.authenticatingIndicator.visible)
        verify(!screen.unlockButton.enabled)
        screen.authState = "locked"
        verify(screen.unlockButton.enabled)
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
