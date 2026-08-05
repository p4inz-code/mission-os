// Mission OS — Installer User Account (MOS-INS-008) QtTest suite
//
// Runtime validation of the User Account screen. Follows the
// foundation smoke-test pattern (tests/tst_smoke.qml) and the
// MOS-INS-001 InstallerWelcome, MOS-INS-002 Language, MOS-INS-003
// Keyboard, MOS-INS-004 Network, MOS-INS-005 Privacy, MOS-INS-006 Disk
// and MOS-INS-007 Partition suites (tests/tst_installer_welcome.qml …
// tst_partition_manager.qml) per docs/engineering/TESTING_STRATEGY.md
// (QML → Qt Test / qmltestrunner).
//
// Coverage (only behaviors required by the authoritative sources —
// reference Screen 10 "User Account", registry MOS-INS-008):
//   - screen loads without QML errors (token singletons resolve)
//   - default state: all required fields empty, Continue disabled
//     (validation before continuing); optional defaults Automatic login
//     off, Require password after sleep on; no avatar selected change
//   - no spurious action or host-change signals on load
//   - the five required fields (display name, username, computer name,
//     password, password confirmation) validate live: Continue enables
//     only when all are complete and the passwords match
//   - password strength is evaluated in real time (score, level,
//     label, meter segments) and weak passwords generate warnings
//   - optional controls: automatic login + require password after
//     sleep switches and the profile picture avatar selector
//   - user edits fire the host-change signal exactly per change
//     (never on load); switches and avatar selection fire on user action
//   - required signals fire from the right controls (continue/back/retry)
//   - required state transitions (empty/loading/error/success/offline)
//   - Continue is blocked while loading/error (validation-before-continue)
//   - state banners render with positive height (banner-height regression)
//   - keyboard focus reaches the editable fields, switches, avatar
//     chips, Back and Continue; Escape navigates back
//   - responsive compact layout (help panel collapses)
//   - reduced motion does not break rendering
//   - MissionPage / MissionWindow integration introduces no runtime errors
//
// Run via qmltestrunner (see CMakeLists.txt CTest registration):
//   qmltestrunner -import <build>/src/libraries/ui/qml \
//                 -input src/libraries/ui/tests/tst_user_account.qml
//
// Exit code: 0 = all checks passed; non-zero = failure (CI gate).

import QtQuick
import QtTest
import org.mission.ui 1.0

