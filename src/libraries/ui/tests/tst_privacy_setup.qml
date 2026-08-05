// Mission OS — Installer Privacy Setup (MOS-INS-005) QtTest suite
//
// Runtime validation of the Privacy Setup screen. Follows the
// foundation smoke-test pattern (tests/tst_smoke.qml), the MOS-INS-001
// InstallerWelcome suite (tests/tst_installer_welcome.qml), the
// MOS-INS-002 Language suite (tests/tst_language.qml), the MOS-INS-003
// Keyboard suite (tests/tst_keyboard.qml) and the MOS-INS-004 Network
// suite (tests/tst_network.qml) per docs/engineering/TESTING_STRATEGY.md
// (QML → Qt Test / qmltestrunner).
//
// Coverage:
//   - screen loads without QML errors (token singletons resolve)
//   - default values: all six privacy options OFF (privacy-by-default)
//   - no spurious privacyChangeRequested signal on load
//   - full privacy-option catalog exposed with the four explanations
//     per option (what data, why, whether optional, how to change later)
//   - every privacy option toggles and emits its code + enabled state
//   - explanatory content is present on every option
//   - MissionTheme works; light/dark rendering bindings re-evaluate
//   - primary actions exist (Continue/Back/Retry)
//   - required state transitions (empty/loading/error/success/offline)
//   - state banners render with positive height (banner-height regression)
//   - Continue never advances while loading/error
//   - keyboard focus reaches actionable controls in logical order;
//     Space toggles the focused switch, Return/click too
//   - Escape navigates back
//   - responsive compact layout (help panel collapses)
//   - reduced motion does not break rendering
//   - MissionPage / MissionWindow integration introduces no runtime errors
//
// Run via qmltestrunner (see CMakeLists.txt CTest registration):
//   qmltestrunner -import <build>/src/libraries/ui/qml \
//                 -input src/libraries/ui/tests/tst_privacy_setup.qml
//
// Exit code: 0 = all checks passed; non-zero = failure (CI gate).

import QtQuick
import QtTest
import org.mission.ui 1.0

