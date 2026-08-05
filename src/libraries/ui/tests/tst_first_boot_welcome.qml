// Mission OS — First Boot Welcome (MOS-INS-014) QtTest suite
//
// Runtime validation of the First Boot Welcome screen. Follows the
// foundation smoke-test pattern (tests/tst_smoke.qml) and the
// MOS-INS-001→013 Installer suites per docs/engineering/
// TESTING_STRATEGY.md (QML → Qt Test / qmltestrunner).
//
// Coverage (only behaviors required by the authoritative sources —
// reference § "Screen 16 — First Boot Welcome", § "First Boot
// Principles", registry MOS-INS-014):
//   - screen loads without QML errors (token singletons resolve)
//   - default state: step 14 of 17, the seven reference display items
//     exist (Welcome heading, Installed version read-back, Build
//     channel read-back, Quick introduction, Documentation link,
//     Release notes, Continue), Continue enabled (valid state), Back
//     enabled (step 14 > 1)
//   - the two read-back details match the reference exactly (Installed
//     version, Build channel) — no item may be invented or omitted
//   - no spurious action signals on load
//   - host wiring: version/buildType updates flow into the header and
//     the read-back rows (they can never drift apart)
//   - required signals fire from the right controls
//     (continue/back/documentation/release notes/retry)
//   - required state transitions (empty/loading/error/success/offline)
//   - Continue is blocked while loading/error (validation-before-continue)
//   - state banners render with positive height (banner-height regression)
//   - keyboard navigation: focus reaches Back, Continue, Documentation
//     and Release notes; the read-only detail rows are NOT Tab stops
//     (no keyboard trap); Shift+Tab wraps backward
//   - Space activates the buttons; Escape navigates back
//   - accessibility roles/names (heading, detail list + items, buttons)
//   - light/dark theme rendering
//   - responsive compact layout (help panel collapses)
//   - reduced motion does not break rendering
//   - MissionPage / MissionWindow integration introduces no runtime errors
//
// Run via qmltestrunner (see CMakeLists.txt CTest registration):
//   qmltestrunner -import <build>/src/libraries/ui/qml \
//                 -input src/libraries/ui/tests/tst_first_boot_welcome.qml
//
// Exit code: 0 = all checks passed; non-zero = failure (CI gate).

import QtQuick
import QtQuick.Controls
import QtTest
import org.mission.ui 1.0

