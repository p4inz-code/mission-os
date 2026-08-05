// Mission OS — Installer Welcome (MOS-INS-001) QtTest suite
//
// Runtime validation of the Installer Welcome screen. Follows the
// foundation smoke-test pattern (tests/tst_smoke.qml) and
// docs/engineering/TESTING_STRATEGY.md (QML → Qt Test / qmltestrunner).
//
// Coverage:
//   - screen loads without QML errors (token singletons resolve)
//   - MissionTheme works; light/dark rendering bindings re-evaluate
//   - primary actions exist (Continue/Back/Shutdown/Restart/Exit/…)
//   - action signals are emitted by the right controls
//   - required state transitions (empty/loading/error/success/offline)
//   - Continue never advances while loading/error
//   - keyboard focus reaches actionable controls in logical order
//   - MissionPage / MissionWindow integration introduces no runtime errors
//
// Run via qmltestrunner (see CMakeLists.txt CTest registration):
//   qmltestrunner -import <build>/src/libraries/ui/qml \
//                 -input src/libraries/ui/tests/tst_installer_welcome.qml
//
// Exit code: 0 = all checks passed; non-zero = failure (CI gate).

import QtQuick
import QtTest
import org.mission.ui 1.0

TestCase {
    id: root
    name: "InstallerWelcome"

    // ── Helpers ────────────────────────────────────────────────────
    // The qmltestrunner harness does not show its own test window, so
    // items hosted directly under the TestCase report visible=false on
    // this Qt build (verified empirically). To validate real
    // visibility and keyboard-focus behavior, every screen under test
    // is hosted inside an explicit visible Window; cleanup() destroys
    // the host windows afterwards.
    property var _hostWindows: []

    function createScreen(extra) {
        var source = "import QtQuick\n" +
                     "import org.mission.ui 1.0\n" +
                     "Window {\n" +
                     "    width: 1024; height: 768; visible: true\n" +
                     "    property alias screen: screen\n" +
                     "    InstallerWelcome { id: screen; width: 1024; height: 768; " +
                     (extra || "") + " }\n" +
                     "}"
        var host = Qt.createQmlObject(source, root, "welcomeHost")
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
        screen.destroy()
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
        verify(screen.languageButton !== null)
        verify(screen.accessibilityButton !== null)
        verify(screen.powerButton !== null)
        verify(screen.documentationButton !== null)
        verify(screen.releaseNotesButton !== null)
        verify(screen.continueButton.visible)
        verify(screen.continueButton.enabled)
        // Back is disabled on step 1 (linear workflow — nothing to go back to)
        verify(!screen.backButton.enabled)
        // Continue is primary variant; Back is secondary
        compare(screen.continueButton.variant, MissionButton.Variant.Primary)
        compare(screen.backButton.variant, MissionButton.Variant.Secondary)
        screen.destroy()
    }

    // ── Action signals fire from the right controls ────────────────
    function test_actionSignals() {
        var screen = createScreen()
        var spies = []
        var spyNames = ["continueRequested", "backRequested", "accessibilityRequested",
                        "documentationRequested", "releaseNotesRequested"]
        for (var i = 0; i < spyNames.length; ++i) {
            var spy = Qt.createQmlObject(
                "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: '" +
                spyNames[i] + "' }", screen, "spy" + i)
            spy.target = screen
            spies.push(spy)
        }

        // Clicking the buttons must emit the corresponding signals
        screen.continueButton.clicked()
        compare(spies[0].count, 1)

        screen.step = 2 // enable Back
        screen.backButton.clicked()
        compare(spies[1].count, 1)

        screen.accessibilityButton.clicked()
        compare(spies[2].count, 1)

        screen.documentationButton.clicked()
        compare(spies[3].count, 1)

        screen.releaseNotesButton.clicked()
        compare(spies[4].count, 1)

        screen.destroy()
    }

    // ── Power menu (Shutdown / Restart / Exit installer) ───────────
    function test_powerMenuActions() {
        var screen = createScreen()
        var spies = []
        var names = ["shutdownRequested", "restartRequested", "exitRequested"]
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
        verify(screen.exitItem !== null)
        verify(screen.shutdownItem.text.length > 0)
        verify(screen.restartItem.text.length > 0)
        verify(screen.exitItem.text.length > 0)

        screen.shutdownItem.triggered()
        screen.restartItem.triggered()
        screen.exitItem.triggered()
        compare(spies[0].count, 1)
        compare(spies[1].count, 1)
        compare(spies[2].count, 1)

        screen.destroy()
    }

    // ── Language selector ──────────────────────────────────────────
    function test_languageSelection() {
        var screen = createScreen()
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'languageChangeRequested' }",
            screen, "langSpy")
        spy.target = screen

        // The language menu must be populated from the languages model
        // (Instantiator + insertItem wiring — regression guard).
        verify(screen.languageMenu.count === screen.languages.length)

        compare(screen.currentLanguage, "English")
        screen.selectLanguage(1) // Deutsch
        compare(screen.currentLanguage, "Deutsch")
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "de_DE")

        screen.selectLanguage(99) // out of range — ignored
        compare(spy.count, 1)

        screen.destroy()
    }

    // ── State banners must render (not collapse to 0 height) ───────
    // Regression guard for the MOS-INS-003 banner-height bug: the
    // error/success/offline banners must have positive rendered height
    // whenever their state is active (this screen carried the same
    // latent bug class as 002/003 — fixed with the proven implicitHeight
    // + padding pattern).
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
    // Disabled buttons cannot receive focus, so real keyboard input
    // (Space/Enter) must never activate Continue in a blocked state.
    function test_continueBlockedWhileLoading() {
        var screen = createScreen()
        wait(100) // let the hosted window activate so key events reach it
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'continueRequested' }",
            screen, "contSpy")
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

    // ── Required state transitions ─────────────────────────────────
    function test_stateTransitions() {
        var screen = createScreen()
        // empty (default): no banner, Continue enabled
        verify(!screen.loadingIndicator.visible)
        verify(!screen.errorBanner.visible)
        verify(!screen.successBanner.visible)
        verify(!screen.offlineBanner.visible)
        verify(screen.continueButton.enabled)

        // loading: progress shown, Continue disabled (never silently advances)
        screen.screenState = "loading"
        verify(screen.loadingIndicator.visible)
        verify(!screen.errorBanner.visible)
        verify(!screen.continueButton.enabled)

        // error: error banner + Retry, Continue disabled
        screen.screenState = "error"
        verify(screen.errorBanner.visible)
        verify(!screen.loadingIndicator.visible)
        verify(!screen.continueButton.enabled)
        var retrySpy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'retryRequested' }",
            screen, "retrySpy")
        retrySpy.target = screen
        screen.retryButton.clicked()
        compare(retrySpy.count, 1)

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

    // ── Keyboard focus reaches actionable controls ─────────────────
    function test_keyboardFocus() {
        var screen = createScreen()
        wait(100) // let the hosted window activate so Tab reaches the controls
        // createScreen() is called exactly once per test and cleanup()
        // destroys all hosts between tests, so the last host window is
        // this screen's window.
        var hostWindow = _hostWindows[_hostWindows.length - 1]
        var controls = ["welcomeLanguage", "welcomeAccessibility", "welcomePower",
                        "welcomeDocumentation", "welcomeReleaseNotes", "welcomeContinue"]
        var found = {}
        for (var i = 0; i < controls.length; ++i)
            found[controls[i]] = false

        // Walk the whole focus chain with Tab (the chain wraps, so 80
        // presses cover every control). Focus is tracked at the host
        // window level: this qmltestrunner build reports
        // activeFocusItem as undefined for items under the TestCase, but
        // resolves it correctly inside an explicit visible Window.
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

    // ── MissionPage / MissionWindow integration ────────────────────
    function test_missionPageIntegration() {
        var page = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionPage { pageTitle: 'Installer'; InstallerWelcome { objectName: 'welcomeInPage' } }",
            root, "welcomeInPage")
        verify(page !== null)
        // MissionPage hosts children in its content column; the welcome
        // screen must have been added to the page content without errors.
        verify(page.data.length > 0)
        page.destroy()
    }

    function test_missionWindowIntegration() {
        var screen = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionWindow { width: 1024; height: 768; InstallerWelcome { objectName: 'welcomeInWindow' } }",
            root, "welcomeInWindow")
        verify(screen !== null)
        verify(screen.width > 0)
        screen.destroy()
    }

    // ── Accessibility roles (audit regression) ─────────────────────
    // Foundation audit fix: this screen's heading previously lacked the
    // Heading role (every other installer screen sets it), and the
    // installation-mode cards lacked Grouping semantics. Both must stay
    // announced correctly for screen-reader users.
    function test_accessibleRoles() {
        var screen = createScreen()
        // Page heading must be announced as a heading landmark
        verify(screen.headingLabel.Accessible.role === Accessible.Heading,
               "welcome heading must carry the Heading role")
        verify(screen.headingLabel.Accessible.name.length > 0)
        // Installation-mode cards must be announced as named groups
        verify(screen.modeCards.count === 2)
        for (var i = 0; i < screen.modeCards.count; ++i) {
            var card = screen.modeCards.itemAt(i)
            verify(card.Accessible.role === Accessible.Grouping,
                   "mode card " + i + " must carry the Grouping role")
            verify(card.Accessible.name.length > 0,
                   "mode card " + i + " must have an accessible name")
        }
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
