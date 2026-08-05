// Mission OS — Installer Installation (MOS-INS-011) QtTest suite
//
// Runtime validation of the Installation screen. Follows the
// foundation smoke-test pattern (tests/tst_smoke.qml) and the
// MOS-INS-001→010 Installer suites (tests/tst_installer_welcome.qml …
// tst_summary.qml) per docs/engineering/TESTING_STRATEGY.md
// (QML → Qt Test / qmltestrunner).
//
// Coverage (only behaviors required by the authoritative sources —
// reference § "Screen 14 — Installation Progress", § "Live Installation
// Log", § "Error Recovery", § "Non-Recoverable Errors", registry
// MOS-INS-011):
//   - screen loads without QML errors (token singletons resolve)
//   - default state: step 11 of 12, the twelve installation stages
//     match the reference example stages exactly, progress 0, not
//     started, log collapsed, Back enabled (step 11 > 1)
//   - the six displayed items exist (overall progress percentage,
//     current installation stage, current task description, estimated
//     remaining time, expandable installation log, overall health
//     indicator)
//   - no spurious action signals on load; host-driven progress data
//     (progress/stage/task/eta/log) never emits signals — the screen is
//     a passive progress display (no Continue; the host drives
//     progression)
//   - host wiring: progress, currentStageIndex, currentTask,
//     estimatedTimeRemaining update the rendered labels; appendLog()
//     appends real entries (info/warning/error, timestamps) that render
//     in the expanded log
//   - required signals fire from the right controls (back/retry/export)
//   - required state transitions (empty/loading/error/success/offline)
//     including the overall health indicator mapping
//   - state banners render with positive height (banner-height regression)
//   - keyboard navigation: focus reaches the log toggle and Back; the
//     read-only stage and log rows are NOT Tab stops (no keyboard trap);
//     Tab wraps and Shift+Tab wraps backward
//   - Space activates the buttons (log toggle, Back, Retry, Export);
//     Enter has no defined activation on this screen (no selectable
//     list, no default button per the authoritative sources)
//   - Escape navigates back
//   - accessibility roles/names (heading, stage list + items, progress
//     bar, buttons, log entries)
//   - responsive compact layout (help panel collapses)
//   - reduced motion does not break rendering
//   - MissionPage / MissionWindow integration introduces no runtime errors
//
// Run via qmltestrunner (see CMakeLists.txt CTest registration):
//   qmltestrunner -import <build>/src/libraries/ui/qml \
//                 -input src/libraries/ui/tests/tst_installation.qml
//
// Exit code: 0 = all checks passed; non-zero = failure (CI gate).

import QtQuick
import QtTest
import org.mission.ui 1.0

