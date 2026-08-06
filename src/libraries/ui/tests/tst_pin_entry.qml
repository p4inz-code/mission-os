// Mission OS — PIN Entry (MOS-LCK-003) QtTest suite
//
// Runtime validation of the PIN Entry screen. Follows the foundation
// smoke-test pattern (tests/tst_smoke.qml), the Lock Screen suite
// (tests/tst_lock_screen.qml), the Login suite (tests/tst_login.qml)
// and docs/engineering/TESTING_STRATEGY.md (QML → Qt Test /
// qmltestrunner).
//
// Coverage:
//   - screen loads without QML errors (token singletons resolve)
//   - MissionTheme works; light/dark rendering bindings re-evaluate
//   - primary actions exist (keypad keys, Unlock submit, Backspace,
//     Use password, Power, Accessibility, Retry, Recovery) and carry
//     the right variants
//   - wireframe auth states: locked · authenticating · incorrect ·
//     recovery required — banners render, submit never fires while
//     blocked
//   - PIN entry via the keypad (digit keys append, Backspace deletes,
//     Unlock submits) and via the keyboard (number keys append, Return
//     submits, Backspace deletes)
//   - pinSubmitted(pin) carries the entered digits from the keypad and
//     from the keyboard; empty PIN submission is host-decided (family
//     contract, same as MOS-LCK-001/002 empty password)
//   - pinMaxLength caps the keypad and the masked dot display
//   - Use password routes to passwordRequested (MOS-LCK-001/002)
//   - power menu (Shutdown / Restart / Suspend) routes to its signals
//   - network/battery status indicators react to host properties
//   - clock text is host-pinnable and seeded at load
//   - avatar reflects the signed-in user
//   - keyboard focus reaches the keypad, then the action controls;
//     Escape is deliberately unmapped (no signal fires)
//   - MissionPage / MissionWindow integration introduces no runtime errors
//   - accessibility roles (clock, avatar, PIN display, keypad keys,
//     status chips) and names (Backspace / Unlock with PIN)
//   - reduced motion does not break rendering
//
// Run via qmltestrunner (see CMakeLists.txt CTest registration):
//   qmltestrunner -import <build>/src/libraries/ui/qml \
//                 -input src/libraries/ui/tests/tst_pin_entry.qml
//
// Exit code: 0 = all checks passed; non-zero = failure (CI gate).

import QtQuick
import QtTest
import org.mission.ui 1.0

