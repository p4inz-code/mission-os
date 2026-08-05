// Mission OS — System Ready (MOS-INS-017) QtTest suite
//
// Runtime validation of the System Ready screen. Follows the
// foundation smoke-test pattern (tests/tst_smoke.qml) and the
// MOS-INS-001→016 Installer suites (in particular the Completion
// terminal-screen suite and the Optional Account Connections
// navigation suite) per docs/engineering/TESTING_STRATEGY.md
// (QML → Qt Test / qmltestrunner).
//
// Coverage (only behaviors required by the authoritative sources —
// reference § "Screen 19 — System Ready", registry MOS-INS-017):
//   - screen loads without QML errors (token singletons resolve)
//   - default state: step 17 of 17, the reference's eight display
//     items present — the heading "Installation complete" (item 1),
//     the three read-only status rows (items 2–4: Recovery
//     configured, Security status, Privacy status), the three open
//     actions (items 5–7: Open Mission Hub, Open Settings, Open
//     Documentation) and the primary Finish action (item 8)
//   - no spurious action signals on load — the screen emits nothing
//     during initialization (host-driven; all six signals stay silent
//     until a user action)
//   - host wiring: the host may replace the systemStatus fixture
//     wholesale with the real recovery/security/privacy state; the
//     list, the count and the rendered rows reflect it; getStatus()
//     resolves by code and unknown codes yield null
//   - all six action signals fire from the right controls (Finish,
//     Back, Open Mission Hub, Open Settings, Open Documentation,
//     plus Retry in the error state)
//   - required state transitions (empty/loading/error/success/offline)
//     including the loading indicator and the state banners
//   - state banners render with positive height (banner-height
//     regression established in MOS-INS-001/002/003)
//   - validation-before-continue on the terminal action: Finish is
//     blocked while loading/error (keyboard cannot activate it) and
//     enabled in every valid state; Back stays available (step 17 > 1)
//   - terminal-screen behavior: no Continue exists (the reference
//     defines Finish, not Continue, as the terminal action — same
//     interpretation as the Completion terminal screen)
//   - keyboard navigation: all enabled action buttons (and error-state
//     Retry) are Tab stops; the read-only status rows are NOT Tab
//     stops (no keyboard trap); the gated Finish is correctly skipped
//     while loading/error (disabled controls are not focusable); Tab
//     and Shift+Tab wrap through the chain; Space activates every
//     button
//   - Escape → backRequested (Master UX: Back always available)
//   - accessibility roles/names (heading, status list + items,
//     buttons)
//   - light/dark theme via MissionTheme
//   - responsive reflow per docs/design/14_RESPONSIVE_RULES.md:
//     wide (≥760) shows the help panel, compact (<640) collapses it,
//     and the 640–759px band is neither compact nor wide
//   - 1024×768 usability: the three status rows render in the
//     viewport without scrolling, so every control is reachable
//   - 480×768 compact behavior: screen usable, help panel collapsed,
//     all rows render, action bar controls visible
//   - reduced motion does not break rendering
//   - 44px minimum touch targets on every action button
//   - MissionPage / MissionWindow integration introduces no runtime
//     errors
//
// Run via qmltestrunner (see CMakeLists.txt CTest registration):
//   qmltestrunner -import <build>/src/libraries/ui/qml \
//                 -input src/libraries/ui/tests/tst_system_ready.qml
//
// Exit code: 0 = all checks passed; non-zero = failure (CI gate).

import QtQuick
import QtTest
import org.mission.ui 1.0