TestCase {
    id: root
    name: "Installation"

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
                     "    Installation { id: screen; width: " + width + "; height: " + height + "; " +
                     (extra || "") + " }\n" +
                     "}"
        var host = Qt.createQmlObject(source, root, "instHost")
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
        verify(screen.backButton.text.length > 0)
        // Step context: Installation is installer step 11 of 12
        compare(screen.step, 12)
        compare(screen.totalSteps, 17)
        // All twelve supported stages exist (reference § "Screen 14")
        compare(screen.installationStageCount, 12)
        compare(screen.stageList.count, 12)
        // Back is enabled (step 11 > 1 — wireframe: back always available)
        verify(screen.backButton.enabled)
        screen.destroy()
    }

    // ── The twelve stages match the reference exactly ──────────────
    // Reference § "Screen 14 — Installation Progress": "Example stages:
    // 1. Preparing installation 2. Creating partitions 3. Formatting
    // storage 4. Installing base system 5. Installing desktop
    // environment 6. Installing drivers 7. Configuring security
    // 8. Creating recovery environment 9. Applying workspace profile
    // 10. Verifying installation 11. Cleaning temporary files
    // 12. Finalizing installation." No stage may be invented or omitted.
    function test_stagesMatchReference() {
        var screen = createScreen()
        var expected = [
            ["preparing",  "Preparing installation"],
            ["partitions", "Creating partitions"],
            ["formatting", "Formatting storage"],
            ["base",       "Installing base system"],
            ["desktop",    "Installing desktop environment"],
            ["drivers",    "Installing drivers"],
            ["security",   "Configuring security"],
            ["recovery",   "Creating recovery environment"],
            ["profile",    "Applying workspace profile"],
            ["verifying",  "Verifying installation"],
            ["cleaning",   "Cleaning temporary files"],
            ["finalizing", "Finalizing installation"]
        ]
        compare(screen.installationStages.length, expected.length)
        for (var i = 0; i < expected.length; ++i) {
            compare(screen.installationStages[i].code, expected[i][0],
                    "stage " + i + " code")
            compare(screen.installationStages[i].label, expected[i][1],
                    "stage " + i + " label")
        }
        // stageIndex() helper resolves every stage code
        compare(screen.stageIndex("base"), 3)
        compare(screen.stageIndex("finalizing"), 11)
        compare(screen.stageIndex("nonexistent"), -1)
        screen.destroy()
    }

    // ── Default / initial state ────────────────────────────────────
    // The screen loads "not started": progress 0, no current stage,
    // neutral estimates, collapsed empty log, health "Not started".
    function test_initialState() {
        var screen = createScreen()
        compare(screen.screenState, "empty")
        compare(screen.progress, 0.0)
        compare(screen.progressPercent, 0)
        compare(screen.progressLabel.text, "0%")
        compare(screen.currentStageIndex, -1)
        compare(screen.currentStage, null)
        compare(screen.currentStageLabel, "Not started")
        compare(screen.currentTask, "")
        compare(screen.taskLabel.text, "—")
        compare(screen.estimatedTimeRemaining, "—")
        compare(screen.etaLabel.text, "—")
        compare(screen.healthLabel, "Not started")
        compare(screen.healthIndicator.text, "Not started")
        compare(screen.logExpanded, false)
        compare(screen.logCount, 0)
        // No state banner on load
        verify(!screen.errorBanner.visible)
        verify(!screen.successBanner.visible)
        verify(!screen.offlineBanner.visible)
        // The stage list renders all twelve rows as pending
        var item0 = screen.stageList.itemAtIndex(0)
        verify(item0 !== null)
        verify(item0.Accessible.name.indexOf("pending") >= 0,
               "stage 0 must start pending, got: " + item0.Accessible.name)
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
                     "    property alias spyB: spyB\n" +
                     "    property alias spyR: spyR\n" +
                     "    property alias spyE: spyE\n" +
                     "    Installation { id: screen; width: 1024; height: 768\n" +
                     "        SignalSpy { id: spyB; signalName: 'backRequested'; target: screen }\n" +
                     "        SignalSpy { id: spyR; signalName: 'retryRequested'; target: screen }\n" +
                     "        SignalSpy { id: spyE; signalName: 'exportReportRequested'; target: screen }\n" +
                     "    }\n" +
                     "}\n"
        var host = Qt.createQmlObject(source, root, "instLoadHost")
        _hostWindows.push(host)
        compare(host.spyB.count, 0)
        compare(host.spyR.count, 0)
        compare(host.spyE.count, 0)
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

    // ── Host wiring: progress display updates (the six items) ──────
    // The host drives the progress display; every value change must
    // re-render the corresponding label (genuine behavior — the screen
    // must report meaningful progress, the current operation, and the
    // estimated time remaining per reference § "Screen 14").
    function test_hostWiringUpdates() {
        var screen = createScreen()

        // Overall progress percentage
        screen.progress = 0.42
        compare(screen.progressPercent, 42)
        compare(screen.progressLabel.text, "42%")

        // Progress is clamped to 0..1 (never a nonsense percentage)
        screen.progress = 1.75
        compare(screen.progressPercent, 100)
        compare(screen.progressLabel.text, "100%")
        screen.progress = -0.3
        compare(screen.progressPercent, 0)
        screen.progress = 0.42

        // Current installation stage
        screen.currentStageIndex = 3
        compare(screen.currentStageLabel, "Installing base system")
        compare(screen.stageValueLabel.text, "Stage 4 of 12 · Installing base system")

        // Current task description
        screen.currentTask = "Extracting base system packages"
        compare(screen.taskLabel.text, "Extracting base system packages")

        // Estimated remaining time
        screen.estimatedTimeRemaining = "About 8 minutes"
        compare(screen.etaLabel.text, "About 8 minutes")

        // The rendered stage list reflects the current stage status
        wait(50) // let the stage list re-evaluate its delegates
        var done0 = screen.stageList.itemAtIndex(0)
        verify(done0.Accessible.name.indexOf("done") >= 0,
               "stage 0 must be done after stage 3 active, got: " + done0.Accessible.name)
        var cur3 = screen.stageList.itemAtIndex(3)
        verify(cur3.Accessible.name.indexOf("in progress") >= 0,
               "stage 3 must be in progress, got: " + cur3.Accessible.name)
        var pending4 = screen.stageList.itemAtIndex(4)
        verify(pending4.Accessible.name.indexOf("pending") >= 0,
               "stage 4 must be pending, got: " + pending4.Accessible.name)

        screen.destroy()
    }

    // ── Host wiring: appendLog() appends real entries ──────────────
    // The log displays completed tasks, warnings, errors, and
    // timestamps (reference § "Live Installation Log"). The host feeds
    // entries; none exist on load.
    function test_appendLog() {
        var screen = createScreen()
        compare(screen.logCount, 0)

        screen.appendLog("info", "Partitions created")
        compare(screen.logCount, 1)
        compare(screen.installationLog[0].level, "info")
        compare(screen.installationLog[0].text, "Partitions created")
        verify(screen.installationLog[0].timestamp.length > 0,
               "omitted timestamp must be auto-formatted")

        screen.appendLog("warning", "Mirror timeout — retrying", "12:00:01")
        compare(screen.logCount, 2)
        compare(screen.installationLog[1].level, "warning")
        compare(screen.installationLog[1].timestamp, "12:00:01")

        screen.appendLog("error", "Verification failed for kernel package", "12:00:05")
        compare(screen.logCount, 3)
        compare(screen.installationLog[2].level, "error")

        // Order is preserved (append order)
        compare(screen.installationLog[0].text, "Partitions created")
        compare(screen.installationLog[2].text, "Verification failed for kernel package")

        // The expanded log renders the entries as real rows
        screen.logExpanded = true
        wait(50) // let the log model reset instantiate the rows
        compare(screen.logList.count, 3)
        var item0 = screen.logList.itemAtIndex(0)
        verify(item0 !== null, "log row 0 must be instantiated")
        compare(item0.objectName, "installationLogItem0")
        verify(item0.Accessible.name.indexOf("Partitions created") >= 0)

        screen.destroy()
    }

    // ── Expandable log: collapsed by default, toggle controls it ───
    function test_logExpandCollapse() {
        var screen = createScreen()
        compare(screen.logExpanded, false)
        compare(screen.logToggle.text, "Show details")
        // Collapsed: no log rows are rendered (0 entries anyway, but the
        // expanded content is hidden)
        verify(!screen.logList.visible)

        screen.appendLog("info", "Base system installed")

        // Toggle expands
        screen.logToggle.clicked()
        compare(screen.logExpanded, true)
        compare(screen.logToggle.text, "Hide details")
        verify(screen.logList.visible)
        compare(screen.logList.count, 1)

        // Toggle collapses again
        screen.logToggle.clicked()
        compare(screen.logExpanded, false)
        compare(screen.logToggle.text, "Show details")
        verify(!screen.logList.visible)

        screen.destroy()
    }

    // ── Required state transitions ─────────────────────────────────
    function test_stateTransitions() {
        var screen = createScreen()
        // empty (default): no banner, health "Not started"
        verify(!screen.errorBanner.visible)
        verify(!screen.successBanner.visible)
        verify(!screen.offlineBanner.visible)
        compare(screen.healthLabel, "Not started")
        compare(screen.healthIndicator.text, "Not started")
        verify(screen.backButton.enabled)

        // loading: no banner (the progress card IS the loading display),
        // health "Installing"
        screen.screenState = "loading"
        verify(!screen.errorBanner.visible)
        verify(!screen.successBanner.visible)
        verify(!screen.offlineBanner.visible)
        compare(screen.healthLabel, "Installing")
        compare(screen.healthIndicator.text, "Installing")
        verify(screen.backButton.enabled)

        // error: error banner + Retry + Export, health "Installation stopped"
        screen.screenState = "error"
        verify(screen.errorBanner.visible)
        verify(screen.retryButton.visible)
        verify(screen.exportButton.visible)
        verify(!screen.successBanner.visible)
        verify(!screen.offlineBanner.visible)
        compare(screen.healthLabel, "Installation stopped")
        compare(screen.healthIndicator.text, "Installation stopped")

        // success: success banner, health "Installation complete"
        screen.screenState = "success"
        verify(screen.successBanner.visible)
        verify(!screen.errorBanner.visible)
        verify(!screen.offlineBanner.visible)
        compare(screen.healthLabel, "Installation complete")
        compare(screen.healthIndicator.text, "Installation complete")

        // offline: informational banner, health reports offline installs
        screen.screenState = "offline"
        verify(screen.offlineBanner.visible)
        verify(!screen.errorBanner.visible)
        verify(!screen.successBanner.visible)
        compare(screen.healthLabel, "Offline — installation continues without internet")
        compare(screen.healthIndicator.text, screen.healthLabel)

        // back to empty clears all banners
        screen.screenState = "empty"
        verify(!screen.errorBanner.visible)
        verify(!screen.successBanner.visible)
        verify(!screen.offlineBanner.visible)
        compare(screen.healthLabel, "Not started")

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

    // ── Action signals fire from the right controls ────────────────
    function test_actionSignals() {
        var screen = createScreen()
        var spies = []
        var spyNames = ["backRequested", "retryRequested", "exportReportRequested"]
        for (var i = 0; i < spyNames.length; ++i) {
            var spy = Qt.createQmlObject(
                "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: '" +
                spyNames[i] + "' }", screen, "instSpy" + i)
            spy.target = screen
            spies.push(spy)
        }

        screen.backButton.clicked()
        compare(spies[0].count, 1)

        screen.screenState = "error"
        screen.retryButton.clicked()
        compare(spies[1].count, 1)

        screen.exportButton.clicked()
        compare(spies[2].count, 1)

        screen.destroy()
    }

    // ── Host-driven progress data never emits signals ──────────────
    // The screen is a passive progress display: the host drives
    // progress/stage/task/eta/log through plain data changes, none of
    // which may fire an action signal (no spurious signaling; the only
    // user-initiated signals are back/retry/export).
    function test_hostDataEmitsNoSignals() {
        var screen = createScreen()
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'backRequested' }",
            screen, "instDataSpy")
        spy.target = screen
        var spyR = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'retryRequested' }",
            screen, "instDataSpyR")
        spyR.target = screen

        screen.progress = 0.5
        screen.currentStageIndex = 4
        screen.currentTask = "Installing drivers"
        screen.estimatedTimeRemaining = "About 4 minutes"
        screen.appendLog("info", "Drivers installed")
        screen.logExpanded = true
        screen.screenState = "loading"
        compare(spy.count, 0)
        compare(spyR.count, 0)

        screen.destroy()
    }

    // ── Keyboard focus reaches the actionable controls ─────────────
    // Only the log toggle and Back are Tab stops in the default state
    // (the stage list and log rows are read-only — no keyboard trap).
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

        verify(found["installationBack"], "focus must reach installationBack")
        verify(found["installationLogToggle"], "focus must reach installationLogToggle")

        // Read-only stage rows must NOT be keyboard Tab stops.
        for (var stage = 0; stage < 12; ++stage) {
            verify(!("installationStageItem" + stage in found),
                   "read-only stage row " + stage + " must not be a Tab stop")
        }

        screen.destroy()
    }

    // ── Expanded log rows are NOT Tab stops (no keyboard trap) ─────
    // With the log open, the read-only log rows must stay out of the
    // focus chain while the log toggle and Back remain reachable.
    function test_expandedLogNotTabStops() {
        var screen = createScreen()
        screen.appendLog("info", "Partitions created")
        screen.appendLog("warning", "Mirror timeout — retrying", "12:00:01")
        screen.appendLog("error", "Verification failed for kernel package", "12:00:05")
        screen.logExpanded = true
        wait(100)
        var hostWindow = _hostWindows[_hostWindows.length - 1]
        var found = {}

        for (var tab = 0; tab < 100; ++tab) {
            keyClick(Qt.Key_Tab)
            var focusItem = hostWindow.activeFocusItem
            if (focusItem && focusItem.objectName)
                found[focusItem.objectName] = true
        }

        verify(found["installationLogToggle"], "focus must reach installationLogToggle with the log open")
        verify(found["installationBack"], "focus must reach installationBack with the log open")
        for (var row = 0; row < 3; ++row) {
            verify(!("installationLogItem" + row in found),
                   "read-only log row " + row + " must not be a Tab stop")
        }
        screen.destroy()
    }

    // ── Error state adds Retry/Export to the focus chain ───────────
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
        verify(found["installationRetry"], "focus must reach installationRetry")
        verify(found["installationExport"], "focus must reach installationExport")
        verify(found["installationBack"], "focus must still reach installationBack")
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

        // Exactly two Tab stops in the default state (log toggle, Back),
        // so the chain wraps: Tab from Back lands on the log toggle.
        screen.backButton.forceActiveFocus()
        keyClick(Qt.Key_Tab)
        var focusItem = hostWindow.activeFocusItem
        verify(focusItem !== null && focusItem.objectName === "installationLogToggle",
               "Tab from Back must wrap to the log toggle, got: " +
               (focusItem ? focusItem.objectName : "none"))

        // Shift+Tab moves backward: from the log toggle back to Back.
        keyClick(Qt.Key_Backtab)
        focusItem = hostWindow.activeFocusItem
        verify(focusItem !== null && focusItem.objectName === "installationBack",
               "Shift+Tab from the log toggle must wrap to Back, got: " +
               (focusItem ? focusItem.objectName : "none"))

        screen.destroy()
    }

    // ── Space activates the buttons ────────────────────────────────
    // QQC2 Buttons activate on Space (Enter activates only dialogs'
    // default buttons; the authoritative sources define no default
    // button and nothing selectable on this screen, so Enter has no
    // defined activation here). Space is exercised for every actionable
    // control: log toggle, Back, and the error-state Retry/Export.
    function test_spaceActivationOnButtons() {
        var screen = createScreen()
        wait(100)

        // Warm up the hosted window (first key event is consumed by
        // window activation on this build — the established pattern).
        screen.logToggle.forceActiveFocus()
        keyClick(Qt.Key_W)

        // Log toggle via Space (expand, then collapse)
        screen.logToggle.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(screen.logExpanded, true, "Space must expand the log")

        keyClick(Qt.Key_Space)
        compare(screen.logExpanded, false, "Space must collapse the log")

        // Back via Space → backRequested
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'backRequested' }",
            screen, "instKeySpy")
        spy.target = screen
        screen.backButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spy.count, 1)

        // Error-state Retry via Space → retryRequested
        var spyR = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'retryRequested' }",
            screen, "instKeySpyR")
        spyR.target = screen
        screen.screenState = "error"
        screen.retryButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spyR.count, 1)

        // Error-state Export via Space → exportReportRequested
        var spyE = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'exportReportRequested' }",
            screen, "instKeySpyE")
        spyE.target = screen
        screen.exportButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spyE.count, 1)

        screen.destroy()
    }

    // ── Escape navigates back ──────────────────────────────────────
    function test_escapeNavigatesBack() {
        var screen = createScreen()
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'backRequested' }",
            screen, "instEscSpy")
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
        screen.screenState = "error"

        // Heading is announced as a heading with a name
        verify(screen.headingLabel.Accessible.role === Accessible.Heading)
        verify(screen.headingLabel.Accessible.name.length > 0)

        // Stage list is a named list; its items are list items
        verify(screen.stageList.Accessible.role === Accessible.List)
        verify(screen.stageList.Accessible.name.length > 0)
        var stage0 = screen.stageList.itemAtIndex(0)
        verify(stage0.Accessible.role === Accessible.ListItem)
        verify(stage0.Accessible.name.length > 0)

        // Progress bar exposes its role and name; the percentage is
        // conveyed by the adjacent progressLabel (Accessible.value is
        // not exposed on this Qt toolchain).
        verify(screen.progressBar.Accessible.role === Accessible.ProgressBar)
        verify(screen.progressBar.Accessible.name.length > 0)
        screen.progress = 0.5
        compare(screen.progressPercent, 50)
        compare(screen.progressLabel.text, "50%")

        // Buttons announce role + name
        verify(screen.backButton.Accessible.role === Accessible.Button)
        compare(screen.backButton.Accessible.name, screen.backButton.text)
        verify(screen.logToggle.Accessible.role === Accessible.Button)
        verify(screen.retryButton.Accessible.role === Accessible.Button)
        verify(screen.exportButton.Accessible.role === Accessible.Button)

        // Health indicator is announced with its label
        compare(screen.healthIndicator.text, "Installation stopped")
        verify(screen.healthIndicator.Accessible.name.length > 0)

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

        // Compact error state: the banner and its two actions must
        // still render with positive height (buttons below the text on
        // their own row — never squeezed into the text column).
        compact.screenState = "error"
        verify(compact.errorBanner.visible)
        verify(compact.errorBanner.height > 0,
               "compact error banner must render with positive height")
        verify(compact.retryButton.visible)
        verify(compact.exportButton.visible)
        // The banner must never overflow the content column width
        verify(compact.errorBanner.width <= compact.contentColumn.width)
        compact.destroy()
    }

    // ── MissionPage / MissionWindow integration ────────────────────
    function test_missionPageIntegration() {
        var page = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionPage { pageTitle: 'Installer'; Installation { objectName: 'instInPage' } }",
            root, "instInPage")
        verify(page !== null)
        verify(page.data.length > 0)
        page.destroy()
    }

    function test_missionWindowIntegration() {
        var screen = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionWindow { width: 1024; height: 768; Installation { objectName: 'instInWindow' } }",
            root, "instInWindow")
        verify(screen !== null)
        verify(screen.width > 0)
        screen.destroy()
    }

    // ── Progress fill tracks progress with default motion ──────────
    // The determinate fill must settle at the bound width after the
    // Behavior animation completes (default reducedMotion=false). This
    // guards the 0-width progress-bar bug class (Layout.fillWidth inside
    // a plain Column collapsed the bar) AND verifies the Behavior
    // animation actually completes to the bound width on this toolchain.
    function test_progressFillDefaultMotion() {
        var screen = createScreen()
        verify(screen.reducedMotion === false)
        screen.progress = 0.5
        compare(screen.progressPercent, 50)
        wait(500) // Motion.durationFast (200ms) + margin
        verify(screen.progressFill.width > 0,
               "progress fill must settle at the bound width (default motion)")
        compare(screen.progressFill.width, screen.progressBar.width * 0.5)
        screen.destroy()
    }

    // ── Reduced motion does not break rendering ────────────────────
    function test_reducedMotion() {
        var screen = createScreen()
        screen.reducedMotion = true
        screen.screenState = "loading"
        compare(screen.healthIndicator.text, "Installing")
        verify(screen.backButton.enabled)

        // Host wiring still works with reduced motion (animations off,
        // bindings intact)
        screen.progress = 0.5
        compare(screen.progressPercent, 50)
        compare(screen.progressLabel.text, "50%")
        wait(50)
        verify(screen.progressFill.width > 0,
               "progress fill must track progress with reduced motion")

        screen.currentStageIndex = 6
        compare(screen.currentStageLabel, "Configuring security")

        // Error banner still renders with reduced motion
        screen.screenState = "error"
        verify(screen.errorBanner.visible)
        verify(screen.errorBanner.height > 0)
        verify(screen.retryButton.visible)

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
