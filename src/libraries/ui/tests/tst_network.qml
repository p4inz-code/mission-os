// Mission OS — Installer Network Selection (MOS-INS-004) QtTest suite
//
// Runtime validation of the Network Selection screen. Follows the
// foundation smoke-test pattern (tests/tst_smoke.qml), the MOS-INS-001
// InstallerWelcome suite (tests/tst_installer_welcome.qml), the
// MOS-INS-002 Language suite (tests/tst_language.qml) and the
// MOS-INS-003 Keyboard suite (tests/tst_keyboard.qml) per
// docs/engineering/TESTING_STRATEGY.md (QML → Qt Test / qmltestrunner).
//
// Coverage:
//   - screen loads without QML errors (token singletons resolve)
//   - MissionTheme works; light/dark rendering bindings re-evaluate
//   - full connection-method catalog is exposed
//   - Offline installation preselected without emitting on load
//   - every connection method emits its code (offline/ethernet/wifi/
//     proxy/static/dhcp)
//   - required signals fire from the right controls (continue/back/retry)
//   - required state transitions (empty/loading/error/success/offline)
//   - Continue never advances while loading/error
//   - keyboard focus reaches actionable controls in logical order;
//     arrows move the list, Enter/Space activate
//   - MissionPage / MissionWindow integration introduces no runtime errors
//   - reduced motion does not break rendering
//
// Run via qmltestrunner (see CMakeLists.txt CTest registration):
//   qmltestrunner -import <build>/src/libraries/ui/qml \
//                 -input src/libraries/ui/tests/tst_network.qml
//
// Exit code: 0 = all checks passed; non-zero = failure (CI gate).

import QtQuick
import QtTest
import org.mission.ui 1.0

TestCase {
    id: root
    name: "NetworkSelection"

    // ── Helpers ────────────────────────────────────────────────────
    // Same hosted-window pattern as tst_language.qml: items hosted
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
                     "    NetworkSelection { id: screen; width: " + width + "; height: " + height + "; " +
                     (extra || "") + " }\n" +
                     "}"
        var host = Qt.createQmlObject(source, root, "netHost")
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
        // The full connection catalog must be populated (MOS-INS-004)
        compare(screen.connectionOptions.length, 6)
        // Offline installation is the default selection on load
        compare(screen.currentConnectionLabel, "Offline installation")
        compare(screen.currentConnectionCode, "offline")
        // Step context: Network is installer step 4 of 12
        compare(screen.step, 4)
        compare(screen.totalSteps, 17)
        screen.destroy()
    }

    // ── Loading must not emit spurious connection signals ──────────
    // Regression guard: preselect-on-load must stay non-emitting
    // (matches the 002/003 contract).
    function test_noSignalsOnLoad() {
        var source = "import QtQuick\n" +
                     "import QtTest\n" +
                     "import org.mission.ui 1.0\n" +
                     "Window {\n" +
                     "    width: 1024; height: 768; visible: true\n" +
                     "    property alias screen: screen\n" +
                     "    property alias spy: spy\n" +
                     "    NetworkSelection { id: screen; width: 1024; height: 768\n" +
                     "        SignalSpy { id: spy; signalName: 'connectionChangeRequested'; target: screen }\n" +
                     "    }\n" +
                     "}\n"
        var host = Qt.createQmlObject(source, root, "netLoadHost")
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
        verify(screen.connectionList !== null)
        verify(screen.continueButton.visible)
        verify(screen.continueButton.enabled)
        // Back is enabled on step 4 (Network is the fourth installer step)
        verify(screen.backButton.enabled)
        // Continue is primary variant; Back is secondary
        compare(screen.continueButton.variant, MissionButton.Variant.Primary)
        compare(screen.backButton.variant, MissionButton.Variant.Secondary)
        screen.destroy()
    }

    // ── Every connection method emits its code ─────────────────────
    function test_connectionSelection() {
        var screen = createScreen()
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'connectionChangeRequested' }",
            screen, "netSpy")
        spy.target = screen

        // Walk every connection entry: selection + emitted code must match
        for (var i = 0; i < screen.connectionOptions.length; ++i) {
            screen.selectConnection(i)
            compare(screen.currentConnectionCode, screen.connectionOptions[i].code)
            compare(screen.currentConnectionLabel, screen.connectionOptions[i].label)
            compare(spy.count, i + 1)
            compare(spy.signalArguments[spy.count - 1][0], screen.connectionOptions[i].code)
        }

        // Out of range is ignored
        screen.selectConnection(999)
        compare(spy.count, screen.connectionOptions.length)

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
                spyNames[i] + "' }", screen, "netSpy" + i)
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
    // Regression guard for the MOS-INS-003 banner-height bug: the
    // error/success/offline banners must have positive rendered height
    // whenever their state is active.
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
            screen, "netContSpy")
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
        var controls = ["networkItem0", "networkBack", "networkContinue"]
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

    // ── Arrow keys move the list; Enter/Space select ───────────────
    function test_listKeyboardSelection() {
        var screen = createScreen()
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'connectionChangeRequested' }",
            screen, "netListSpy")
        spy.target = screen

        screen.connectionList.forceActiveFocus()
        verify(screen.connectionList.activeFocus)
        // Move from Offline (0) to Ethernet (1) with Down, then select
        keyClick(Qt.Key_Down)
        compare(screen.connectionList.currentIndex, 1)
        keyClick(Qt.Key_Return)
        compare(screen.currentConnectionLabel, "Ethernet")
        compare(screen.currentConnectionCode, "ethernet")
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "ethernet")

        // Space also selects (Wi-Fi → wifi)
        keyClick(Qt.Key_Down)
        keyClick(Qt.Key_Space)
        compare(screen.currentConnectionLabel, "Wi-Fi")
        compare(screen.currentConnectionCode, "wifi")

        screen.destroy()
    }

    // ── Escape navigates back ──────────────────────────────────────
    function test_escapeNavigatesBack() {
        var screen = createScreen()
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'backRequested' }",
            screen, "netEscSpy")
        spy.target = screen

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
            "import org.mission.ui 1.0; MissionPage { pageTitle: 'Installer'; NetworkSelection { objectName: 'netInPage' } }",
            root, "netInPage")
        verify(page !== null)
        verify(page.data.length > 0)
        page.destroy()
    }

    function test_missionWindowIntegration() {
        var screen = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionWindow { width: 1024; height: 768; NetworkSelection { objectName: 'netInWindow' } }",
            root, "netInWindow")
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
