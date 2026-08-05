// Mission OS — Installer Keyboard Selection (MOS-INS-003) QtTest suite
//
// Runtime validation of the Keyboard Selection screen. Follows the
// foundation smoke-test pattern (tests/tst_smoke.qml), the MOS-INS-001
// InstallerWelcome suite (tests/tst_installer_welcome.qml) and the
// MOS-INS-002 Language suite (tests/tst_language.qml) per
// docs/engineering/TESTING_STRATEGY.md (QML → Qt Test / qmltestrunner).
//
// Coverage:
//   - screen loads without QML errors (token singletons resolve)
//   - MissionTheme works; light/dark rendering bindings re-evaluate
//   - full keyboard layout + platform preset catalogs are exposed
//   - US layout + Linux preset preselected without emitting on load
//   - every keyboard layout emits its code (us/uk/de/fr/ja/in/custom)
//   - every platform preset emits its preset (linux/windows/macos)
//   - keyboard test/capture area captures typing; Clear + Escape clear it
//   - Escape precedence: focused test area clears (no backRequested);
//     elsewhere root Escape → backRequested
//   - required signals fire from the right controls (continue/back/retry)
//   - required state transitions (empty/loading/error/success/offline)
//   - Continue never advances while loading/error
//   - keyboard focus reaches actionable controls in logical order;
//     arrows move the list, Enter/Space activate, chips select
//   - MissionPage / MissionWindow integration introduces no runtime errors
//   - reduced motion does not break rendering
//
// Run via qmltestrunner (see CMakeLists.txt CTest registration):
//   qmltestrunner -import <build>/src/libraries/ui/qml \
//                 -input src/libraries/ui/tests/tst_keyboard.qml
//
// Exit code: 0 = all checks passed; non-zero = failure (CI gate).

import QtQuick
import QtTest
import org.mission.ui 1.0

