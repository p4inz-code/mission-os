// Mission OS — Installer Completion (MOS-INS-012) QtTest suite
//
// Runtime validation of the Completion screen. Follows the
// foundation smoke-test pattern (tests/tst_smoke.qml) and the
// MOS-INS-001→011 Installer suites (tests/tst_installer_welcome.qml …
// tst_installation.qml) per docs/engineering/TESTING_STRATEGY.md
// (QML → Qt Test / qmltestrunner).
//
// Coverage (only behaviors required by the authoritative sources —
// reference § "Screen 15 — Installation Complete", registry MOS-INS-012):
//   - screen loads without QML errors (token singletons resolve)
//   - default state: step 13 of 17, the four completion details match
//     the reference display items 2–5 exactly (Installed version,
//     Build channel, Installation duration, Disk usage summary) with
//     neutral host-fed placeholders, and "Installation successful" is
//     the heading (display item 1)
//   - no spurious action signals on load — the completion screen emits
//     nothing during initialization (host-driven; all six signals stay
//     silent until a user action)
//   - host wiring: setDetailValue() updates a detail, the rendered list
//     row reflects the new value, and unknown codes are ignored; the
//     version/channel rows always mirror the public properties so the
//     header and the summary can never drift apart
//   - all five reference actions fire from the right controls (Restart
//     now, Continue in Live Mode, View installation report, Export
//     installation log, Shut down) plus Retry in the error state
//   - required state transitions (empty/loading/error/success/offline)
//     including the loading indicator and the state banners
//   - state banners render with positive height (banner-height regression)
//   - media-removal warning: hidden by default, visible and rendered
//     with positive height when requiresMediaRemoval is true
//     (reference: "If installation media must be removed before reboot,
//     the user should receive a clear prompt.")
//   - keyboard navigation: all five action buttons (and error-state
//     Retry) are Tab stops; the read-only detail rows are NOT Tab stops
//     (no keyboard trap); Tab and Shift+Tab wrap through the chain
//   - Space activates every action button (QQC2 Button semantics; Enter
//     has no defined activation on this screen — no default button, and
//     the terminal screen defines no selectable list)
//   - terminal-screen behavior: no Back and no Continue exist (the
//     reference defines exactly the five completion actions), and
//     Escape has no mapping (no signal fires)
//   - accessibility roles/names (heading, detail list + items, buttons,
//     media-removal note)
//   - light/dark theme via MissionTheme
//   - responsive compact layout (help panel collapses)
//   - reduced motion does not break rendering
//   - 44px minimum touch targets on every action button
//   - MissionPage / MissionWindow integration introduces no runtime errors
//
// Run via qmltestrunner (see CMakeLists.txt CTest registration):
//   qmltestrunner -import <build>/src/libraries/ui/qml \
//                 -input src/libraries/ui/tests/tst_completion.qml
//
// Exit code: 0 = all checks passed; non-zero = failure (CI gate).

import QtQuick
import QtTest
import org.mission.ui 1.0