TestCase {
    id: root
    name: "SystemReady"

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
                     "    SystemReady { id: screen; width: " + width + "; height: " + height +
                     "; " + (extra || "") + " }\n" +
                     "}"
        var host = Qt.createQmlObject(source, root, "sysHost" + _hostWindows.length)
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
        // Step context: System Ready is the final installer step, 17 of 17
        compare(screen.step, 17)
        compare(screen.totalSteps, 17)
        // The three read-only status rows exist (reference display items 2–4)
        compare(screen.statusCount, 3)
        compare(screen.statusList.count, 3)
        verify(screen.statusList.height > 0,
               "status list must render with positive height")
        // The three open actions (items 5–7) and the primary Finish
        // action (item 8) are present; Back is available (step 17 > 1).
        verify(screen.missionHubButton.enabled)
        verify(screen.settingsButton.enabled)
        verify(screen.documentationButton.enabled)
        verify(screen.backButton.enabled)
        verify(screen.finishButton.enabled)
        compare(screen.finishButton.text, "Finish")
        compare(screen.backButton.text, "Back")
        // Finish is the terminal action and carries the initial focus.
        compare(screen.finishButton.focus, true,
                "Finish must hold the initial focus on the terminal screen")
        screen.destroy()
    }

    // ── The three status rows match the reference exactly ──────────
    // Reference § "Screen 19 — System Ready" display items 2–4:
    // "Recovery configured", "Security status", "Privacy status". No
    // row may be invented or omitted. The values are least-assumption
    // host-fed fixtures (documented interpretation in SystemReady.qml).
    function test_statusMatchesReference() {
        var screen = createScreen()
        var expected = [
            ["recovery", "Recovery configured", "Configured"],
            ["security", "Security status",     "Protected"],
            ["privacy",  "Privacy status",      "Privacy by default"]
        ]
        compare(screen.systemStatus.length, expected.length)
        for (var i = 0; i < expected.length; ++i) {
            compare(screen.systemStatus[i].code, expected[i][0],
                    "status " + i + " code")
            compare(screen.systemStatus[i].label, expected[i][1],
                    "status " + i + " label")
            compare(screen.systemStatus[i].value, expected[i][2],
                    "status " + i + " value")
        }
        // getStatus() resolves every status code and rejects unknowns
        compare(screen.getStatus("recovery").label, "Recovery configured")
        compare(screen.getStatus("privacy").value, "Privacy by default")
        compare(screen.getStatus("nonexistent"), null)
        // detailRowHeight is the single source of truth for row sizing
        compare(screen.detailRowHeight, 44)
        screen.destroy()
    }

    // ── The heading is the reference display item 1 ────────────────
    // Reference § "Screen 19": "Display: Installation complete …"
    function test_authoritativeHeading() {
        var screen = createScreen()
        compare(screen.headingLabel.text, "Installation complete")
        screen.destroy()
    }

    // ── Defaults must not emit spurious signals ────────────────────
    // Regression guard: the System Ready screen is host-fed and emits
    // nothing during initialization — all six action signals must stay
    // at zero immediately after load and after the engine settles.
    function test_noSignalsOnLoad() {
        var source = "import QtQuick\n" +
                     "import QtTest\n" +
                     "import org.mission.ui 1.0\n" +
                     "Window {\n" +
                     "    width: 1024; height: 768; visible: true\n" +
                     "    property alias screen: screen\n" +
                     "    property alias spyFinish: spyFinish\n" +
                     "    property alias spyBack: spyBack\n" +
                     "    property alias spyHub: spyHub\n" +
                     "    property alias spySettings: spySettings\n" +
                     "    property alias spyDocs: spyDocs\n" +
                     "    property alias spyRetry: spyRetry\n" +
                     "    SystemReady { id: screen; width: 1024; height: 768\n" +
                     "        SignalSpy { id: spyFinish;   signalName: 'finishRequested'; target: screen }\n" +
                     "        SignalSpy { id: spyBack;     signalName: 'backRequested'; target: screen }\n" +
                     "        SignalSpy { id: spyHub;      signalName: 'missionHubRequested'; target: screen }\n" +
                     "        SignalSpy { id: spySettings; signalName: 'settingsRequested'; target: screen }\n" +
                     "        SignalSpy { id: spyDocs;     signalName: 'documentationRequested'; target: screen }\n" +
                     "        SignalSpy { id: spyRetry;    signalName: 'retryRequested'; target: screen }\n" +
                     "    }\n" +
                     "}\n"
        var host = Qt.createQmlObject(source, root, "sysLoadHost")
        _hostWindows.push(host)
        compare(host.spyFinish.count, 0)
        compare(host.spyBack.count, 0)
        compare(host.spyHub.count, 0)
        compare(host.spySettings.count, 0)
        compare(host.spyDocs.count, 0)
        compare(host.spyRetry.count, 0)
        // Let the engine settle — still nothing may fire.
        wait(80)
        compare(host.spyFinish.count, 0)
        compare(host.spyBack.count, 0)
        compare(host.spyHub.count, 0)
        compare(host.spySettings.count, 0)
        compare(host.spyDocs.count, 0)
        compare(host.spyRetry.count, 0)
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

    // ── Host wiring: the host replaces the status fixture ──────────
    // The host feeds the real recovery/security/privacy state into the
    // screen by replacing the systemStatus fixture wholesale (documented
    // interpretation in SystemReady.qml). The count, the list, the row
    // heights and the rendered rows must all reflect the new data
    // (genuine behavior — the screen must display the real state per
    // reference § "Screen 19").
    function test_hostStatusReplacement() {
        var screen = createScreen()
        compare(screen.statusCount, 3)
        compare(screen.statusList.height, 3 * 44 + 2 * 4)

        // Host wires the real system state (including a new row)
        screen.systemStatus = [
            { code: "recovery", label: "Recovery configured", value: "Configured — GRUB" },
            { code: "security", label: "Security status",     value: "Locked down" },
            { code: "privacy",  label: "Privacy status",      value: "Maximal" },
            { code: "updates",  label: "Update status",       value: "Up to date" }
        ]
        compare(screen.statusCount, 4)
        compare(screen.statusList.count, 4)
        compare(screen.statusList.height, 4 * 44 + 3 * 4)
        compare(screen.getStatus("updates").label, "Update status")

        // The rendered list rows reflect the new values
        wait(50) // let the model reset re-instantiate the visible rows
        var rec = screen.statusList.itemAtIndex(0)
        verify(rec !== null, "recovery row delegate must be instantiated")
        compare(rec.objectName, "systemReadyStatusItem0")
        compare(rec.valueLabel.text, "Configured — GRUB")
        var upd = screen.statusList.itemAtIndex(3)
        verify(upd !== null, "updates row delegate must be instantiated")
        compare(upd.valueLabel.text, "Up to date")

        // Data wiring emits no action signals (passive screen)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'finishRequested' }",
            screen, "sysDataSpy")
        spy.target = screen
        screen.systemStatus = [
            { code: "recovery", label: "Recovery configured", value: "Configured" },
            { code: "security", label: "Security status",     value: "Protected" },
            { code: "privacy",  label: "Privacy status",      value: "Privacy by default" }
        ]
        compare(spy.count, 0)

        screen.destroy()
    }

    // ── All reference actions fire from the right controls ─────────
    function test_actionSignals() {
        var screen = createScreen()
        var spies = []
        var spyNames = ["finishRequested", "backRequested", "missionHubRequested",
                        "settingsRequested", "documentationRequested"]
        for (var i = 0; i < spyNames.length; ++i) {
            var spy = Qt.createQmlObject(
                "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: '" +
                spyNames[i] + "' }", screen, "sysSpy" + i)
            spy.target = screen
            spies.push(spy)
        }

        screen.finishButton.clicked()
        compare(spies[0].count, 1)

        screen.backButton.clicked()
        compare(spies[1].count, 1)

        screen.missionHubButton.clicked()
        compare(spies[2].count, 1)

        screen.settingsButton.clicked()
        compare(spies[3].count, 1)

        screen.documentationButton.clicked()
        compare(spies[4].count, 1)

        // Error-state Retry → retryRequested
        var spyR = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'retryRequested' }",
            screen, "sysSpyRetry")
        spyR.target = screen
        screen.screenState = "error"
        screen.retryButton.clicked()
        compare(spyR.count, 1)

        screen.destroy()
    }

    // ── Required state transitions ─────────────────────────────────
    function test_stateTransitions() {
        var screen = createScreen()
        // empty (default): no banner, Finish enabled (valid state)
        verify(!screen.loadingIndicator.visible)
        verify(!screen.errorBanner.visible)
        verify(!screen.successBanner.visible)
        verify(!screen.offlineBanner.visible)
        verify(screen.finishButton.enabled)

        // loading: progress shown, Finish disabled (validation pending)
        screen.screenState = "loading"
        verify(screen.loadingIndicator.visible)
        verify(!screen.errorBanner.visible)
        verify(!screen.successBanner.visible)
        verify(!screen.offlineBanner.visible)
        verify(!screen.finishButton.enabled)

        // error: error banner + Retry, Finish disabled
        screen.screenState = "error"
        verify(screen.errorBanner.visible)
        verify(!screen.loadingIndicator.visible)
        verify(!screen.successBanner.visible)
        verify(!screen.offlineBanner.visible)
        verify(!screen.finishButton.enabled)
        verify(screen.retryButton.visible)

        // success: success banner, Finish enabled
        screen.screenState = "success"
        verify(screen.successBanner.visible)
        verify(!screen.loadingIndicator.visible)
        verify(!screen.errorBanner.visible)
        verify(!screen.offlineBanner.visible)
        verify(screen.finishButton.enabled)

        // offline: informational banner, Finish enabled
        screen.screenState = "offline"
        verify(screen.offlineBanner.visible)
        verify(!screen.loadingIndicator.visible)
        verify(!screen.errorBanner.visible)
        verify(!screen.successBanner.visible)
        verify(screen.finishButton.enabled)

        // back to empty clears everything
        screen.screenState = "empty"
        verify(!screen.loadingIndicator.visible)
        verify(!screen.errorBanner.visible)
        verify(!screen.successBanner.visible)
        verify(!screen.offlineBanner.visible)

        // Back stays available in every state (step 17 > 1 — the host
        // decides what backRequested() means on this terminal screen)
        screen.screenState = "error"
        verify(screen.backButton.enabled)
        screen.screenState = "success"
        verify(screen.backButton.enabled)

        screen.destroy()
    }

    // ── State banners must render (not collapse to 0 height) ───────
    // Regression guard for the banner-height bug class found in
    // MOS-INS-001/002/003: the error/success/offline banners must have
    // positive rendered height whenever their state is active, and the
    // loading indicator must render with positive height too.
    function test_stateBannersRender() {
        var screen = createScreen()

        screen.screenState = "loading"
        verify(screen.loadingIndicator.visible)
        verify(screen.loadingIndicator.height > 0,
               "loading indicator must render with positive height")

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

    // ── Finish must not silently advance while loading/error ───────
    // Validation-before-continue on the terminal action: Finish is the
    // reference's item 8 ("After completion, the user enters the Mission
    // OS desktop"), and it must never fire while the system status is
    // still loading or failed. Back remains available regardless.
    function test_finishBlockedWhileLoadingError() {
        var screen = createScreen()
        wait(100) // let the hosted window activate so key events reach it
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'finishRequested' }",
            screen, "sysFinishSpy")
        spy.target = screen

        // Loading: Finish disabled → no signal from keyboard input
        screen.screenState = "loading"
        verify(!screen.finishButton.enabled)
        screen.finishButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        keyClick(Qt.Key_Return)
        compare(spy.count, 0)

        // Error: Finish disabled → no signal
        screen.screenState = "error"
        verify(!screen.finishButton.enabled)
        screen.finishButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        keyClick(Qt.Key_Return)
        compare(spy.count, 0)

        // Success: valid state → Finish enabled → keyboard advances
        screen.screenState = "success"
        verify(screen.finishButton.enabled)
        screen.finishButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spy.count, 1)

        screen.destroy()
    }

    // ── Keyboard focus reaches all actionable controls ─────────────
    // All five action buttons must be Tab stops; the read-only status
    // rows are deliberately NOT Tab stops (no keyboard trap — they
    // convey information, they are not interactive).
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

        verify(found["systemFinish"], "focus must reach systemFinish")
        verify(found["systemBack"], "focus must reach systemBack")
        verify(found["systemMissionHub"], "focus must reach systemMissionHub")
        verify(found["systemSettings"], "focus must reach systemSettings")
        verify(found["systemDocumentation"], "focus must reach systemDocumentation")

        // Read-only status rows must NOT be keyboard Tab stops.
        for (var row = 0; row < 3; ++row) {
            verify(!("systemReadyStatusItem" + row in found),
                   "read-only status row " + row + " must not be a Tab stop")
        }

        screen.destroy()
    }

    // ── Error state adds Retry to the focus chain ──────────────────
    // Retry becomes a Tab stop in the error state. Back stays reachable.
    // Finish is disabled while error (validation-before-continue), and
    // disabled controls are skipped by keyboard navigation — so the
    // gated terminal action must NOT be a Tab stop while gated.
    function test_keyboardFocusErrorState() {
        var screen = createScreen()
        screen.screenState = "error"
        wait(100)
        var hostWindow = _hostWindows[_hostWindows.length - 1]
        var found = {}
        for (var tab = 0; tab < 100; ++tab) {
            keyClick(Qt.Key_Tab)
            var focusItem = hostWindow.activeFocusItem
            if (focusItem && focusItem.objectName)
                found[focusItem.objectName] = true
        }
        verify(found["systemRetry"], "focus must reach systemRetry")
        verify(found["systemBack"], "focus must still reach systemBack")
        verify(!("systemFinish" in found),
               "disabled Finish must not be a Tab stop in the error state")
        screen.destroy()
    }

    // ── Tab and Shift+Tab wrap through the focus chain ─────────────
    // Every stop in the chain is one of the System Ready action buttons
    // (or Retry in the error state) — the chain never escapes into a
    // read-only status row or a dead end. The wrap check matches the
    // known interactive objectNames explicitly (not a shared prefix),
    // so a regression that made a status row focusable would fail here.
    function test_tabWrapsBothDirections() {
        var screen = createScreen()
        wait(100)
        var hostWindow = _hostWindows[_hostWindows.length - 1]

        // Warm up the hosted window (first key event is consumed by
        // window activation on this build).
        screen.finishButton.forceActiveFocus()
        keyClick(Qt.Key_W)

        var isActionButton = function(name) {
            return name === "systemBack" || name === "systemFinish" ||
                   name === "systemMissionHub" || name === "systemSettings" ||
                   name === "systemDocumentation"
        }

        // Tab from the last stop wraps to another action button.
        screen.finishButton.forceActiveFocus()
        keyClick(Qt.Key_Tab)
        var focusItem = hostWindow.activeFocusItem
        verify(focusItem !== null && isActionButton(focusItem.objectName),
               "Tab from Finish must wrap to another action button, got: " +
               (focusItem ? focusItem.objectName : "none"))

        // Shift+Tab from that stop wraps backward to an action button.
        keyClick(Qt.Key_Backtab)
        focusItem = hostWindow.activeFocusItem
        verify(focusItem !== null && isActionButton(focusItem.objectName),
               "Shift+Tab must wrap to another action button, got: " +
               (focusItem ? focusItem.objectName : "none"))

        screen.destroy()
    }

    // ── Space activates every action button ────────────────────────
    // QQC2 Buttons activate on Space. Enter is not exercised on the
    // open actions (no default button exists); the Finish gating test
    // above already exercises Return on the primary action.
    function test_spaceActivationOnButtons() {
        var screen = createScreen()
        wait(100)

        // Warm up the hosted window (first key event is consumed by
        // window activation on this build — the established pattern).
        screen.finishButton.forceActiveFocus()
        keyClick(Qt.Key_W)

        var spies = []
        var spyNames = ["finishRequested", "backRequested", "missionHubRequested",
                        "settingsRequested", "documentationRequested"]
        for (var i = 0; i < spyNames.length; ++i) {
            var spy = Qt.createQmlObject(
                "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: '" +
                spyNames[i] + "' }", screen, "sysKeySpy" + i)
            spy.target = screen
            spies.push(spy)
        }

        // Finish via Space → finishRequested
        screen.finishButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spies[0].count, 1)

        // Back via Space → backRequested
        screen.backButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spies[1].count, 1)

        // Open Mission Hub via Space → missionHubRequested
        screen.missionHubButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spies[2].count, 1)

        // Open Settings via Space → settingsRequested
        screen.settingsButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spies[3].count, 1)

        // Open Documentation via Space → documentationRequested
        screen.documentationButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spies[4].count, 1)

        // Error-state Retry via Space → retryRequested
        var spyR = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'retryRequested' }",
            screen, "sysKeySpyR")
        spyR.target = screen
        screen.screenState = "error"
        screen.retryButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spyR.count, 1)

        screen.destroy()
    }

    // ── Escape navigates back ──────────────────────────────────────
    // Master UX: "Back navigation always available". The screen has no
    // Back-disabling state (step 17 > 1) and no child consumes Escape,
    // so Escape always → backRequested — even with an action button
    // focused.
    function test_escapeNavigatesBack() {
        var screen = createScreen()
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'backRequested' }",
            screen, "sysEscSpy")
        spy.target = screen

        // Warm up the hosted window (first key event is consumed by
        // window activation on this build).
        screen.finishButton.forceActiveFocus()
        keyClick(Qt.Key_W)
        screen.finishButton.forceActiveFocus()
        keyClick(Qt.Key_Escape)
        compare(spy.count, 1)

        // Escape with a tertiary action focused fires back too
        screen.missionHubButton.forceActiveFocus()
        keyClick(Qt.Key_Escape)
        compare(spy.count, 2)

        screen.destroy()
    }

    // ── Accessibility roles / names ────────────────────────────────
    function test_accessibility() {
        var screen = createScreen()
        screen.screenState = "error"

        // Heading is announced as a heading with a name
        verify(screen.headingLabel.Accessible.role === Accessible.Heading)
        compare(screen.headingLabel.Accessible.name, "Installation complete")

        // Status list is a named list; its items are named list items
        // announcing exactly what is rendered (label: value).
        verify(screen.statusList.Accessible.role === Accessible.List)
        verify(screen.statusList.Accessible.name.length > 0)
        var item0 = screen.statusList.itemAtIndex(0)
        verify(item0 !== null)
        verify(item0.Accessible.role === Accessible.ListItem)
        compare(item0.Accessible.name, "Recovery configured: Configured")

        // Every action button announces role + name
        verify(screen.finishButton.Accessible.role === Accessible.Button)
        compare(screen.finishButton.Accessible.name, screen.finishButton.text)
        verify(screen.backButton.Accessible.role === Accessible.Button)
        compare(screen.backButton.Accessible.name, screen.backButton.text)
        verify(screen.missionHubButton.Accessible.role === Accessible.Button)
        compare(screen.missionHubButton.Accessible.name, "Open Mission Hub")
        verify(screen.settingsButton.Accessible.role === Accessible.Button)
        compare(screen.settingsButton.Accessible.name, "Open Settings")
        verify(screen.documentationButton.Accessible.role === Accessible.Button)
        compare(screen.documentationButton.Accessible.name, "Open Documentation")
        verify(screen.retryButton.Accessible.role === Accessible.Button)
        compare(screen.retryButton.Accessible.name, "Retry")

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

        // 640–759px band: neither compact nor wide — help panel hidden
        // (the 760px help-panel breakpoint), dots sized for the band
        var mid = createScreenAt(700, 768)
        verify(!mid.wideLayout, "700px is below the 760px help-panel breakpoint")
        verify(!mid.compactLayout, "700px is above the 640px compact breakpoint")
        verify(!mid.helpPanel.visible, "help panel collapses below 760px")
        mid.destroy()

        // Exactly at the compact boundary: 640px is not compact
        var at640 = createScreenAt(640, 768)
        verify(!at640.compactLayout, "640px is not compact (<640)")
        verify(!at640.wideLayout, "640px is not wide (≥760)")
        verify(!at640.helpPanel.visible)
        at640.destroy()

        // Exactly at the wide boundary: 760px is wide
        var at760 = createScreenAt(760, 768)
        verify(at760.wideLayout, "760px is wide (≥760)")
        verify(at760.helpPanel.visible)
        at760.destroy()
    }

    // ── 1024×768 (implementation target): every status row renders
    //    in the viewport and every control is reachable ─────────────
    function test_usableAt1024x768() {
        var screen = createScreen() // 1024×768
        wait(100)
        for (var i = 0; i < 3; ++i) {
            var item = screen.statusList.itemAtIndex(i)
            verify(item !== null, "status row " + i + " must be instantiated")
            verify(item.height > 0, "status row " + i + " must render with positive height")
        }
        // The content fits the viewport at 1024×768 (heading + body +
        // three rows + open actions), so no scrolling is required and
        // every control is reachable without interaction.
        verify(screen.contentFlickable.contentHeight <= screen.contentFlickable.height,
               "content must fit the 1024×768 viewport (contentHeight=" +
               screen.contentFlickable.contentHeight + " viewport=" +
               screen.contentFlickable.height + ")")
        // The action bar (Back / Finish) is anchored to the bottom and
        // always visible within the window.
        verify(screen.backButton.visible)
        verify(screen.finishButton.visible)
        screen.destroy()
    }

    // ── 480×768 compact: screen usable, controls reachable ─────────
    function test_usableAt480x768() {
        var screen = createScreenAt(480, 768)
        wait(100)
        verify(screen.compactLayout)
        verify(!screen.helpPanel.visible)
        // The content column renders with positive height (scrollable
        // if ever needed) and all three status rows are present.
        verify(screen.contentFlickable.height > 0)
        verify(screen.contentColumn.height > 0)
        for (var i = 0; i < 3; ++i) {
            var item = screen.statusList.itemAtIndex(i)
            verify(item !== null, "status row " + i + " must be instantiated at 480×768")
            verify(item.height > 0)
        }
        // The action bar controls are always visible at the bottom.
        verify(screen.backButton.visible)
        verify(screen.finishButton.visible)
        verify(screen.finishButton.enabled)
        screen.destroy()
    }

    // ── Reduced motion does not break rendering ────────────────────
    function test_reducedMotion() {
        var screen = createScreen()
        screen.reducedMotion = true
        screen.screenState = "loading"
        verify(screen.loadingIndicator.visible)
        verify(!screen.finishButton.enabled)
        screen.screenState = "empty"
        verify(screen.finishButton.enabled)

        // Actions still work with reduced motion
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'finishRequested' }",
            screen, "sysRmSpy")
        spy.target = screen
        screen.finishButton.clicked()
        compare(spy.count, 1)

        screen.reducedMotion = false
        screen.destroy()
    }

    // ── 44px minimum touch targets on every action ─────────────────
    function test_touchTargets() {
        var screen = createScreen()
        verify(screen.finishButton.implicitHeight >= 44)
        verify(screen.backButton.implicitHeight >= 44)
        verify(screen.missionHubButton.implicitHeight >= 44)
        verify(screen.settingsButton.implicitHeight >= 44)
        verify(screen.documentationButton.implicitHeight >= 44)
        screen.screenState = "error"
        verify(screen.retryButton.implicitHeight >= 44)
        screen.destroy()
    }

    // ── Terminal screen: no Continue exists ────────────────────────
    // The reference defines Finish, not Continue, as the terminal
    // action of the first-boot experience ("After completion, the user
    // enters the Mission OS desktop.") — same interpretation as the
    // Completion terminal screen, which has no Continue either.
    function test_terminalScreenNoContinue() {
        var screen = createScreen()
        verify(typeof screen.continueButton === "undefined",
               "terminal screen must not expose a Continue button")
        // Finish is the only primary terminal action
        verify(screen.finishButton.visible)
        compare(screen.finishButton.text, "Finish")
        screen.destroy()
    }

    // ── MissionPage / MissionWindow integration ────────────────────
    function test_missionPageIntegration() {
        var page = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionPage { pageTitle: 'System Ready'; SystemReady { objectName: 'sysInPage' } }",
            root, "sysInPage")
        verify(page !== null)
        verify(page.data.length > 0)
        page.destroy()
    }

    function test_missionWindowIntegration() {
        var screen = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionWindow { width: 1024; height: 768; SystemReady { objectName: 'sysInWindow' } }",
            root, "sysInWindow")
        verify(screen !== null)
        verify(screen.width > 0)
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