TestCase {
    id: root
    name: "UserAccount"

    // ── Helpers ────────────────────────────────────────────────────
    // Same hosted-window pattern as the other suites: items hosted
    // directly under the TestCase report visible=false on this Qt build,
    // so every screen under test lives in an explicit visible Window;
    // cleanup() destroys the host windows afterwards.
    property var _hostWindows: []

    function createScreen(extra) {
        return createScreenAt(1024, 768, extra)
    }

    function createScreenAt(width, height, extra) {
        var source = "import QtQuick\n" +
                     "import org.mission.ui 1.0\n" +
                     "Window {\n" +
                     "    width: " + width + "; height: " + height + "; visible: true\n" +
                     "    property alias screen: screen\n" +
                     "    UserAccount { id: screen; width: " + width + "; height: " + height + "; " +
                     (extra || "") + " }\n" +
                     "}"
        var host = Qt.createQmlObject(source, root, "userHost")
        _hostWindows.push(host)
        return host.screen
    }

    /// Fill every required field with a complete, matching, valid set.
    function fillCompleteForm(screen) {
        screen.displayNameField.text = "Alex Johnson"
        screen.usernameField.text = "alex"
        screen.computerNameField.text = "alex-pc"
        screen.passwordField.text = "Mission0S!"
        screen.passwordConfirmField.text = "Mission0S!"
    }

    // ── Screen loads; tokens resolve; no QML errors ────────────────
    function test_screenLoads() {
        var screen = createScreen()
        verify(screen !== null)
        verify(screen.height > 0)
        // Token singletons must resolve through the screen's bindings
        verify(Qt.colorEqual(screen.backgroundColor, Colors.background))
        verify(Qt.colorEqual(screen.headingColor, Colors.textPrimary))
        verify(screen.headingLabel.text.length > 0)
        verify(screen.continueButton.text.length > 0)
        // Step context: User Account is installer step 8 of 12
        compare(screen.step, 8)
        compare(screen.totalSteps, 17)
        // Required fields exist (reference Screen 10)
        verify(screen.displayNameField !== null)
        verify(screen.usernameField !== null)
        verify(screen.computerNameField !== null)
        verify(screen.passwordField !== null)
        verify(screen.passwordConfirmField !== null)
        // Optional controls exist (reference Screen 10)
        verify(screen.autoLoginSwitch !== null)
        verify(screen.sleepPasswordSwitch !== null)
        compare(screen.avatarCount, 6)
        compare(screen.requiredFieldCount, 5)
        // Defaults: empty form → Continue disabled (validation first),
        // Automatic login off, Require password after sleep on, avatar
        // None preselected.
        compare(screen.filledFieldCount, 0)
        verify(!screen.formComplete)
        verify(!screen.continueButton.enabled)
        compare(screen.automaticLogin, false)
        compare(screen.requirePasswordAfterSleep, true)
        compare(screen.profilePicture, "none")
        compare(screen.selectedAvatarIndex, 0)
        screen.destroy()
    }

    // ── Defaults must not emit spurious signals ────────────────────
    // Regression guard: no action signal and no host-change signal may
    // fire on load (same contract as 002–007; rule: initial/default
    // values never emit host-change signals).
    function test_noSignalsOnLoad() {
        var source = "import QtQuick\n" +
                     "import QtTest\n" +
                     "import org.mission.ui 1.0\n" +
                     "Window {\n" +
                     "    width: 1024; height: 768; visible: true\n" +
                     "    property alias screen: screen\n" +
                     "    property alias spyC: spyC\n" +
                     "    property alias spyB: spyB\n" +
                     "    property alias spyR: spyR\n" +
                     "    property alias spyA: spyA\n" +
                     "    UserAccount { id: screen; width: 1024; height: 768\n" +
                     "        SignalSpy { id: spyC; signalName: 'continueRequested'; target: screen }\n" +
                     "        SignalSpy { id: spyB; signalName: 'backRequested'; target: screen }\n" +
                     "        SignalSpy { id: spyR; signalName: 'retryRequested'; target: screen }\n" +
                     "        SignalSpy { id: spyA; signalName: 'accountChangeRequested'; target: screen }\n" +
                     "    }\n" +
                     "}\n"
        var host = Qt.createQmlObject(source, root, "userLoadHost")
        _hostWindows.push(host)
        compare(host.spyC.count, 0)
        compare(host.spyB.count, 0)
        compare(host.spyR.count, 0)
        compare(host.spyA.count, 0)
        host.destroy()
    }

    // ── MissionTheme light/dark rendering bindings ─────────────────
    function test_themeLightAndDark() {
        var screen = createScreen()
        MissionTheme.darkMode = false
        verify(Qt.colorEqual(screen.backgroundColor, Colors.background))
        verify(Qt.colorEqual(screen.backgroundColor, MissionTheme.background))
        verify(Qt.colorEqual(screen.headingColor, MissionTheme.textPrimary))

        MissionTheme.darkMode = true
        verify(Qt.colorEqual(screen.backgroundColor, Colors.darkBackground))
        verify(Qt.colorEqual(screen.backgroundColor, MissionTheme.background))
        verify(Qt.colorEqual(screen.headingColor, MissionTheme.textPrimary))

        MissionTheme.darkMode = false
        verify(Qt.colorEqual(screen.backgroundColor, Colors.background))
        screen.destroy()
    }

    // ── Required fields validate live (validation before continue) ─
    function test_requiredFieldsValidation() {
        var screen = createScreen()
        verify(!screen.continueButton.enabled)

        // One field at a time: still incomplete
        screen.displayNameField.text = "Alex Johnson"
        compare(screen.filledFieldCount, 1)
        verify(!screen.formComplete)
        verify(!screen.continueButton.enabled)

        screen.usernameField.text = "alex"
        screen.computerNameField.text = "alex-pc"
        screen.passwordField.text = "Mission0S!"
        screen.passwordConfirmField.text = "Mission0S!"
        compare(screen.filledFieldCount, 5)
        verify(screen.passwordsMatch)
        verify(screen.formComplete)
        verify(screen.continueButton.enabled)

        // Clearing any required field disables Continue again
        screen.usernameField.text = ""
        compare(screen.filledFieldCount, 4)
        verify(!screen.formComplete)
        verify(!screen.continueButton.enabled)
        screen.destroy()
    }

    // ── Passwords must match (validation before continue) ──────────
    function test_passwordsMustMatch() {
        var screen = createScreen()
        screen.displayNameField.text = "Alex Johnson"
        screen.usernameField.text = "alex"
        screen.computerNameField.text = "alex-pc"
        screen.passwordField.text = "Mission0S!"
        screen.passwordConfirmField.text = "Different1!"
        compare(screen.filledFieldCount, 5)
        verify(!screen.passwordsMatch)
        verify(!screen.formComplete)
        verify(!screen.continueButton.enabled)
        // The live caption states the mismatch
        verify(screen.formCaption.text.indexOf("do not match") >= 0)

        // Matching confirms the form
        screen.passwordConfirmField.text = "Mission0S!"
        verify(screen.passwordsMatch)
        verify(screen.formComplete)
        verify(screen.continueButton.enabled)
        screen.destroy()
    }

    // ── Password strength: real-time evaluation + weak warning ─────
    // Reference Screen 10: "The installer should evaluate password
    // strength in real time. Weak passwords should generate warnings."
    function test_passwordStrength() {
        var screen = createScreen()

        // Empty password: no evaluation, meter empty, no warning
        compare(screen.passwordScore, 0)
        compare(screen.passwordStrengthLevel, 0)
        compare(screen.passwordStrengthLabel, "")
        verify(!screen.weakPassword)
        verify(!screen.weakWarning.visible)
        verify(Qt.colorEqual(screen.strengthSegments.itemAt(0).color, MissionTheme.surfaceDim))

        // Weak: "short" (lowercase only, < 8 chars) → level 1 + warning
        screen.passwordField.text = "short"
        compare(screen.passwordScore, 1)
        compare(screen.passwordStrengthLevel, 1)
        compare(screen.passwordStrengthLabel, "Weak")
        verify(screen.weakPassword)
        verify(screen.weakWarning.visible)
        // Meter: one warning-colored segment filled
        verify(Qt.colorEqual(screen.strengthSegments.itemAt(0).color, MissionTheme.warning))
        verify(Qt.colorEqual(screen.strengthSegments.itemAt(1).color, MissionTheme.surfaceDim))

        // Fair: length + upper + lower (no digit/symbol) → level 2
        screen.passwordField.text = "Abcdefgh"
        compare(screen.passwordScore, 3)
        compare(screen.passwordStrengthLevel, 2)
        compare(screen.passwordStrengthLabel, "Fair")
        verify(!screen.weakPassword)
        verify(!screen.weakWarning.visible)

        // Good: length + upper + lower + digit → level 3
        screen.passwordField.text = "Abcdef1g"
        compare(screen.passwordScore, 4)
        compare(screen.passwordStrengthLabel, "Good")
        verify(!screen.weakWarning.visible)

        // Strong: length + upper + lower + digit + symbol → level 4
        screen.passwordField.text = "Mission0S!"
        compare(screen.passwordScore, 5)
        compare(screen.passwordStrengthLevel, 4)
        compare(screen.passwordStrengthLabel, "Strong")
        verify(!screen.weakPassword)
        verify(!screen.weakWarning.visible)
        // Meter fully filled with the success color
        verify(Qt.colorEqual(screen.strengthSegments.itemAt(0).color, MissionTheme.success))
        verify(Qt.colorEqual(screen.strengthSegments.itemAt(3).color, MissionTheme.success))
        screen.destroy()
    }

    // ── Weak passwords warn but do not block continuing ────────────
    // Reference Screen 10: "Weak passwords should generate warnings."
    // Validation requires a complete + matching password — a weak one
    // warns (visible warning + warning label) but Continue stays
    // available (the documented, tested interpretation).
    function test_weakPasswordWarnsButDoesNotBlock() {
        var screen = createScreen()
        screen.displayNameField.text = "Alex Johnson"
        screen.usernameField.text = "alex"
        screen.computerNameField.text = "alex-pc"
        screen.passwordField.text = "short"
        screen.passwordConfirmField.text = "short"
        compare(screen.filledFieldCount, 5)
        compare(screen.passwordStrengthLabel, "Weak")
        verify(screen.weakPassword)
        verify(screen.weakWarning.visible)
        // The warning does not block continuing
        verify(screen.passwordsMatch)
        verify(screen.formComplete)
        verify(screen.continueButton.enabled)
        screen.destroy()
    }

    // ── User edits fire the host-change signal (never on load) ─────
    // Real keyboard input: typing into a field updates the screen
    // property and fires accountChangeRequested once per keystroke.
    function test_typingEmitsChange() {
        var screen = createScreen()
        wait(100) // let the hosted window activate so key events reach it
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'accountChangeRequested' }",
            screen, "userTypeSpy")
        spy.target = screen

        // Warm up the hosted window (first key event is consumed by
        // window activation on this build — same pattern as 001–007).
        screen.continueButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        screen.usernameField.forceActiveFocus()

        keyClick(Qt.Key_A)
        keyClick(Qt.Key_L)
        keyClick(Qt.Key_E)
        keyClick(Qt.Key_X)
        compare(screen.username, "alex")
        compare(spy.count, 4)
        // Last emission carries the field name and the current value
        var lastArgs = spy.signalArguments[spy.count - 1]
        compare(lastArgs[0], "username")
        compare(lastArgs[1], "alex")
        screen.destroy()
    }

    // ── Optional switches (reference Screen 10) ────────────────────
    // Real keyboard interaction: Space toggles the focused switch and
    // fires accountChangeRequested with the field name + new state.
    function test_switchBehavior() {
        var screen = createScreen()
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'accountChangeRequested' }",
            screen, "userSwitchSpy")
        spy.target = screen

        // Automatic login: off by default; Space toggles it on
        compare(screen.autoLoginSwitch.checked, false)
        keyClick(Qt.Key_Tab) // warm up the hosted window (activation)
        screen.autoLoginSwitch.forceActiveFocus()
        verify(screen.autoLoginSwitch.activeFocus)
        keyClick(Qt.Key_Space)
        compare(screen.autoLoginSwitch.checked, true)
        compare(screen.automaticLogin, true)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "automaticLogin")
        compare(spy.signalArguments[0][1], true)

        // Space toggles it back off
        keyClick(Qt.Key_Space)
        compare(screen.autoLoginSwitch.checked, false)
        compare(screen.automaticLogin, false)
        compare(spy.count, 2)
        compare(spy.signalArguments[1][0], "automaticLogin")
        compare(spy.signalArguments[1][1], false)

        // Require password after sleep: on by default (security by
        // default); Space toggles it off
        compare(screen.sleepPasswordSwitch.checked, true)
        compare(screen.requirePasswordAfterSleep, true)
        screen.sleepPasswordSwitch.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(screen.sleepPasswordSwitch.checked, false)
        compare(screen.requirePasswordAfterSleep, false)
        compare(spy.count, 3)
        compare(spy.signalArguments[2][0], "requirePasswordAfterSleep")
        compare(spy.signalArguments[2][1], false)
        screen.destroy()
    }

    // ── Profile picture: preset avatar selector (optional) ─────────
    function test_avatarSelection() {
        var screen = createScreen()
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'accountChangeRequested' }",
            screen, "userAvatarSpy")
        spy.target = screen

        // Default: None preselected, preview renders the none outline
        compare(screen.profilePicture, "none")
        compare(screen.selectedAvatarIndex, 0)

        // Selecting a preset via real keyboard interaction
        wait(100)
        var chip = screen.avatarRows.itemAt(3) // "Green" (success)
        verify(chip !== null)
        keyClick(Qt.Key_Tab) // warm up the hosted window (activation)
        chip.forceActiveFocus()
        verify(chip.activeFocus)
        keyClick(Qt.Key_Return)
        compare(screen.selectedAvatarIndex, 3)
        compare(screen.profilePicture, "success")
        var args = spy.signalArguments[spy.count - 1]
        compare(args[0], "profilePicture")
        compare(args[1], "success")
        // Preview follows the selection (existing token color)
        verify(Qt.colorEqual(screen.avatarPreview.color, MissionTheme.success))

        // Back to None
        screen.selectAvatar(0)
        compare(screen.profilePicture, "none")
        verify(!Qt.colorEqual(screen.avatarPreview.color, MissionTheme.success))
        screen.destroy()
    }

    // ── Action signals fire from the right controls ────────────────
    function test_actionSignals() {
        var screen = createScreen()
        fillCompleteForm(screen)
        var spies = []
        var spyNames = ["continueRequested", "backRequested", "retryRequested"]
        for (var i = 0; i < spyNames.length; ++i) {
            var spy = Qt.createQmlObject(
                "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: '" +
                spyNames[i] + "' }", screen, "userSpy" + i)
            spy.target = screen
            spies.push(spy)
        }

        screen.continueButton.clicked()
        compare(spies[0].count, 1)

        screen.backButton.clicked()
        compare(spies[1].count, 1)

        screen.screenState = "error"
        screen.retryButton.clicked()
        compare(spies[2].count, 1)

        screen.destroy()
    }

    // ── Required state transitions ─────────────────────────────────
    function test_stateTransitions() {
        var screen = createScreen()
        fillCompleteForm(screen)
        // empty (default): no banner, Continue enabled (form complete)
        verify(!screen.loadingIndicator.visible)
        verify(!screen.errorBanner.visible)
        verify(!screen.successBanner.visible)
        verify(!screen.offlineBanner.visible)
        verify(screen.continueButton.enabled)

        // loading: progress shown, Continue disabled
        screen.screenState = "loading"
        verify(screen.loadingIndicator.visible)
        verify(!screen.errorBanner.visible)
        verify(!screen.continueButton.enabled)

        // error: error banner + Retry, Continue disabled
        screen.screenState = "error"
        verify(screen.errorBanner.visible)
        verify(!screen.loadingIndicator.visible)
        verify(!screen.continueButton.enabled)

        // success: success banner, Continue enabled
        screen.screenState = "success"
        verify(screen.successBanner.visible)
        verify(!screen.errorBanner.visible)
        verify(screen.continueButton.enabled)

        // offline: informational banner, Continue enabled
        screen.screenState = "offline"
        verify(screen.offlineBanner.visible)
        verify(screen.continueButton.enabled)

        // back to empty clears all banners
        screen.screenState = "empty"
        verify(!screen.loadingIndicator.visible)
        verify(!screen.errorBanner.visible)
        verify(!screen.successBanner.visible)
        verify(!screen.offlineBanner.visible)

        screen.destroy()
    }

    // ── State banners must render (not collapse to 0 height) ───────
    // Regression guard for the banner-height bug class found in
    // MOS-INS-001/002/003: the error/success/offline banners must have
    // positive rendered height whenever their state is active.
    function test_stateBannersRender() {
        var screen = createScreen()

        screen.screenState = "error"
        verify(screen.errorBanner.visible)
        verify(screen.errorBanner.height > 0,
               "error banner must render with positive height (banner-height bug regression)")

        screen.screenState = "success"
        verify(screen.successBanner.visible)
        verify(screen.successBanner.height > 0,
               "success banner must render with positive height (banner-height bug regression)")

        screen.screenState = "offline"
        verify(screen.offlineBanner.visible)
        verify(screen.offlineBanner.height > 0,
               "offline banner must render with positive height (banner-height bug regression)")

        screen.screenState = "empty"
        screen.destroy()
    }

    // ── Continue must not silently advance while loading/error ─────
    function test_continueBlockedWhileLoading() {
        var screen = createScreen()
        fillCompleteForm(screen)
        wait(100) // let the hosted window activate so key events reach it
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'continueRequested' }",
            screen, "userContSpy")
        spy.target = screen

        // Loading: Continue disabled → no signal from keyboard input
        screen.screenState = "loading"
        verify(!screen.continueButton.enabled)
        screen.continueButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spy.count, 0)

        // Error: Continue disabled → no signal
        screen.screenState = "error"
        verify(!screen.continueButton.enabled)
        screen.continueButton.forceActiveFocus()
        keyClick(Qt.Key_Return)
        compare(spy.count, 0)

        // Empty + complete form: Continue enabled → keyboard advances
        screen.screenState = "empty"
        verify(screen.continueButton.enabled)
        screen.continueButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spy.count, 1)

        screen.destroy()
    }

    // ── Keyboard focus reaches all actionable controls ─────────────
    // The editable fields, switches, avatar chips, Back and Continue
    // must all be reachable through the Tab focus chain. The form is
    // filled first so Continue is enabled and therefore focusable
    // (disabled controls are not in the focus chain).
    function test_keyboardFocus() {
        var screen = createScreen()
        fillCompleteForm(screen)
        wait(100) // let the hosted window activate so Tab reaches the controls
        var hostWindow = _hostWindows[_hostWindows.length - 1]
        var found = {}

        // Walk the whole focus chain with Tab (the chain wraps, so 100
        // presses cover every control).
        for (var tab = 0; tab < 100; ++tab) {
            keyClick(Qt.Key_Tab)
            var focusItem = hostWindow.activeFocusItem
            if (focusItem && focusItem.objectName)
                found[focusItem.objectName] = true
        }

        verify(found["accountDisplayName"], "focus must reach the display name field")
        verify(found["accountUsername"], "focus must reach the username field")
        verify(found["accountComputerName"], "focus must reach the computer name field")
        verify(found["accountPassword"], "focus must reach the password field")
        verify(found["accountPasswordConfirm"], "focus must reach the password confirmation field")
        verify(found["accountAutoLogin"], "focus must reach the automatic login switch")
        verify(found["accountSleepPassword"], "focus must reach the require-password-after-sleep switch")
        verify(found["accountAvatarItem2"], "focus must reach an avatar preset chip")
        verify(found["accountBack"], "focus must reach accountBack")
        verify(found["accountContinue"], "focus must reach accountContinue")

        screen.destroy()
    }

    // ── Escape navigates back ──────────────────────────────────────
    function test_escapeNavigatesBack() {
        var screen = createScreen()
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'backRequested' }",
            screen, "userEscSpy")
        spy.target = screen

        // Warm up the hosted window (first key event is consumed by
        // window activation on this build). Focus lands in an editable
        // field; the field does not consume Escape, so it propagates to
        // the root and navigates back.
        screen.displayNameField.forceActiveFocus()
        keyClick(Qt.Key_W)
        screen.displayNameField.forceActiveFocus()
        keyClick(Qt.Key_Escape)
        compare(spy.count, 1)

        screen.destroy()
    }

    // ── Responsive reflow (docs/design/14_RESPONSIVE_RULES.md) ────
    function test_responsiveLayout() {
        // Wide (≥760): help panel visible, wide layout active
        var wide = createScreenAt(1024, 768)
        verify(wide.wideLayout)
        verify(!wide.compactLayout)
        verify(wide.helpPanel.visible)
        wide.destroy()

        // Compact (<640): help panel collapses, compact layout active
        var compact = createScreenAt(480, 768)
        verify(!compact.wideLayout)
        verify(compact.compactLayout)
        verify(!compact.helpPanel.visible)
        compact.destroy()
    }

    // ── MissionPage / MissionWindow integration ────────────────────
    function test_missionPageIntegration() {
        var page = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionPage { pageTitle: 'Installer'; UserAccount { objectName: 'userInPage' } }",
            root, "userInPage")
        verify(page !== null)
        verify(page.data.length > 0)
        page.destroy()
    }

    function test_missionWindowIntegration() {
        var screen = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionWindow { width: 1024; height: 768; UserAccount { objectName: 'userInWindow' } }",
            root, "userInWindow")
        verify(screen !== null)
        verify(screen.width > 0)
        screen.destroy()
    }

    // ── Reduced motion does not break rendering ────────────────────
    function test_reducedMotion() {
        var screen = createScreen()
        screen.reducedMotion = true
        screen.screenState = "loading"
        verify(screen.loadingIndicator.visible)
        verify(!screen.continueButton.enabled)
        fillCompleteForm(screen)
        screen.screenState = "empty"
        verify(screen.continueButton.enabled)
        // Toggling + avatar selection still work with reduced motion
        screen.setAutomaticLogin(true)
        compare(screen.automaticLogin, true)
        screen.selectAvatar(1)
        compare(screen.selectedAvatarIndex, 1)
        compare(screen.profilePicture, "primary")
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
