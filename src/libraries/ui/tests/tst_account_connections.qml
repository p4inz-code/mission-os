// Mission OS — Optional Account Connections (MOS-INS-016) QtTest suite
//
// Runtime validation of the Optional Account Connections screen. Follows
// the foundation smoke-test pattern (tests/tst_smoke.qml) and the
// MOS-INS-001→015 Installer suites (in particular the Security Options
// toggle suite) per docs/engineering/TESTING_STRATEGY.md (QML → Qt Test
// / qmltestrunner).
//
// Coverage (only behaviors required by the authoritative sources —
// reference § "Screen 18 — Optional Account Connections", registry
// MOS-INS-016):
//   - screen loads without QML errors (token singletons resolve)
//   - default state: step 16 of 17, the reference's five optional
//     integrations shown, every integration OFF by default (optional,
//     privacy by default), Continue enabled (valid state — nothing is
//     mandatory), Back enabled (step 16 > 1)
//   - no spurious action or host-change signals on load
//   - the five integrations exactly as listed in the reference (GitHub,
//     GitLab, Nextcloud, Microsoft account, Google account), in order —
//     no integration invented or omitted
//   - toggling an integration fires accountConnectionRequested exactly
//     once per change, carrying the code and the connected state
//   - host wiring: the host can feed the connected state back into the
//     connected properties; switches and the summary reflect it
//   - required signals fire from the right controls (continue/back/retry)
//   - required state transitions (empty/loading/error/success/offline)
//   - Continue is blocked while loading/error (validation-before-continue)
//   - state banners render with positive height (banner-height regression)
//   - keyboard navigation: Space toggles a focused integration switch;
//     focus reaches all toggles, Back and Continue
//   - Escape navigates back
//   - accessibility roles/names (heading, grouping cards, checkbox
//     toggles, buttons)
//   - responsive compact layout (help panel collapses)
//   - 1024×768 usability: all five integrations render and the content
//     scrolls to reach them (no unreachable controls)
//   - reduced motion does not break rendering
//   - MissionPage / MissionWindow integration introduces no runtime errors
//
// Run via qmltestrunner (see CMakeLists.txt CTest registration):
//   qmltestrunner -import <build>/src/libraries/ui/qml \
//                 -input src/libraries/ui/tests/tst_account_connections.qml
//
// Exit code: 0 = all checks passed; non-zero = failure (CI gate).

import QtQuick
import QtQuick.Controls
import QtTest
import org.mission.ui 1.0