TestCase {
    id: root
    name: "Completion"

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
                     "    Completion { id: screen; width: " + width + "; height: " + height + "; " +
                     (extra || "") + " }\n" +
                     "}"
        var host = Qt.createQmlObject(source, root, "compHost")
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
        // Step context: Completion is installer step 13 of 17
        compare(screen.step, 13)
        compare(screen.totalSteps, 17)
        // The four detail rows exist (reference display items 2–5)
        compare(screen.completionDetailCount, 4)
        compare(screen.detailList.count, 4)
        verify(screen.detailList.height > 0, "detail list must render with positive height")
        // Terminal screen: every reference action is available and the
        // primary action (Restart now) carries the initial focus.
        verify(screen.restartButton.enabled)
        verify(screen.continueLiveButton.enabled)
        verify(screen.viewReportButton.enabled)
        verify(screen.exportLogButton.enabled)
        verify(screen.shutdownButton.enabled)
        compare(screen.restartButton.focus, true,
                "Restart now must hold the initial focus on the terminal screen")
        screen.destroy()
    }

    // ── The four completion details match the reference exactly ────
    // Reference § "Screen 15 — Installation Complete": "Display:
    // Installation successful, Installed version, Build channel,
    // Installation duration, Disk usage summary." Item 1 is the heading
    // (verified in test_authoritativeHeading); items 2–5 are the four
    // detail rows, verbatim — no item may be invented or omitted.
    function test_detailsMatchReference() {
        var screen = createScreen()
        var expected = [
            ["version",  "Installed version",     "0.1.0"],
            ["channel",  "Build channel",         "Nightly"],
            ["duration", "Installation duration", "—"],
            ["storage",  "Disk usage summary",    "—"]
        ]
        compare(screen.completionDetails.length, expected.length)
        for (var i = 0; i < expected.length; ++i) {
            compare(screen.completionDetails[i].code, expected[i][0],
                    "detail " + i + " code")
            compare(screen.completionDetails[i].label, expected[i][1],
                    "detail " + i + " label")
            compare(screen.completionDetails[i].value, expected[i][2],
                    "detail " + i + " value")
        }
        // detailIndex()/getDetail() resolve every detail code
        compare(screen.detailIndex("version"), 0)
        compare(screen.detailIndex("storage"), 3)
        compare(screen.detailIndex("nonexistent"), -1)
        compare(screen.getDetail("duration").label, "Installation duration")
        compare(screen.getDetail("nonexistent"), null)
        // detailRowHeight is the single source of truth for row sizing
        compare(screen.detailRowHeight, 44)
        screen.destroy()
    }

    // ── The heading is the reference display item 1 ────────────────
    // Reference § "Screen 15": "Display: Installation successful …"
    function test_authoritativeHeading() {
        var screen = createScreen()
        compare(screen.headingLabel.text, "Installation successful")
        screen.destroy()
    }

    // ── Defaults must not emit spurious signals ────────────────────
    // Regression guard: the completion screen is host-fed and emits
    // nothing during initialization — all six action signals must stay
    // at zero immediately after load and after the engine settles.
    function test_noSignalsOnLoad() {
        var source = "import QtQuick\n" +
                     "import QtTest\n" +
                     "import org.mission.ui 1.0\n" +
                     "Window {\n" +
                     "    width: 1024; height: 768; visible: true\n" +
                     "    property alias screen: screen\n" +
                     "    property alias spyRestart: spyRestart\n" +
                     "    property alias spyLive: spyLive\n" +
                     "    property alias spyView: spyView\n" +
                     "    property alias spyExport: spyExport\n" +
                     "    property alias spyShutdown: spyShutdown\n" +
                     "    property alias spyRetry: spyRetry\n" +
                     "    Completion { id: screen; width: 1024; height: 768\n" +
                     "        SignalSpy { id: spyRestart; signalName: 'restartRequested'; target: screen }\n" +
                     "        SignalSpy { id: spyLive;    signalName: 'continueLiveRequested'; target: screen }\n" +
                     "        SignalSpy { id: spyView;    signalName: 'viewReportRequested'; target: screen }\n" +
                     "        SignalSpy { id: spyExport;  signalName: 'exportLogRequested'; target: screen }\n" +
                     "        SignalSpy { id: spyShutdown; signalName: 'shutdownRequested'; target: screen }\n" +
                     "        SignalSpy { id: spyRetry;   signalName: 'retryRequested'; target: screen }\n" +
                     "    }\n" +
                     "}\n"
        var host = Qt.createQmlObject(source, root, "compLoadHost")
        _hostWindows.push(host)
        compare(host.spyRestart.count, 0)
        compare(host.spyLive.count, 0)
        compare(host.spyView.count, 0)
        compare(host.spyExport.count, 0)
        compare(host.spyShutdown.count, 0)
        compare(host.spyRetry.count, 0)
        // Let the engine settle — still nothing may fire.
        wait(80)
        compare(host.spyRestart.count, 0)
        compare(host.spyLive.count, 0)
        compare(host.spyView.count, 0)
        compare(host.spyExport.count, 0)
        compare(host.spyShutdown.count, 0)
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

    // ── Host wiring: setDetailValue updates data + rendered row ────
    // The host feeds the real installation duration and disk usage
    // summary into the completion screen; each call updates the detail,
    // notifies the list, and the rendered row reflects the new value
    // (genuine behavior — the screen must display the real values per
    // reference § "Screen 15").
    function test_setDetailValueUpdates() {
        var screen = createScreen()
        compare(screen.getDetail("duration").value, "—")

        // Host wires the real installation duration
        screen.setDetailValue("duration", "About 15 minutes")
        compare(screen.getDetail("duration").value, "About 15 minutes")

        // Host wires the real disk usage summary
        screen.setDetailValue("storage", "About 12 GB used of 256 GB")
        compare(screen.getDetail("storage").value, "About 12 GB used of 256 GB")

        // Model intact
        compare(screen.completionDetailCount, 4)
        compare(screen.detailList.count, 4)

        // The rendered list rows reflect the new values
        wait(50) // let the model reset re-instantiate the visible rows
        var dur = screen.detailList.itemAtIndex(2)
        verify(dur !== null, "duration row delegate must be instantiated")
        compare(dur.objectName, "completionDetailItem2")
        compare(dur.valueLabel.text, "About 15 minutes")
        var stor = screen.detailList.itemAtIndex(3)
        verify(stor !== null, "storage row delegate must be instantiated")
        compare(stor.valueLabel.text, "About 12 GB used of 256 GB")

        // Data wiring emits no action signals (passive screen)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'restartRequested' }",
            screen, "compDataSpy")
        spy.target = screen
        screen.setDetailValue("duration", "About 16 minutes")
        compare(spy.count, 0)

        screen.destroy()
    }

    // ── Unknown detail codes are ignored (no invention) ────────────
    function test_setDetailUnknownCodeIgnored() {
        var screen = createScreen()
        screen.setDetailValue("nonexistent", "anything")
        compare(screen.getDetail("duration").value, "—")
        compare(screen.completionDetailCount, 4)
        screen.destroy()
    }

    // ── Version/channel rows mirror the public properties ──────────
    // The rendered version and channel rows always follow the public
    // `version`/`buildType` properties so the header and the summary can
    // never drift apart; the static fixture values are only defaults.
    function test_versionChannelRowsMirrorPublicProperties() {
        var screen = createScreen()
        wait(50) // let the visible rows instantiate
        var verRow = screen.detailList.itemAtIndex(0)
        var chanRow = screen.detailList.itemAtIndex(1)
        verify(verRow !== null && chanRow !== null)
        compare(verRow.valueLabel.text, "0.1.0")
        compare(chanRow.valueLabel.text, "Nightly")

        // Host updates the installed version → the row re-renders
        screen.version = "0.2.0"
        wait(50)
        compare(verRow.valueLabel.text, "0.2.0")

        // Host updates the build channel → the row re-renders
        screen.buildType = "Stable"
        wait(50)
        compare(chanRow.valueLabel.text, "Stable")

        // The static fixture values are untouched (mirroring only)
        compare(screen.completionDetails[0].value, "0.1.0")
        compare(screen.completionDetails[1].value, "Nightly")

        // Mirroring back to the fixture after a host change keeps the
        // rendered row in sync with the public property.
        screen.buildType = "Nightly"
        screen.version = "0.1.0"
        wait(50)
        compare(verRow.valueLabel.text, "0.1.0")
        compare(chanRow.valueLabel.text, "Nightly")

        screen.destroy()
    }

    // ── The five reference actions fire from the right controls ────
    function test_actionSignals() {
        var screen = createScreen()
        var spies = []
        var spyNames = ["restartRequested", "continueLiveRequested", "viewReportRequested",
                        "exportLogRequested", "shutdownRequested"]
        for (var i = 0; i < spyNames.length; ++i) {
            var spy = Qt.createQmlObject(
                "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: '" +
                spyNames[i] + "' }", screen, "compSpy" + i)
            spy.target = screen
            spies.push(spy)
        }

        screen.shutdownButton.clicked()
        compare(spies[4].count, 1)

        screen.continueLiveButton.clicked()
        compare(spies[1].count, 1)

        screen.restartButton.clicked()
        compare(spies[0].count, 1)

        screen.viewReportButton.clicked()
        compare(spies[2].count, 1)

        screen.exportLogButton.clicked()
        compare(spies[3].count, 1)

        // Error-state Retry → retryRequested
        var spyR = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'retryRequested' }",
            screen, "compSpyRetry")
        spyR.target = screen
        screen.screenState = "error"
        screen.retryButton.clicked()
        compare(spyR.count, 1)

        screen.destroy()
    }

    // ── Required state transitions ─────────────────────────────────
    function test_stateTransitions() {
        var screen = createScreen()
        // empty (default): no banner, no loading indicator
        verify(!screen.loadingIndicator.visible)
        verify(!screen.errorBanner.visible)
        verify(!screen.successBanner.visible)
        verify(!screen.offlineBanner.visible)

        // loading: loading indicator shown, no banners
        screen.screenState = "loading"
        verify(screen.loadingIndicator.visible)
        verify(!screen.errorBanner.visible)
        verify(!screen.successBanner.visible)
        verify(!screen.offlineBanner.visible)

        // error: error banner, no others
        screen.screenState = "error"
        verify(screen.errorBanner.visible)
        verify(!screen.loadingIndicator.visible)
        verify(!screen.successBanner.visible)
        verify(!screen.offlineBanner.visible)
        verify(screen.retryButton.visible)

        // success: success banner, no others
        screen.screenState = "success"
        verify(screen.successBanner.visible)
        verify(!screen.loadingIndicator.visible)
        verify(!screen.errorBanner.visible)
        verify(!screen.offlineBanner.visible)

        // offline: informational banner, no others
        screen.screenState = "offline"
        verify(screen.offlineBanner.visible)
        verify(!screen.loadingIndicator.visible)
        verify(!screen.errorBanner.visible)
        verify(!screen.successBanner.visible)

        // back to empty clears everything
        screen.screenState = "empty"
        verify(!screen.loadingIndicator.visible)
        verify(!screen.errorBanner.visible)
        verify(!screen.successBanner.visible)
        verify(!screen.offlineBanner.visible)

        // The five completion actions stay available in every state
        // (the completion screen only exists after a successful
        // installation; the reference does not gate the actions).
        screen.screenState = "error"
        verify(screen.restartButton.enabled)
        verify(screen.continueLiveButton.enabled)
        verify(screen.viewReportButton.enabled)
        verify(screen.exportLogButton.enabled)
        verify(screen.shutdownButton.enabled)

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

    // ── Media-removal warning ──────────────────────────────────────
    // Reference § "Screen 15": "If installation media must be removed
    // before reboot, the user should receive a clear prompt." Hidden by
    // default; visible and rendered when the host sets
    // requiresMediaRemoval.
    function test_mediaRemovalWarning() {
        var screen = createScreen()
        // Hidden by default (not installed from removable media)
        verify(!screen.mediaNote.visible)

        // Host declares removable-media installation → clear prompt
        screen.requiresMediaRemoval = true
        verify(screen.mediaNote.visible)
        verify(screen.mediaNote.height > 0,
               "media-removal note must render with positive height")
        compare(screen.mediaNote.Accessible.role, Accessible.Grouping)
        compare(screen.mediaNote.Accessible.name,
                "Remove the installation media before restarting")

        // Toggling back off hides it again (host-driven)
        screen.requiresMediaRemoval = false
        verify(!screen.mediaNote.visible)

        // The media note and the state banners are independent: a media
        // warning can coexist with the success state (both are valid on
        // the completion screen).
        screen.requiresMediaRemoval = true
        screen.screenState = "success"
        verify(screen.mediaNote.visible)
        verify(screen.successBanner.visible)
        verify(screen.mediaNote.height > 0)

        screen.destroy()
    }

    // ── Keyboard focus reaches the five actions ────────────────────
    // All five reference action buttons must be Tab stops; the
    // read-only detail rows are deliberately NOT Tab stops (no keyboard
    // trap — they convey information, they are not interactive).
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

        verify(found["completionRestart"], "focus must reach completionRestart")
        verify(found["completionContinueLive"], "focus must reach completionContinueLive")
        verify(found["completionViewReport"], "focus must reach completionViewReport")
        verify(found["completionExportLog"], "focus must reach completionExportLog")
        verify(found["completionShutdown"], "focus must reach completionShutdown")

        // Read-only detail rows must NOT be keyboard Tab stops.
        for (var row = 0; row < 4; ++row) {
            verify(!("completionDetailItem" + row in found),
                   "read-only detail row " + row + " must not be a Tab stop")
        }

        screen.destroy()
    }

    // ── Error state adds Retry to the focus chain ──────────────────
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
        verify(found["completionRetry"], "focus must reach completionRetry")
        verify(found["completionRestart"], "focus must still reach completionRestart")
        verify(found["completionShutdown"], "focus must still reach completionShutdown")
        screen.destroy()
    }

    // ── Tab and Shift+Tab wrap through the focus chain ─────────────
    // Every stop in the chain is one of the completion action buttons
    // (or Retry in the error state) — the chain never escapes into a
    // read-only row or a dead end.
    function test_tabWrapsBothDirections() {
        var screen = createScreen()
        wait(100)
        var hostWindow = _hostWindows[_hostWindows.length - 1]

        // Warm up the hosted window (first key event is consumed by
        // window activation on this build).
        screen.restartButton.forceActiveFocus()
        keyClick(Qt.Key_W)

        // Tab from the last stop wraps to another action button.
        screen.restartButton.forceActiveFocus()
        keyClick(Qt.Key_Tab)
        var focusItem = hostWindow.activeFocusItem
        verify(focusItem !== null && focusItem.objectName.indexOf("completion") === 0,
               "Tab from Restart must wrap to another action button, got: " +
               (focusItem ? focusItem.objectName : "none"))

        // Shift+Tab from that stop wraps backward to an action button.
        keyClick(Qt.Key_Backtab)
        focusItem = hostWindow.activeFocusItem
        verify(focusItem !== null && focusItem.objectName.indexOf("completion") === 0,
               "Shift+Tab must wrap to another action button, got: " +
               (focusItem ? focusItem.objectName : "none"))

        screen.destroy()
    }

    // ── Space activates every action button ────────────────────────
    // QQC2 Buttons activate on Space. Enter is not exercised: the
    // authoritative sources define no default button and nothing
    // selectable on this screen, so Enter has no defined activation
    // here (same interpretation as MOS-INS-011).
    function test_spaceActivationOnButtons() {
        var screen = createScreen()
        wait(100)

        // Warm up the hosted window (first key event is consumed by
        // window activation on this build — the established pattern).
        screen.restartButton.forceActiveFocus()
        keyClick(Qt.Key_W)

        var spies = []
        var spyNames = ["restartRequested", "continueLiveRequested", "viewReportRequested",
                        "exportLogRequested", "shutdownRequested"]
        for (var i = 0; i < spyNames.length; ++i) {
            var spy = Qt.createQmlObject(
                "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: '" +
                spyNames[i] + "' }", screen, "compKeySpy" + i)
            spy.target = screen
            spies.push(spy)
        }

        // Shut down via Space → shutdownRequested
        screen.shutdownButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spies[4].count, 1)

        // Continue in Live Mode via Space → continueLiveRequested
        screen.continueLiveButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spies[1].count, 1)

        // View installation report via Space → viewReportRequested
        screen.viewReportButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spies[2].count, 1)

        // Export installation log via Space → exportLogRequested
        screen.exportLogButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spies[3].count, 1)

        // Restart now via Space → restartRequested
        screen.restartButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spies[0].count, 1)

        // Error-state Retry via Space → retryRequested
        var spyR = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'retryRequested' }",
            screen, "compKeySpyR")
        spyR.target = screen
        screen.screenState = "error"
        screen.retryButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spyR.count, 1)

        screen.destroy()
    }

    // ── Terminal screen: no Back, no Continue, no Escape mapping ───
    // The reference defines exactly the five completion actions for
    // Screen 15; the wireframe's generic "Back / Continue" shell layout
    // is a template, and backing out of a finished installation is
    // meaningless. Therefore no Back or Continue control exists, and
    // Escape has no mapping on this screen — the host controls the exit
    // paths through the five actions.
    function test_terminalScreenNoBackNoEscape() {
        var screen = createScreen()
        // No Back and no Continue controls exist at all (not merely
        // hidden) — the completion screen is the terminal installer step.
        verify(typeof screen.backButton === "undefined",
               "terminal screen must not expose a Back button")
        verify(typeof screen.continueButton === "undefined",
               "terminal screen must not expose a Continue button")

        wait(100)
        var spies = []
        var spyNames = ["restartRequested", "continueLiveRequested", "viewReportRequested",
                        "exportLogRequested", "shutdownRequested", "retryRequested"]
        for (var i = 0; i < spyNames.length; ++i) {
            var spy = Qt.createQmlObject(
                "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: '" +
                spyNames[i] + "' }", screen, "compEscSpy" + i)
            spy.target = screen
            spies.push(spy)
        }

        // Warm up the hosted window (first key event is consumed by
        // window activation on this build).
        screen.restartButton.forceActiveFocus()
        keyClick(Qt.Key_W)

        // Escape on the terminal screen has no mapping: pressing it
        // repeatedly with a button focused must fire no signal at all.
        screen.restartButton.forceActiveFocus()
        keyClick(Qt.Key_Escape)
        keyClick(Qt.Key_Escape)
        keyClick(Qt.Key_Escape)
        for (var s = 0; s < spies.length; ++s)
            compare(spies[s].count, 0,
                    spyNames[s] + " must not fire on Escape (no Escape mapping)")

        // The five actions remain the only signals: pressing Space on
        // the focused Restart button still works after the Escape taps.
        keyClick(Qt.Key_Space)
        compare(spies[0].count, 1)

        screen.destroy()
    }

    // ── Accessibility roles / names ────────────────────────────────
    function test_accessibility() {
        var screen = createScreen()
        screen.screenState = "error"
        screen.requiresMediaRemoval = true

        // Heading is announced as a heading with a name
        verify(screen.headingLabel.Accessible.role === Accessible.Heading)
        compare(screen.headingLabel.Accessible.name, "Installation successful")

        // Detail list is a named list; its items are named list items
        // announcing exactly what is rendered (label: value).
        verify(screen.detailList.Accessible.role === Accessible.List)
        verify(screen.detailList.Accessible.name.length > 0)
        var item0 = screen.detailList.itemAtIndex(0)
        verify(item0.Accessible.role === Accessible.ListItem)
        compare(item0.Accessible.name, "Installed version: 0.1.0")

        // Every action button announces role + name
        verify(screen.restartButton.Accessible.role === Accessible.Button)
        compare(screen.restartButton.Accessible.name, screen.restartButton.text)
        verify(screen.continueLiveButton.Accessible.role === Accessible.Button)
        verify(screen.viewReportButton.Accessible.role === Accessible.Button)
        verify(screen.exportLogButton.Accessible.role === Accessible.Button)
        verify(screen.shutdownButton.Accessible.role === Accessible.Button)
        verify(screen.retryButton.Accessible.role === Accessible.Button)

        // Media-removal note announces its grouping + name
        compare(screen.mediaNote.Accessible.role, Accessible.Grouping)
        compare(screen.mediaNote.Accessible.name,
                "Remove the installation media before restarting")

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

        // Compact error state: the banner must still render with
        // positive height and never overflow the content column width.
        compact.screenState = "error"
        verify(compact.errorBanner.visible)
        verify(compact.errorBanner.height > 0,
               "compact error banner must render with positive height")
        verify(compact.errorBanner.width <= compact.contentColumn.width)
        verify(compact.retryButton.visible)

        // Compact media-removal note must render with positive height
        compact.requiresMediaRemoval = true
        verify(compact.mediaNote.visible)
        verify(compact.mediaNote.height > 0,
               "compact media-removal note must render with positive height")
        compact.destroy()
    }

    // ── 44px minimum touch targets ─────────────────────────────────
    // Every actionable control must meet the 44px minimum touch target
    // (Spacing.minimumTouchTarget; design-system rule carried by
    // MissionButton) so the completion screen is usable by touch.
    function test_minimumTouchTargets() {
        var screen = createScreen()
        var minTarget = Spacing.minimumTouchTarget
        verify(minTarget >= 44)
        var buttons = [screen.restartButton, screen.continueLiveButton,
                       screen.viewReportButton, screen.exportLogButton,
                       screen.shutdownButton]
        for (var i = 0; i < buttons.length; ++i) {
            verify(buttons[i].implicitHeight >= minTarget,
                   "action button " + i + " must be at least " + minTarget + "px tall")
        }
        screen.screenState = "error"
        verify(screen.retryButton.implicitHeight >= minTarget,
               "retry button must be at least " + minTarget + "px tall")
        screen.destroy()
    }

    // ── MissionPage / MissionWindow integration ────────────────────
    function test_missionPageIntegration() {
        var page = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionPage { pageTitle: 'Installer'; Completion { objectName: 'compInPage' } }",
            root, "compInPage")
        verify(page !== null)
        verify(page.data.length > 0)
        page.destroy()
    }

    function test_missionWindowIntegration() {
        var screen = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionWindow { width: 1024; height: 768; Completion { objectName: 'compInWindow' } }",
            root, "compInWindow")
        verify(screen !== null)
        verify(screen.width > 0)
        screen.destroy()
    }

    // ── Reduced motion does not break rendering ────────────────────
    function test_reducedMotion() {
        var screen = createScreen()
        screen.reducedMotion = true

        // Loading indicator still renders (the fill animation is gated
        // off, but the indicator itself stays visible)
        screen.screenState = "loading"
        verify(screen.loadingIndicator.visible)
        verify(screen.loadingIndicator.height > 0)

        // Host wiring still works with reduced motion
        screen.setDetailValue("storage", "About 12 GB used of 256 GB")
        compare(screen.getDetail("storage").value, "About 12 GB used of 256 GB")

        // Error banner still renders with reduced motion
        screen.screenState = "error"
        verify(screen.errorBanner.visible)
        verify(screen.errorBanner.height > 0)
        verify(screen.retryButton.visible)

        // Media note still renders with reduced motion
        screen.requiresMediaRemoval = true
        verify(screen.mediaNote.visible)
        verify(screen.mediaNote.height > 0)

        // The five actions remain enabled
        verify(screen.restartButton.enabled)
        verify(screen.shutdownButton.enabled)

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