TestCase {
    id: root
    name: "KeyboardSelection"

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
                     "    KeyboardSelection { id: screen; width: " + width + "; height: " + height + "; " +
                     (extra || "") + " }\n" +
                     "}"
        var host = Qt.createQmlObject(source, root, "kbdHost")
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
        verify(screen.testField !== null)
        // The full layout + preset catalogs must be populated (MOS-INS-003)
        compare(screen.layouts.length, 7)
        compare(screen.presets.length, 3)
        // US + Linux (Default) are the default selections on load
        compare(screen.currentLayoutLabel, "US")
        compare(screen.currentLayoutCode, "us")
        compare(screen.currentPresetLabel, "Linux (Default)")
        compare(screen.currentPresetCode, "linux")
        // Step context: Keyboard is installer step 3 of 12
        compare(screen.step, 3)
        compare(screen.totalSteps, 17)
        screen.destroy()
    }

    // ── Loading must not emit spurious layout/preset signals ───────
    // Regression guard: preselect-on-load must stay non-emitting for
    // BOTH the layout and the preset (matches the 002 contract).
    function test_noSignalsOnLoad() {
        var source = "import QtQuick\n" +
                     "import QtTest\n" +
                     "import org.mission.ui 1.0\n" +
                     "Window {\n" +
                     "    width: 1024; height: 768; visible: true\n" +
                     "    property alias screen: screen\n" +
                     "    property alias spyLayout: spyLayout\n" +
                     "    property alias spyPreset: spyPreset\n" +
                     "    KeyboardSelection { id: screen; width: 1024; height: 768\n" +
                     "        SignalSpy { id: spyLayout; signalName: 'keyboardLayoutChangeRequested'; target: screen }\n" +
                     "        SignalSpy { id: spyPreset; signalName: 'platformPresetChangeRequested'; target: screen }\n" +
                     "    }\n" +
                     "}\n"
        var host = Qt.createQmlObject(source, root, "kbdLoadHost")
        _hostWindows.push(host)
        compare(host.spyLayout.count, 0)
        compare(host.spyPreset.count, 0)
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
        verify(screen.testField !== null)
        verify(screen.clearTestButton !== null)
        verify(screen.continueButton.visible)
        verify(screen.continueButton.enabled)
        // Back is enabled on step 3 (Keyboard is the third installer step)
        verify(screen.backButton.enabled)
        // Continue is primary variant; Back is secondary
        compare(screen.continueButton.variant, MissionButton.Variant.Primary)
        compare(screen.backButton.variant, MissionButton.Variant.Secondary)
        screen.destroy()
    }

    // ── Every keyboard layout emits its code ───────────────────────
    function test_layoutSelection() {
        var screen = createScreen()
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'keyboardLayoutChangeRequested' }",
            screen, "kbdLayoutSpy")
        spy.target = screen

        // Walk every layout entry: selection + emitted code must match
        for (var i = 0; i < screen.layouts.length; ++i) {
            screen.selectLayout(i)
            compare(screen.currentLayoutCode, screen.layouts[i].code)
            compare(screen.currentLayoutLabel, screen.layouts[i].label)
            compare(spy.count, i + 1)
            compare(spy.signalArguments[spy.count - 1][0], screen.layouts[i].code)
        }

        // Out of range is ignored
        screen.selectLayout(999)
        compare(spy.count, screen.layouts.length)

        screen.destroy()
    }

    // ── Every platform preset emits its preset ─────────────────────
    function test_presetSelection() {
        var screen = createScreen()
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'platformPresetChangeRequested' }",
            screen, "kbdPresetSpy")
        spy.target = screen

        // Walk every preset entry: selection + emitted preset must match
        for (var i = 0; i < screen.presets.length; ++i) {
            screen.selectPreset(i)
            compare(screen.currentPresetCode, screen.presets[i].code)
            compare(screen.currentPresetLabel, screen.presets[i].label)
            compare(spy.count, i + 1)
            compare(spy.signalArguments[spy.count - 1][0], screen.presets[i].code)
        }

        // Out of range is ignored
        screen.selectPreset(999)
        compare(spy.count, screen.presets.length)

        screen.destroy()
    }

    // ── Keyboard test/capture area ─────────────────────────────────
    function test_keyboardCapture() {
        var screen = createScreen()
        wait(100) // let the hosted window activate so key events reach it

        screen.testField.forceActiveFocus()
        verify(screen.testField.activeFocus)
        // keyClick sends the key without Shift on this platform, so the
        // captured text is lowercase (case is a layout concern, not a
        // capture-area concern).
        keyClick(Qt.Key_H)
        keyClick(Qt.Key_E)
        keyClick(Qt.Key_L)
        keyClick(Qt.Key_L)
        keyClick(Qt.Key_O)
        compare(screen.testField.text, "hello")

        // Clear button clears the capture area
        screen.clearTestButton.clicked()
        compare(screen.testField.text, "")

        // Capture again after clearing
        keyClick(Qt.Key_A)
        compare(screen.testField.text, "a")

        screen.destroy()
    }

    // ── Escape precedence: test area clears, root navigates back ──
    function test_escapeBehavior() {
        var screen = createScreen()
        wait(100)
        var backSpy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'backRequested' }",
            screen, "kbdBackSpy")
        backSpy.target = screen

        // While the test area is focused, Escape clears it and must NOT
        // bubble up to the root backRequested (parent-vs-child rule).
        screen.testField.forceActiveFocus()
        screen.testField.text = "abc"
        keyClick(Qt.Key_Escape)
        compare(screen.testField.text, "")
        compare(backSpy.count, 0)

        // Elsewhere (action bar focus), root Escape → backRequested.
        screen.continueButton.forceActiveFocus()
        keyClick(Qt.Key_Escape)
        compare(backSpy.count, 1)

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
                spyNames[i] + "' }", screen, "kbdSpy" + i)
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

    // ── Continue must not silently advance while loading/error ─────
    function test_continueBlockedWhileLoading() {
        var screen = createScreen()
        wait(100) // let the hosted window activate so key events reach it
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'continueRequested' }",
            screen, "kbdContSpy")
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
        var controls = ["keyboardItem0", "keyboardTest", "keyboardClear",
                        "presetItem0", "presetItem1", "presetItem2",
                        "keyboardBack", "keyboardContinue"]
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
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'keyboardLayoutChangeRequested' }",
            screen, "kbdListSpy")
        spy.target = screen

        screen.layoutList.forceActiveFocus()
        verify(screen.layoutList.activeFocus)
        // Move from US (0) to UK (1) with Down, then select
        keyClick(Qt.Key_Down)
        compare(screen.layoutList.currentIndex, 1)
        keyClick(Qt.Key_Return)
        compare(screen.currentLayoutLabel, "UK")
        compare(screen.currentLayoutCode, "uk")
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "uk")

        // Space also selects (German → de)
        keyClick(Qt.Key_Down)
        keyClick(Qt.Key_Space)
        compare(screen.currentLayoutLabel, "German")
        compare(screen.currentLayoutCode, "de")

        screen.destroy()
    }

    // ── Preset chips select via keyboard (Return/Space) ────────────
    function test_presetChipKeyboardSelection() {
        var screen = createScreen()
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'platformPresetChangeRequested' }",
            screen, "kbdChipSpy")
        spy.target = screen

        // Focus chip 1 (Windows) and activate with Return
        screen.presetRows.itemAt(1).forceActiveFocus()
        verify(screen.presetRows.itemAt(1).activeFocus)
        keyClick(Qt.Key_Return)
        compare(screen.currentPresetLabel, "Windows")
        compare(screen.currentPresetCode, "windows")
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "windows")

        // Focus chip 2 (macOS) and activate with Space
        screen.presetRows.itemAt(2).forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(screen.currentPresetLabel, "macOS")
        compare(screen.currentPresetCode, "macos")
        compare(spy.count, 2)

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
            "import org.mission.ui 1.0; MissionPage { pageTitle: 'Installer'; KeyboardSelection { objectName: 'kbdInPage' } }",
            root, "kbdInPage")
        verify(page !== null)
        verify(page.data.length > 0)
        page.destroy()
    }

    function test_missionWindowIntegration() {
        var screen = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionWindow { width: 1024; height: 768; KeyboardSelection { objectName: 'kbdInWindow' } }",
            root, "kbdInWindow")
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