TestCase {
    id: root
    name: "AccountConnections"

    // ── Helpers ────────────────────────────────────────────────────
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
                     "    AccountConnections { id: screen; width: " + width +
                     "; height: " + height + "; " + (extra || "") + " }\n" +
                     "}"
        var host = Qt.createQmlObject(source, root, "accHost" + _hostWindows.length)
        _hostWindows.push(host)
        return host.screen
    }

    function getToggle(screen, index) {
        var item = screen.accountRows.itemAt(index)
        return item ? item.toggleControl : null
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
        // Step context: Optional Account Connections is installer step 16 of 17
        compare(screen.step, 16)
        compare(screen.totalSteps, 17)
        // All five optional integrations exist (reference § "Screen 18")
        compare(screen.accountCount, 5)
        // Defaults: every integration OFF (optional, privacy by default);
        // Continue enabled (valid state — nothing is mandatory); Back
        // enabled (step 16 > 1).
        compare(screen.connectedCount, 0)
        verify(screen.continueButton.enabled)
        verify(screen.backButton.enabled)
        screen.destroy()
    }

    // ── The five integrations match the reference exactly ──────────
    // Reference § "Screen 18": "Optional integrations may include:
    // GitHub, GitLab, Nextcloud, Microsoft account, Google account."
    // No integration may be invented or omitted.
    function test_accountsMatchReference() {
        var screen = createScreen()
        var expected = [
            ["github",    "GitHub"],
            ["gitlab",    "GitLab"],
            ["nextcloud", "Nextcloud"],
            ["microsoft", "Microsoft account"],
            ["google",    "Google account"]
        ]
        compare(screen.optionalAccounts.length, expected.length)
        for (var i = 0; i < expected.length; ++i) {
            compare(screen.optionalAccounts[i].code, expected[i][0], "account " + i + " code")
            compare(screen.optionalAccounts[i].label, expected[i][1], "account " + i + " label")
            verify(screen.optionalAccounts[i].description.length > 0,
                   "account " + expected[i][0] + " must carry a description")
        }
        // All five rows are present in the list
        compare(screen.accountRows.count, 5)
        screen.destroy()
    }

    // ── Default toggle states ──────────────────────────────────────
    function test_defaultToggleStates() {
        var screen = createScreen()
        // Every integration is OFF by default (optional — privacy by
        // default: no account, no telemetry, no cloud required)
        compare(screen.githubConnected, false)
        compare(screen.gitlabConnected, false)
        compare(screen.nextcloudConnected, false)
        compare(screen.microsoftConnected, false)
        compare(screen.googleConnected, false)
        for (var i = 0; i < 5; ++i) {
            var toggle = getToggle(screen, i)
            verify(toggle !== null, "toggle " + i + " must exist")
            verify(!toggle.checked, "toggle " + i + " must be off by default")
        }
        // Summary reflects the default state
        verify(screen.selectionCaption.visible)
        verify(screen.selectionCaption.text.indexOf("No accounts connected") >= 0)
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
                     "    property alias spyR: spyR\n" +
                     "    property alias spyA: spyA\n" +
                     "    AccountConnections { id: screen; width: 1024; height: 768\n" +
                     "        SignalSpy { id: spyC; signalName: 'continueRequested'; target: screen }\n" +
                     "        SignalSpy { id: spyB; signalName: 'backRequested'; target: screen }\n" +
                     "        SignalSpy { id: spyR; signalName: 'retryRequested'; target: screen }\n" +
                     "        SignalSpy { id: spyA; signalName: 'accountConnectionRequested'; target: screen }\n" +
                     "    }\n" +
                     "}\n"
        var host = Qt.createQmlObject(source, root, "accLoadHost")
        _hostWindows.push(host)
        compare(host.spyC.count, 0)
        compare(host.spyB.count, 0)
        compare(host.spyR.count, 0)
        compare(host.spyA.count, 0)
        host.destroy()
    }

    // ── Toggling emits the host-change signal with code + state ────
    function test_toggleSignals() {
        var screen = createScreen()
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'accountConnectionRequested' }",
            screen, "accToggleSpy")
        spy.target = screen

        // Connect GitHub (index 0)
        var toggle = getToggle(screen, 0)
        verify(toggle !== null, "github toggle must exist")
        toggle.checked = true
        compare(screen.githubConnected, true)
        compare(screen.connectedCount, 1)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "github")
        compare(spy.signalArguments[0][1], true)

        // Connect Nextcloud (index 2)
        toggle = getToggle(screen, 2)
        verify(toggle !== null, "nextcloud toggle must exist")
        toggle.checked = true
        compare(screen.nextcloudConnected, true)
        compare(screen.connectedCount, 2)
        compare(spy.count, 2)
        compare(spy.signalArguments[1][0], "nextcloud")
        compare(spy.signalArguments[1][1], true)

        // Disconnect GitHub again
        toggle = getToggle(screen, 0)
        toggle.checked = false
        compare(screen.githubConnected, false)
        compare(screen.connectedCount, 1)
        compare(spy.count, 3)
        compare(spy.signalArguments[2][0], "github")
        compare(spy.signalArguments[2][1], false)

        // Summary reflects the live state
        verify(screen.selectionCaption.text.indexOf("Connected: Nextcloud") >= 0)

        screen.destroy()
    }

    // ── Host wiring: the host feeds the connected state back ───────
    // The host runs the real authorization flow and reports the result
    // through the connected properties; switches and the summary must
    // reflect it (established toggle pattern, e.g. SecurityOptions:
    // onCheckedChanged fires on both programmatic and user-initiated
    // changes).
    function test_hostWiring() {
        var screen = createScreen()
        screen.microsoftConnected = true
        wait(50) // let the binding re-evaluate the switch state
        var toggle = getToggle(screen, 3)
        verify(toggle !== null)
        verify(toggle.checked, "host-fed connected state must reflect on the switch")
        verify(screen.connectedSummary.indexOf("Microsoft account") >= 0)

        screen.googleConnected = true
        wait(50)
        verify(getToggle(screen, 4).checked)
        compare(screen.connectedCount, 2)

        // getAccount resolves the fixture by code
        var git = screen.getAccount("github")
        verify(git !== null)
        compare(git.label, "GitHub")
        verify(screen.getAccount("nope") === null)

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
                spyNames[i] + "' }", screen, "accActSpy" + i)
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
        // empty (default): no banner, Continue enabled (valid state)
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
        wait(100) // let the hosted window activate so key events reach it
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'continueRequested' }",
            screen, "accContSpy")
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

    // ── Keyboard: Space toggles a focused integration switch ───────
    function test_keyboardToggle() {
        var screen = createScreen()
        wait(100) // let the hosted window activate so key events reach it
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'accountConnectionRequested' }",
            screen, "accKbdSpy")
        spy.target = screen

        // Warm up the hosted window (first key event is consumed by
        // window activation on this build — same pattern as 001–015).
        keyClick(Qt.Key_Tab)

        // Focus the GitHub toggle and toggle it with Space
        var toggle = getToggle(screen, 0)
        verify(toggle !== null)
        toggle.forceActiveFocus()
        verify(toggle.activeFocus)
        keyClick(Qt.Key_Space)
        verify(toggle.checked, "Space must toggle the focused switch on")
        compare(screen.githubConnected, true)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "github")
        compare(spy.signalArguments[0][1], true)

        // Space again toggles it back off
        keyClick(Qt.Key_Space)
        verify(!toggle.checked, "Space must toggle the focused switch off")
        compare(screen.githubConnected, false)
        compare(spy.count, 2)
        compare(spy.signalArguments[1][1], false)

        screen.destroy()
    }

    // ── Keyboard focus reaches all actionable controls ─────────────
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

        // Every integration toggle is a Tab stop, plus Back and Continue.
        for (var i = 0; i < 5; ++i)
            verify(found["accountsToggle" + i], "focus must reach accountsToggle" + i)
        verify(found["accountsBack"], "focus must reach accountsBack")
        verify(found["accountsContinue"], "focus must reach accountsContinue")

        screen.destroy()
    }

    // ── Escape navigates back ──────────────────────────────────────
    function test_escapeNavigatesBack() {
        var screen = createScreen()
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'backRequested' }",
            screen, "accEscSpy")
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
        screen.googleConnected = true
        wait(50)

        // Heading is announced as a heading with a name
        verify(screen.headingLabel.Accessible.role === Accessible.Heading)
        verify(screen.headingLabel.Accessible.name.length > 0)

        // Each integration card is a named grouping with a description
        var item0 = screen.accountRows.itemAt(0)
        verify(item0 !== null)
        verify(item0.Accessible.role === Accessible.Grouping)
        verify(item0.Accessible.name.indexOf("GitHub") >= 0)
        verify(item0.Accessible.description.length > 0)

        // Each toggle is a checkbox with the connected state announced
        var toggle0 = getToggle(screen, 0)
        verify(toggle0.Accessible.role === Accessible.CheckBox)
        compare(toggle0.Accessible.name, "GitHub")
        verify(toggle0.Accessible.description.length > 0)
        verify(!toggle0.Accessible.checked, "disconnected toggle must not announce checked")

        var toggle4 = getToggle(screen, 4)
        verify(toggle4.Accessible.checked, "connected toggle must announce checked")

        // Buttons announce role + name
        verify(screen.backButton.Accessible.role === Accessible.Button)
        compare(screen.backButton.Accessible.name, screen.backButton.text)
        verify(screen.continueButton.Accessible.role === Accessible.Button)
        compare(screen.continueButton.Accessible.name, screen.continueButton.text)

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

    // ── 1024×768 (implementation target): every integration renders
    //    and the content scrolls to reach all controls ──────────────
    function test_usableAt1024x768() {
        var screen = createScreen() // 1024×768
        wait(100)
        for (var i = 0; i < 5; ++i) {
            var item = screen.accountRows.itemAt(i)
            verify(item !== null, "account row " + i + " must be instantiated")
            verify(item.height > 0, "account row " + i + " must render with positive height")
            verify(getToggle(screen, i) !== null)
        }
        // All five toggles are reachable: the content column is taller
        // than the viewport, so the screen scrolls (Flickable) — the
        // last toggle becomes visible by scrolling to the bottom.
        verify(screen.contentFlickable.contentHeight > screen.contentFlickable.height,
               "content must scroll at 1024×768 so every control is reachable")
        // Scroll to the true bottom: Flickable.contentY is NOT clamped
        // on direct assignment (verified empirically on this Qt 6.10
        // toolchain), so assigning contentHeight would over-scroll past
        // the end and push the last row back out of view. The maximum
        // scroll offset is contentHeight - height.
        screen.contentFlickable.contentY =
            screen.contentFlickable.contentHeight - screen.contentFlickable.height
        wait(50)
        // After scrolling to the bottom, the last toggle must be inside
        // the visible viewport (its top edge above the viewport bottom
        // and its bottom edge below the viewport top) — genuinely
        // reachable on screen, not merely present somewhere in the
        // scrollable content.
        var lastToggle = getToggle(screen, 4)
        var pos = lastToggle.mapToItem(screen.contentFlickable, 0, 0)
        var view = screen.contentFlickable
        verify(pos.y < view.height,
               "last toggle top edge must be above the viewport bottom (y=" + pos.y + ")")
        verify(pos.y + lastToggle.height > 0,
               "last toggle bottom edge must be below the viewport top")
        screen.destroy()
    }

    // ── MissionPage / MissionWindow integration ────────────────────
    function test_missionPageIntegration() {
        var page = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionPage { pageTitle: 'First Boot'; AccountConnections { objectName: 'accInPage' } }",
            root, "accInPage")
        verify(page !== null)
        verify(page.data.length > 0)
        page.destroy()
    }

    function test_missionWindowIntegration() {
        var screen = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionWindow { width: 1024; height: 768; AccountConnections { objectName: 'accInWindow' } }",
            root, "accInWindow")
        verify(screen !== null)
        verify(screen.width > 0)
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
        var toggle = getToggle(screen, 1)
        verify(toggle !== null)
        toggle.checked = true
        compare(screen.gitlabConnected, true)
        compare(screen.connectedCount, 1)

        screen.reducedMotion = false
        screen.destroy()
    }

    // Reset theme mode and destroy hosted test windows after each test
    function cleanup() {
        for (var i = 0; i < _hostWindows.length; ++i)
            _hostWindows[i].destroy()
        _hostWindows = []
        MissionTheme.darkMode = false
    }
}