TestCase {
    id: root
    name: "FirstBootWelcome"

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
                     "    FirstBootWelcome { id: screen; width: " + width +
                     "; height: " + height + "; " + (extra || "") + " }\n" +
                     "}"
        var host = Qt.createQmlObject(source, root, "fbwHost" + _hostWindows.length)
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
        // Step context: First Boot Welcome is installer step 14 of 17
        compare(screen.step, 14)
        compare(screen.totalSteps, 17)
        // The seven reference display items exist
        verify(screen.headingLabel.text.length > 0)          // 1 Welcome to Mission OS
        compare(screen.firstBootDetailCount, 2)              // 2-3 Installed version + Build channel
        verify(screen.introLabel.text.length > 0)            // 4 Quick introduction
        verify(screen.documentationButton.text.length > 0)   // 5 Documentation link
        verify(screen.releaseNotesButton.text.length > 0)    // 6 Release notes
        verify(screen.continueButton.text.length > 0)        // 7 Continue
        // Defaults: Continue enabled (valid state); Back enabled (step 14 > 1)
        verify(screen.continueButton.enabled)
        verify(screen.backButton.enabled)
        screen.destroy()
    }

    // ── The read-back details match the reference exactly ──────────
    // Reference § "Screen 16": "Installed version" and "Build channel".
    // No item may be invented or omitted.
    function test_detailsMatchReference() {
        var screen = createScreen()
        var expected = [
            { code: "version", label: "Installed version" },
            { code: "channel", label: "Build channel" }
        ]
        compare(screen.firstBootDetails.length, expected.length)
        for (var i = 0; i < expected.length; ++i) {
            compare(screen.firstBootDetails[i].code, expected[i].code, "detail " + i + " code")
            compare(screen.firstBootDetails[i].label, expected[i].label, "detail " + i + " label")
        }
        // getDetail() helper resolves every detail code
        verify(screen.getDetail("version") !== null)
        verify(screen.getDetail("channel") !== null)
        compare(screen.getDetail("nonexistent"), null)
        screen.destroy()
    }

    // ── Default / initial state ────────────────────────────────────
    function test_initialState() {
        var screen = createScreen()
        compare(screen.screenState, "empty")
        compare(screen.version, "0.1.0")
        compare(screen.buildType, "Nightly")
        // No state banner on load
        verify(!screen.loadingIndicator.visible)
        verify(!screen.errorBanner.visible)
        verify(!screen.successBanner.visible)
        verify(!screen.offlineBanner.visible)
        // Read-back rows render the default version/build channel
        var item0 = screen.detailList.itemAtIndex(0)
        var item1 = screen.detailList.itemAtIndex(1)
        verify(item0 !== null, "detail row 0 must be instantiated")
        verify(item1 !== null, "detail row 1 must be instantiated")
        compare(item0.valueLabel.text, "0.1.0")
        compare(item1.valueLabel.text, "Nightly")
        screen.destroy()
    }

    // ── Defaults must not emit spurious signals ────────────────────
    function test_noSignalsOnLoad() {
        var source = "import QtQuick\n" +
                     "import QtTest\n" +
                     "import org.mission.ui 1.0\n" +
                     "Window {\n" +
                     "    width: 1024; height: 768; visible: true\n" +
                     "    property alias screen: screen\n" +
                     "    property alias spyC: spyC\n" +
                     "    property alias spyB: spyB\n" +
                     "    property alias spyD: spyD\n" +
                     "    property alias spyR: spyR\n" +
                     "    FirstBootWelcome { id: screen; width: 1024; height: 768\n" +
                     "        SignalSpy { id: spyC; signalName: 'continueRequested'; target: screen }\n" +
                     "        SignalSpy { id: spyB; signalName: 'backRequested'; target: screen }\n" +
                     "        SignalSpy { id: spyD; signalName: 'documentationRequested'; target: screen }\n" +
                     "        SignalSpy { id: spyR; signalName: 'releaseNotesRequested'; target: screen }\n" +
                     "    }\n" +
                     "}\n"
        var host = Qt.createQmlObject(source, root, "fbwLoadHost")
        _hostWindows.push(host)
        compare(host.spyC.count, 0)
        compare(host.spyB.count, 0)
        compare(host.spyD.count, 0)
        compare(host.spyR.count, 0)
        host.destroy()
    }

    // ── Host wiring: version/buildType flow into header + read-back ─
    // The reference's "Installed version" and "Build channel" items are
    // host-fed; the header and the read-back rows share the same public
    // properties so they can never drift apart (established pattern).
    function test_hostWiring() {
        var screen = createScreen()
        screen.version = "0.2.0-rc1"
        screen.buildType = "Beta"
        compare(screen.version, "0.2.0-rc1")
        compare(screen.buildType, "Beta")
        wait(50) // let the read-back delegates re-evaluate
        var item0 = screen.detailList.itemAtIndex(0)
        var item1 = screen.detailList.itemAtIndex(1)
        verify(item0 !== null)
        verify(item1 !== null)
        compare(item0.valueLabel.text, "0.2.0-rc1")
        compare(item1.valueLabel.text, "Beta")
        screen.destroy()
    }

    // ── Action signals fire from the right controls ────────────────
    function test_actionSignals() {
        var screen = createScreen()
        var spies = []
        var spyNames = ["continueRequested", "backRequested", "documentationRequested",
                        "releaseNotesRequested", "retryRequested"]
        for (var i = 0; i < spyNames.length; ++i) {
            var spy = Qt.createQmlObject(
                "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: '" +
                spyNames[i] + "' }", screen, "fbwSpy" + i)
            spy.target = screen
            spies.push(spy)
        }

        screen.continueButton.clicked()
        compare(spies[0].count, 1)

        screen.backButton.clicked()
        compare(spies[1].count, 1)

        screen.documentationButton.clicked()
        compare(spies[2].count, 1)

        screen.releaseNotesButton.clicked()
        compare(spies[3].count, 1)

        screen.screenState = "error"
        screen.retryButton.clicked()
        compare(spies[4].count, 1)

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
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'continueRequested' }",
            screen, "fbwContSpy")
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

        // Empty: valid state → Continue enabled → keyboard advances
        screen.screenState = "empty"
        verify(screen.continueButton.enabled)
        screen.continueButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spy.count, 1)

        screen.destroy()
    }

    // ── Keyboard focus reaches the actionable controls ─────────────
    // The read-only detail rows are not Tab stops (no keyboard trap);
    // Back, Continue, Documentation and Release notes are reachable.
    function test_keyboardFocus() {
        var screen = createScreen()
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

        verify(found["firstbootBack"], "focus must reach firstbootBack")
        verify(found["firstbootContinue"], "focus must reach firstbootContinue")
        verify(found["firstbootDocumentation"], "focus must reach firstbootDocumentation")
        verify(found["firstbootReleaseNotes"], "focus must reach firstbootReleaseNotes")

        // Read-only detail rows must NOT be keyboard Tab stops.
        for (var row = 0; row < 2; ++row) {
            verify(!("firstbootDetailItem" + row in found),
                   "read-only detail row " + row + " must not be a Tab stop")
        }

        screen.destroy()
    }

    // ── Shift+Tab wraps backward through the focus chain ───────────
    function test_shiftTabWrapsBackward() {
        var screen = createScreen()
        wait(100)
        var hostWindow = _hostWindows[_hostWindows.length - 1]

        // Warm up the hosted window (first key event is consumed by
        // window activation on this build).
        screen.backButton.forceActiveFocus()
        keyClick(Qt.Key_W)

        // Focus chain wraps: Tab from Back eventually reaches Continue
        // (the primary action). Shift+Tab from Continue must wrap to the
        // previous control rather than getting stuck.
        screen.continueButton.forceActiveFocus()
        keyClick(Qt.Key_Backtab)
        var focusItem = hostWindow.activeFocusItem
        verify(focusItem !== null && focusItem.objectName.length > 0,
               "Shift+Tab from Continue must move focus, got: " +
               (focusItem ? focusItem.objectName : "none"))
        verify(focusItem.objectName !== "firstbootContinue",
               "Shift+Tab from Continue must wrap backward, got: " + focusItem.objectName)

        screen.destroy()
    }

    // ── Space activates the buttons ────────────────────────────────
    function test_spaceActivationOnButtons() {
        var screen = createScreen()
        wait(100)

        // Warm up the hosted window (first key event is consumed by
        // window activation on this build — the established pattern).
        screen.continueButton.forceActiveFocus()
        keyClick(Qt.Key_W)

        // Documentation via Space → documentationRequested
        var spyD = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'documentationRequested' }",
            screen, "fbwKeySpyD")
        spyD.target = screen
        screen.documentationButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spyD.count, 1)

        // Release notes via Space → releaseNotesRequested
        var spyR = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'releaseNotesRequested' }",
            screen, "fbwKeySpyR")
        spyR.target = screen
        screen.releaseNotesButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spyR.count, 1)

        // Back via Space → backRequested
        var spyB = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'backRequested' }",
            screen, "fbwKeySpyB")
        spyB.target = screen
        screen.backButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spyB.count, 1)

        // Continue via Space → continueRequested
        var spyC = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'continueRequested' }",
            screen, "fbwKeySpyC")
        spyC.target = screen
        screen.continueButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spyC.count, 1)

        // Error-state Retry via Space → retryRequested
        var spyRt = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'retryRequested' }",
            screen, "fbwKeySpyRt")
        spyRt.target = screen
        screen.screenState = "error"
        screen.retryButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spyRt.count, 1)

        screen.destroy()
    }

    // ── Escape navigates back ──────────────────────────────────────
    function test_escapeNavigatesBack() {
        var screen = createScreen()
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'backRequested' }",
            screen, "fbwEscSpy")
        spy.target = screen

        // Warm up the hosted window (first key event is consumed by
        // window activation on this build).
        screen.backButton.forceActiveFocus()
        keyClick(Qt.Key_W)
        screen.backButton.forceActiveFocus()
        keyClick(Qt.Key_Escape)
        compare(spy.count, 1)

        screen.destroy()
    }

    // ── Accessibility roles / names ────────────────────────────────
    function test_accessibility() {
        var screen = createScreen()

        // Heading is announced as a heading with a name
        verify(screen.headingLabel.Accessible.role === Accessible.Heading)
        verify(screen.headingLabel.Accessible.name.length > 0)

        // Read-back list is a named list; its items are list items with
        // the rendered value announced
        verify(screen.detailList.Accessible.role === Accessible.List)
        verify(screen.detailList.Accessible.name.length > 0)
        var item0 = screen.detailList.itemAtIndex(0)
        verify(item0.Accessible.role === Accessible.ListItem)
        verify(item0.Accessible.name.indexOf("Installed version") >= 0)
        verify(item0.Accessible.name.indexOf("0.1.0") >= 0)

        // Quick introduction is announced
        verify(screen.introLabel.Accessible.name.length > 0)

        // Buttons announce role + name
        verify(screen.backButton.Accessible.role === Accessible.Button)
        compare(screen.backButton.Accessible.name, screen.backButton.text)
        verify(screen.continueButton.Accessible.role === Accessible.Button)
        compare(screen.continueButton.Accessible.name, screen.continueButton.text)
        verify(screen.documentationButton.Accessible.role === Accessible.Button)
        verify(screen.releaseNotesButton.Accessible.role === Accessible.Button)

        screen.destroy()
    }

    // ── Theme light/dark rendering ─────────────────────────────────
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

        // Compact error state: the banner and its Retry action must
        // still render with positive height and fit the content column
        compact.screenState = "error"
        verify(compact.errorBanner.visible)
        verify(compact.errorBanner.height > 0,
               "compact error banner must render with positive height")
        verify(compact.retryButton.visible)
        verify(compact.errorBanner.width <= compact.contentColumn.width)
        compact.destroy()
    }

    // ── MissionPage / MissionWindow integration ────────────────────
    function test_missionPageIntegration() {
        var page = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionPage { pageTitle: 'First Boot'; FirstBootWelcome { objectName: 'fbwInPage' } }",
            root, "fbwInPage")
        verify(page !== null)
        verify(page.data.length > 0)
        page.destroy()
    }

    function test_missionWindowIntegration() {
        var screen = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionWindow { width: 1024; height: 768; FirstBootWelcome { objectName: 'fbwInWindow' } }",
            root, "fbwInWindow")
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

        // Host wiring still works with reduced motion
        screen.version = "0.3.0"
        compare(screen.version, "0.3.0")

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