TestCase {
    id: root
    name: "PrivacySetup"

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
                     "    PrivacySetup { id: screen; width: " + width + "; height: " + height + "; " +
                     (extra || "") + " }\n" +
                     "}"
        var host = Qt.createQmlObject(source, root, "privHost")
        _hostWindows.push(host)
        return host.screen
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
        // The full privacy catalog must be populated (MOS-INS-005)
        compare(screen.privacyOptions.length, 6)
        // Default values: privacy-by-default — nothing enabled on load
        compare(screen.enabledCount, 0)
        // Step context: Privacy is installer step 5 of 12
        compare(screen.step, 5)
        compare(screen.totalSteps, 17)
        screen.destroy()
    }

    // ── Defaults must not emit spurious privacy signals ────────────
    // Regression guard: all options are OFF by default and no toggle
    // happens during initialization, so no change signal may fire on
    // load (same contract as 002/003/004).
    function test_noSignalsOnLoad() {
        var source = "import QtQuick\n" +
                     "import QtTest\n" +
                     "import org.mission.ui 1.0\n" +
                     "Window {\n" +
                     "    width: 1024; height: 768; visible: true\n" +
                     "    property alias screen: screen\n" +
                     "    property alias spy: spy\n" +
                     "    PrivacySetup { id: screen; width: 1024; height: 768\n" +
                     "        SignalSpy { id: spy; signalName: 'privacyChangeRequested'; target: screen }\n" +
                     "    }\n" +
                     "}\n"
        var host = Qt.createQmlObject(source, root, "privLoadHost")
        _hostWindows.push(host)
        compare(host.spy.count, 0)
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

    // ── Primary actions exist ──────────────────────────────────────
    function test_primaryActionsExist() {
        var screen = createScreen()
        verify(screen.continueButton !== null)
        verify(screen.backButton !== null)
        verify(screen.privacyRows.count === 6)
        verify(screen.continueButton.visible)
        verify(screen.continueButton.enabled)
        // Back is enabled on step 5 (Privacy is the fifth installer step)
        verify(screen.backButton.enabled)
        // Continue is primary variant; Back is secondary
        compare(screen.continueButton.variant, MissionButton.Variant.Primary)
        compare(screen.backButton.variant, MissionButton.Variant.Secondary)
        screen.destroy()
    }

    // ── Privacy option catalog: codes + required explanations ───────
    function test_privacyCatalog() {
        var screen = createScreen()
        var expectedCodes = ["crash", "diagnostics", "updates", "location",
                             "search", "permissions"]
        var expectedLabels = ["Crash reporting", "Anonymous diagnostics",
                              "Update checking", "Location access",
                              "Search providers", "Application permissions"]
        compare(screen.privacyOptions.length, expectedCodes.length)
        for (var i = 0; i < screen.privacyOptions.length; ++i) {
            compare(screen.privacyOptions[i].code, expectedCodes[i])
            compare(screen.privacyOptions[i].label, expectedLabels[i])
        }
        screen.destroy()
    }

    // ── Explanatory content: every option communicates what data,
    //    why it is used, whether it is optional, and how to change
    //    it later (reference Screen 12). ────────────────────────────
    function test_explanatoryContent() {
        var screen = createScreen()
        for (var i = 0; i < screen.privacyOptions.length; ++i) {
            var opt = screen.privacyOptions[i]
            verify(opt.what.length > 20, "option " + i + " must explain what data/access is involved")
            verify(opt.why.length > 10, "option " + i + " must explain why it is used")
            verify(opt.optional.length > 10, "option " + i + " must state whether it is optional")
            verify(opt.change.length > 15, "option " + i + " must explain how to change it later")
        }
        screen.destroy()
    }

    // ── Every privacy option toggles and emits code + enabled ──────
    function test_optionToggleSignals() {
        var screen = createScreen()
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'privacyChangeRequested' }",
            screen, "privSpy")
        spy.target = screen

        // Enable each option in turn via the host API
        for (var i = 0; i < screen.privacyOptions.length; ++i) {
            screen.setOptionEnabled(i, true)
            compare(screen.isOptionEnabled(i), true)
            compare(screen.enabledCount, i + 1)
            compare(spy.count, i + 1)
            compare(spy.signalArguments[spy.count - 1][0], screen.privacyOptions[i].code)
            compare(spy.signalArguments[spy.count - 1][1], true)
        }

        // Disable each option again
        for (var j = 0; j < screen.privacyOptions.length; ++j) {
            screen.setOptionEnabled(j, false)
            compare(screen.isOptionEnabled(j), false)
            compare(screen.enabledCount, screen.privacyOptions.length - j - 1)
            compare(spy.signalArguments[spy.count - 1][0], screen.privacyOptions[j].code)
            compare(spy.signalArguments[spy.count - 1][1], false)
        }

        // Out of range is ignored
        screen.setOptionEnabled(999, true)
        compare(spy.count, screen.privacyOptions.length * 2)

        screen.destroy()
    }

    // ── Toggling the switch control directly emits the signal ──────
    function test_switchToggle() {
        var screen = createScreen()
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'privacyChangeRequested' }",
            screen, "privSwitchSpy")
        spy.target = screen

        // Click-toggle the first switch (crash reporting)
        var first = screen.privacyRows.itemAt(0)
        verify(first !== null)
        first.switchControl.checked = true
        compare(screen.enabledCount, 1)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "crash")
        compare(spy.signalArguments[0][1], true)

        // Toggle it back off
        first.switchControl.checked = false
        compare(screen.enabledCount, 0)
        compare(spy.count, 2)
        compare(spy.signalArguments[1][1], false)

        screen.destroy()
    }

    // ── Action signals fire from the right controls ────────────────
    function test_actionSignals() {
        var screen = createScreen()
        var spies = []
        var spyNames = ["continueRequested", "backRequested", "retryRequested"]
        for (var i = 0; i < spyNames.length; ++i) {
            var spy = Qt.createQmlObject(
                "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: '" +
                spyNames[i] + "' }", screen, "privSpy" + i)
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
        // empty (default): no banner, Continue enabled
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
        wait(100) // let the hosted window activate so key events reach it
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'continueRequested' }",
            screen, "privContSpy")
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

        // Empty: Continue enabled → keyboard input advances
        screen.screenState = "empty"
        verify(screen.continueButton.enabled)
        screen.continueButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spy.count, 1)

        screen.destroy()
    }

    // ── Keyboard focus reaches actionable controls ─────────────────
    function test_keyboardFocus() {
        var screen = createScreen()
        wait(100) // let the hosted window activate so Tab reaches the controls
        var hostWindow = _hostWindows[_hostWindows.length - 1]
        var controls = ["privacyToggle0", "privacyToggle1", "privacyToggle2",
                        "privacyToggle3", "privacyToggle4", "privacyToggle5",
                        "privacyBack", "privacyContinue"]
        var found = {}
        for (var i = 0; i < controls.length; ++i)
            found[controls[i]] = false

        // Walk the whole focus chain with Tab (the chain wraps, so 80
        // presses cover every control).
        for (var tab = 0; tab < 80; ++tab) {
            keyClick(Qt.Key_Tab)
            var focusItem = hostWindow.activeFocusItem
            if (focusItem && focusItem.objectName)
                found[focusItem.objectName] = true
        }

        for (var c = 0; c < controls.length; ++c)
            verify(found[controls[c]], "focus must reach " + controls[c])

        screen.destroy()
    }

    // ── Space toggles the focused switch ───────────────────────────
    function test_switchKeyboardToggle() {
        var screen = createScreen()
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'privacyChangeRequested' }",
            screen, "privKbdSpy")
        spy.target = screen

        var first = screen.privacyRows.itemAt(0)
        // Warm up the hosted window: on this build the first key event
        // delivered to a freshly created window is consumed by window
        // activation, so focus and key delivery are only reliable after
        // one warm-up key (same mechanism the Continue-blocked and
        // keyboard-focus tests rely on implicitly).
        keyClick(Qt.Key_Tab)
        first.switchControl.forceActiveFocus()
        verify(first.switchControl.activeFocus)
        keyClick(Qt.Key_Space)
        compare(first.switchControl.checked, true)
        compare(screen.enabledCount, 1)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "crash")

        keyClick(Qt.Key_Space)
        compare(first.switchControl.checked, false)
        compare(screen.enabledCount, 0)
        compare(spy.count, 2)

        screen.destroy()
    }

    // ── Escape navigates back ──────────────────────────────────────
    function test_escapeNavigatesBack() {
        var screen = createScreen()
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'backRequested' }",
            screen, "privEscSpy")
        spy.target = screen

        // Warm up the hosted window before asserting the real Escape
        // behavior: the first key event on a fresh window is consumed by
        // window activation on this build (verified empirically), so an
        // extra key is sent first to absorb that activation. The warm-up
        // Space lands on Continue (fires continueRequested, never
        // backRequested), keeping the backRequested count clean.
        screen.continueButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        screen.continueButton.forceActiveFocus()
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
            "import org.mission.ui 1.0; MissionPage { pageTitle: 'Installer'; PrivacySetup { objectName: 'privInPage' } }",
            root, "privInPage")
        verify(page !== null)
        verify(page.data.length > 0)
        page.destroy()
    }

    function test_missionWindowIntegration() {
        var screen = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionWindow { width: 1024; height: 768; PrivacySetup { objectName: 'privInWindow' } }",
            root, "privInWindow")
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
        screen.screenState = "empty"
        verify(screen.continueButton.enabled)
        // Toggling still works with reduced motion
        screen.setOptionEnabled(0, true)
        compare(screen.enabledCount, 1)
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