TestCase {
    id: root
    name: "PinEntry"

    // ── Helpers ────────────────────────────────────────────────────
    // The qmltestrunner harness does not show its own test window, so
    // items hosted directly under the TestCase report visible=false on
    // this Qt build (verified empirically). To validate real
    // visibility and keyboard-focus behavior, every screen under test
    // is hosted inside an explicit visible Window; cleanup() destroys
    // the host windows afterwards.
    property var _hostWindows: []

    // Keypad model order (matches PinEntry.qml keypadModel):
    // indices 0-8 = digits 1-9, 9 = Backspace, 10 = 0, 11 = Unlock
    property int _keyBackspace: 9
    property int _keyZero: 10
    property int _keySubmit: 11

    function createScreen(extra) {
        var source = "import QtQuick\n" +
                     "import org.mission.ui 1.0\n" +
                     "Window {\n" +
                     "    width: 1024; height: 768; visible: true\n" +
                     "    property alias screen: screen\n" +
                     "    PinEntry { id: screen; width: 1024; height: 768; " +
                     (extra || "") + " }\n" +
                     "}"
        var host = Qt.createQmlObject(source, root, "pinHost")
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
        verify(screen.pinDisplay !== null)
        verify(screen.keypadGrid !== null)
        verify(screen.keypad.count === 12)
        verify(screen.avatarPreview !== null)
        // Masked display shows one slot per pinMaxLength position
        verify(screen.pinSlots.count === screen.pinMaxLength)
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
        verify(screen.keypad.count === 12)
        // Keypad: digits 1-9, Backspace, 0, Unlock
        compare(screen.keypad.itemAt(0).text, "1")
        compare(screen.keypad.itemAt(4).text, "5")
        compare(screen.keypad.itemAt(8).text, "9")
        compare(screen.keypad.itemAt(_keyBackspace).text, "\u232B")
        compare(screen.keypad.itemAt(_keyZero).text, "0")
        compare(screen.keypad.itemAt(_keySubmit).text, "Unlock")
        // Unlock is the primary action on the pad; digits are secondary
        compare(screen.keypad.itemAt(_keySubmit).variant, MissionButton.Variant.Primary)
        compare(screen.keypad.itemAt(0).variant, MissionButton.Variant.Secondary)
        // Wireframe actions: power + accessibility are secondary;
        // Use password is tertiary (routing link, not a primary action)
        verify(screen.powerButton !== null)
        verify(screen.accessibilityButton !== null)
        verify(screen.passwordButton !== null)
        verify(screen.retryButton !== null)
        verify(screen.recoveryButton !== null)
        verify(screen.passwordButton.visible)
        verify(screen.passwordButton.enabled)
        compare(screen.powerButton.variant, MissionButton.Variant.Secondary)
        compare(screen.accessibilityButton.variant, MissionButton.Variant.Secondary)
        compare(screen.passwordButton.variant, MissionButton.Variant.Tertiary)
        // Wireframe components: user avatar + status indicators present
        verify(screen.avatarPreview.visible)
        verify(screen.networkStatusLabel.text.length > 0)
        verify(screen.batteryStatusLabel.text.length > 0)
        screen.destroy()
    }

    // ── Auth states (wireframe: Locked · Authenticating · Incorrect ·
    //    Recovery Required) ─────────────────────────────────────────
    function test_authStateTransitions() {
        var screen = createScreen()
        // locked (default): keys + Use password enabled, no banners
        verify(screen.keypad.itemAt(0).enabled)
        verify(screen.keypad.itemAt(_keySubmit).enabled)
        verify(screen.passwordButton.enabled)
        verify(!screen.authenticatingIndicator.visible)
        verify(!screen.errorBanner.visible)
        verify(!screen.recoveryBanner.visible)

        // authenticating: progress shown, keys + link blocked
        screen.authState = "authenticating"
        verify(screen.authenticatingIndicator.visible)
        verify(screen.keypad.itemAt(_keySubmit).loading)
        verify(!screen.keypad.itemAt(_keySubmit).enabled)
        verify(!screen.keypad.itemAt(0).enabled)
        verify(!screen.passwordButton.enabled)
        verify(!screen.errorBanner.visible)

        // incorrect: error banner + Retry, keys blocked
        screen.authState = "incorrect"
        verify(screen.errorBanner.visible)
        verify(screen.errorBanner.height > 0,
               "error banner must render with positive height (banner-height bug regression)")
        verify(screen.retryButton.visible)
        verify(!screen.keypad.itemAt(_keySubmit).enabled)
        verify(!screen.keypad.itemAt(0).enabled)
        verify(!screen.passwordButton.enabled)

        // recovery: recovery banner + Recovery button, keys blocked
        screen.authState = "recovery"
        verify(screen.recoveryBanner.visible)
        verify(screen.recoveryBanner.height > 0,
               "recovery banner must render with positive height (banner-height bug regression)")
        verify(screen.recoveryButton.visible)
        verify(!screen.keypad.itemAt(_keySubmit).enabled)
        verify(!screen.keypad.itemAt(0).enabled)
        verify(!screen.passwordButton.enabled)

        // back to locked clears everything
        screen.authState = "locked"
        verify(screen.keypad.itemAt(0).enabled)
        verify(screen.keypad.itemAt(_keySubmit).enabled)
        verify(screen.passwordButton.enabled)
        verify(!screen.authenticatingIndicator.visible)
        verify(!screen.errorBanner.visible)
        verify(!screen.recoveryBanner.visible)

        screen.destroy()
    }

    // ── Submit must not fire while blocked (keyboard-safe) ─────────
    function test_submitBlockedWhileAuthenticating() {
        var screen = createScreen()
        wait(100) // let the hosted window activate so key events reach it
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'pinSubmitted' }",
            screen, "pinSpyBlocked")
        spy.target = screen

        // Authenticating: keys disabled → no signal from keyboard
        screen.authState = "authenticating"
        verify(!screen.keypad.itemAt(_keySubmit).enabled)
        screen.keypad.itemAt(_keySubmit).forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spy.count, 0)
        keyClick(Qt.Key_Return)
        compare(spy.count, 0)

        // Incorrect: keys disabled → no signal
        screen.authState = "incorrect"
        verify(!screen.keypad.itemAt(_keySubmit).enabled)
        screen.keypad.itemAt(_keySubmit).forceActiveFocus()
        keyClick(Qt.Key_Return)
        compare(spy.count, 0)

        // Locked: submit enabled → keyboard input submits
        screen.authState = "locked"
        verify(screen.keypad.itemAt(_keySubmit).enabled)
        screen.keypad.itemAt(_keySubmit).forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spy.count, 1)

        screen.destroy()
    }

    // ── PIN entry via the keypad (mouse/click path) ────────────────
    function test_pinEntryViaKeypad() {
        var screen = createScreen()
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'pinSubmitted' }",
            screen, "pinSpyKeypad")
        spy.target = screen

        // Click digits 1, 2, 3 → "123"
        screen.keypad.itemAt(0).clicked()   // 1
        screen.keypad.itemAt(1).clicked()   // 2
        screen.keypad.itemAt(2).clicked()   // 3
        compare(screen.pinText, "123")
        compare(screen.pinLength, 3)
        // Masked display: filled slots for entered digits
        verify(screen.pinSlots.itemAt(0).color !== "transparent")
        verify(screen.pinSlots.itemAt(2).color !== "transparent")
        verify(Qt.colorEqual(screen.pinSlots.itemAt(3).color, "transparent"))

        // Backspace removes the last digit
        screen.keypad.itemAt(_keyBackspace).clicked()
        compare(screen.pinText, "12")

        // Zero key appends "0"
        screen.keypad.itemAt(_keyZero).clicked()
        compare(screen.pinText, "120")

        // Unlock submits the entered digits
        screen.keypad.itemAt(_keySubmit).clicked()
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "120")

        screen.destroy()
    }

    // ── clearPin resets the entered digits ─────────────────────────
    function test_clearPin() {
        var screen = createScreen()
        screen.keypad.itemAt(0).clicked()   // 1
        screen.keypad.itemAt(1).clicked()   // 2
        compare(screen.pinText, "12")
        screen.clearPin()
        compare(screen.pinText, "")
        compare(screen.pinLength, 0)
        // Masked display slots reset to hollow
        verify(Qt.colorEqual(screen.pinSlots.itemAt(0).color, "transparent"))
        // Entry continues normally after clearing
        screen.keypad.itemAt(2).clicked()   // 3
        compare(screen.pinText, "3")
        screen.destroy()
    }

    // ── PIN entry via the keyboard (keyboard-first path) ───────────
    function test_pinEntryViaKeyboard() {
        var screen = createScreen()
        wait(100) // window activation for key delivery
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'pinSubmitted' }",
            screen, "pinSpyKbd")
        spy.target = screen

        // Number keys append digits (captured screen-wide by the root)
        screen.forceActiveFocus()
        keyClick(Qt.Key_4)
        keyClick(Qt.Key_5)
        keyClick(Qt.Key_6)
        compare(screen.pinText, "456")

        // Backspace deletes the last digit
        keyClick(Qt.Key_Backspace)
        compare(screen.pinText, "45")

        // Return submits
        keyClick(Qt.Key_Return)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "45")

        screen.destroy()
    }

    // ── Keyboard digits also work while a keypad key is focused ────
    function test_keyboardDigitsFromFocusedKey() {
        var screen = createScreen()
        wait(100)
        // Focus a digit key; number keys still append because the root
        // key handler receives unaccepted key events via propagation.
        screen.keypad.itemAt(0).forceActiveFocus()
        keyClick(Qt.Key_7)
        compare(screen.pinText, "7")
        screen.destroy()
    }

    // ── pinMaxLength caps the keypad and the dot display ───────────
    function test_pinMaxLengthCap() {
        var screen = createScreen("pinMaxLength: 4")
        compare(screen.pinSlots.count, 4)
        wait(100) // window activation for key delivery (first key is
                  // otherwise dropped before the window activates)
        // Enter one digit more than the cap via the keyboard
        screen.forceActiveFocus()
        keyClick(Qt.Key_1)
        keyClick(Qt.Key_2)
        keyClick(Qt.Key_3)
        keyClick(Qt.Key_4)
        compare(screen.pinText, "1234")
        verify(screen.pinFull)
        // Extra digits are ignored (both keyboard and keypad paths)
        keyClick(Qt.Key_5)
        compare(screen.pinText, "1234")
        screen.keypad.itemAt(8).clicked() // 9
        compare(screen.pinText, "1234")
        screen.destroy()
    }

    // ── Use password routes to MOS-LCK-001/002 ─────────────────────
    function test_passwordRoute() {
        var screen = createScreen()
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'passwordRequested' }",
            screen, "passwordSpy")
        spy.target = screen
        screen.passwordButton.clicked()
        compare(spy.count, 1)
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
        var controls = ["pinKey0", "pinKey11", "pinPassword", "pinPower", "pinAccessibility"]
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
        var names = ["pinSubmitted", "passwordRequested", "retryRequested",
                     "recoveryRequested", "accessibilityRequested", "shutdownRequested"]
        for (var i = 0; i < names.length; ++i) {
            var spy = Qt.createQmlObject(
                "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: '" +
                names[i] + "' }", screen, "escSpy" + i)
            spy.target = screen
            spies.push(spy)
        }

        // Escape with the PIN screen focused must not dismiss it (host
        // owns any escape behavior)
        screen.forceActiveFocus()
        keyClick(Qt.Key_Escape)
        for (var s = 0; s < spies.length; ++s)
            compare(spies[s].count, 0, names[s] + " must not fire on Escape")

        // Escape on a focused keypad key must not change the PIN either
        screen.keypad.itemAt(0).forceActiveFocus()
        keyClick(Qt.Key_Escape)
        compare(screen.pinText, "")
        compare(spies[0].count, 0)

        screen.destroy()
    }

    // ── MissionPage / MissionWindow integration ────────────────────
    function test_missionPageIntegration() {
        var page = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionPage { pageTitle: 'PIN'; PinEntry { objectName: 'pinInPage' } }",
            root, "pinInPage")
        verify(page !== null)
        verify(page.data.length > 0)
        page.destroy()
    }

    function test_missionWindowIntegration() {
        var screen = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionWindow { width: 1024; height: 768; PinEntry { objectName: 'pinInWindow' } }",
            root, "pinInWindow")
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
        // PIN display announced as static text carrying the digit count
        verify(screen.pinDisplay.Accessible.role === Accessible.StaticText)
        verify(screen.pinDisplay.Accessible.name.indexOf("0 of") >= 0)
        // Status indicators announced as named groups
        verify(screen.networkChip.Accessible.role === Accessible.Grouping)
        verify(screen.networkChip.Accessible.name.length > 0)
        verify(screen.batteryChip.Accessible.role === Accessible.Grouping)
        verify(screen.batteryChip.Accessible.name.length > 0)
        // Keypad keys announced as buttons with meaningful names
        verify(screen.keypad.itemAt(0).Accessible.role === Accessible.Button)
        verify(screen.keypad.itemAt(0).Accessible.name === "1")
        verify(screen.keypad.itemAt(_keyBackspace).Accessible.name === "Backspace")
        verify(screen.keypad.itemAt(_keySubmit).Accessible.name === "Unlock with PIN")
        screen.destroy()
    }

    // ── Reduced motion does not break rendering ────────────────────
    function test_reducedMotion() {
        var screen = createScreen()
        screen.reducedMotion = true
        screen.authState = "authenticating"
        verify(screen.authenticatingIndicator.visible)
        verify(!screen.keypad.itemAt(_keySubmit).enabled)
        screen.authState = "locked"
        verify(screen.keypad.itemAt(_keySubmit).enabled)
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
