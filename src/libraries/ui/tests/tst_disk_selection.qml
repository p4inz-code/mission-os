// Mission OS — Installer Disk Selection (MOS-INS-006) QtTest suite
//
// Runtime validation of the Disk Selection screen. Follows the
// foundation smoke-test pattern (tests/tst_smoke.qml), the MOS-INS-001
// InstallerWelcome suite (tests/tst_installer_welcome.qml), the
// MOS-INS-002 Language suite (tests/tst_language.qml), the MOS-INS-003
// Keyboard suite (tests/tst_keyboard.qml), the MOS-INS-004 Network suite
// (tests/tst_network.qml) and the MOS-INS-005 Privacy suite
// (tests/tst_privacy_setup.qml) per docs/engineering/TESTING_STRATEGY.md
// (QML → Qt Test / qmltestrunner).
//
// Coverage:
//   - screen loads without QML errors (token singletons resolve)
//   - default values: no disk preselected on load (selectedDiskIndex -1)
//   - no spurious diskSelectionRequested signal on load
//   - full drive catalog is exposed with the Screen 06 fields (friendly
//     name, device, interface, health, operating systems, available)
//   - every disk emits its device name (nvme0n1/sda/sdb/sdc)
//   - required signals fire from the right controls (continue/back/retry)
//   - required state transitions (empty/loading/error/success/offline)
//   - state banners render with positive height (banner-height regression)
//   - Continue is blocked until a destination disk is selected and never
//     advances while loading/error
//   - keyboard focus reaches actionable controls in logical order;
//     arrows move the list, Enter/Space select
//   - Escape navigates back
//   - responsive compact layout (help panel collapses)
//   - reduced motion does not break rendering
//   - MissionPage / MissionWindow integration introduces no runtime errors
//
// Run via qmltestrunner (see CMakeLists.txt CTest registration):
//   qmltestrunner -import <build>/src/libraries/ui/qml \
//                 -input src/libraries/ui/tests/tst_disk_selection.qml
//
// Exit code: 0 = all checks passed; non-zero = failure (CI gate).

import QtQuick
import QtTest
import org.mission.ui 1.0

TestCase {
    id: root
    name: "DiskSelection"

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
                     "    DiskSelection { id: screen; width: " + width + "; height: " + height + "; " +
                     (extra || "") + " }\n" +
                     "}"
        var host = Qt.createQmlObject(source, root, "diskHost")
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
        // The full drive catalog must be populated (MOS-INS-006)
        compare(screen.diskOptions.length, 4)
        // Default values: no destination disk preselected on load
        compare(screen.selectedDiskIndex, -1)
        compare(screen.selectedDiskLabel, "")
        compare(screen.selectedDiskDevice, "")
        // Step context: Disk Selection is installer step 6 of 12
        compare(screen.step, 6)
        compare(screen.totalSteps, 17)
        screen.destroy()
    }

    // ── Defaults must not emit spurious disk signals ───────────────
    // Regression guard: no disk is preselected and no selection happens
    // during initialization, so no diskSelectionRequested may fire on
    // load (same contract as 002/003/004/005).
    function test_noSignalsOnLoad() {
        var source = "import QtQuick\n" +
                     "import QtTest\n" +
                     "import org.mission.ui 1.0\n" +
                     "Window {\n" +
                     "    width: 1024; height: 768; visible: true\n" +
                     "    property alias screen: screen\n" +
                     "    property alias spy: spy\n" +
                     "    DiskSelection { id: screen; width: 1024; height: 768\n" +
                     "        SignalSpy { id: spy; signalName: 'diskSelectionRequested'; target: screen }\n" +
                     "    }\n" +
                     "}\n"
        var host = Qt.createQmlObject(source, root, "diskLoadHost")
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
        verify(screen.diskList !== null)
        verify(screen.continueButton.visible)
        // Continue is disabled until a destination disk is chosen
        // (validation before continuing — no disk is ever auto-selected)
        verify(!screen.continueButton.enabled)
        // Back is enabled on step 6 (Disk Selection is the sixth step)
        verify(screen.backButton.enabled)
        // Continue is primary variant; Back is secondary
        compare(screen.continueButton.variant, MissionButton.Variant.Primary)
        compare(screen.backButton.variant, MissionButton.Variant.Secondary)
        screen.destroy()
    }

    // ── Drive catalog: codes + Screen 06 fields ────────────────────
    function test_diskCatalog() {
        var screen = createScreen()
        var expectedDevices = ["nvme0n1", "sda", "sdb", "sdc"]
        var expectedLabels = ["Samsung 990 Pro (2 TB)", "Seagate BarraCuda (1 TB)",
                              "SanDisk Ultra Fit (128 GB)", "WD Blue (512 GB)"]
        compare(screen.diskOptions.length, expectedDevices.length)
        for (var i = 0; i < screen.diskOptions.length; ++i) {
            compare(screen.diskOptions[i].device, expectedDevices[i])
            compare(screen.diskOptions[i].label, expectedLabels[i])
        }
        screen.destroy()
    }

    // ── Every drive exposes the reference Screen 06 display fields ──
    // friendly name, interface, health status, existing operating
    // systems, available space (device name is secondary info only).
    function test_diskFields() {
        var screen = createScreen()
        for (var i = 0; i < screen.diskOptions.length; ++i) {
            var disk = screen.diskOptions[i]
            verify(disk.label.length > 0, "disk " + i + " must have a friendly name")
            verify(disk.device.length > 0, "disk " + i + " must expose a device name")
            verify(disk.interface.length > 0, "disk " + i + " must state its interface")
            verify(disk.health.length > 0, "disk " + i + " must state its health status")
            verify(disk.os.length > 0, "disk " + i + " must state detected operating systems")
            verify(disk.available.length > 0, "disk " + i + " must state available space")
        }
        // Friendly names lead: no disk is identified by its device name alone
        verify(screen.diskOptions[0].label !== screen.diskOptions[0].device)
        screen.destroy()
    }

    // ── Every disk selection emits its device name ─────────────────
    function test_diskSelection() {
        var screen = createScreen()
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'diskSelectionRequested' }",
            screen, "diskSpy")
        spy.target = screen

        // Walk every drive entry: selection + emitted device must match
        for (var i = 0; i < screen.diskOptions.length; ++i) {
            screen.selectDisk(i)
            compare(screen.selectedDiskIndex, i)
            compare(screen.selectedDiskDevice, screen.diskOptions[i].device)
            compare(screen.selectedDiskLabel, screen.diskOptions[i].label)
            compare(spy.count, i + 1)
            compare(spy.signalArguments[spy.count - 1][0], screen.diskOptions[i].device)
        }

        // Out of range is ignored
        screen.selectDisk(999)
        compare(spy.count, screen.diskOptions.length)

        screen.destroy()
    }

    // ── Action signals fire from the right controls ────────────────
    // Continue is disabled until a disk is selected, so the disk must
    // be chosen before Continue can fire (real behavior, not object
    // existence).
    function test_actionSignals() {
        var screen = createScreen()
        var spies = []
        var spyNames = ["continueRequested", "backRequested", "retryRequested"]
        for (var i = 0; i < spyNames.length; ++i) {
            var spy = Qt.createQmlObject(
                "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: '" +
                spyNames[i] + "' }", screen, "diskSpy" + i)
            spy.target = screen
            spies.push(spy)
        }

        // Continue cannot fire before a destination disk is selected —
        // the button is disabled. (Calling Button.clicked() directly
        // emits the signal regardless of `enabled`; the disabled state
        // gates real user input, which test_continueBlocking verifies
        // with key events.)
        verify(!screen.continueButton.enabled)

        screen.selectDisk(0)
        verify(screen.continueButton.enabled)
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
        // empty (default): no banner, Continue disabled (no disk yet)
        verify(!screen.loadingIndicator.visible)
        verify(!screen.errorBanner.visible)
        verify(!screen.successBanner.visible)
        verify(!screen.offlineBanner.visible)
        verify(!screen.continueButton.enabled)

        // Select a destination disk → Continue becomes available
        screen.selectDisk(0)
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

        // success: success banner, Continue enabled (disk still chosen)
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

    // ── Continue must not advance until a disk is chosen, and never
    //    while loading/error ────────────────────────────────────────
    function test_continueBlocking() {
        var screen = createScreen()
        wait(100) // let the hosted window activate so key events reach it
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'continueRequested' }",
            screen, "diskContSpy")
        spy.target = screen

        // No destination disk: Continue disabled → no signal from
        // keyboard input (this first key press also absorbs the fresh
        // window's activation consumption on this build)
        verify(!screen.continueButton.enabled)
        screen.continueButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spy.count, 0)
        keyClick(Qt.Key_Return)
        compare(spy.count, 0)

        // Select a disk → Continue enabled → keyboard input advances
        screen.selectDisk(0)
        verify(screen.continueButton.enabled)
        screen.continueButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spy.count, 1)

        // Loading: Continue disabled → no signal
        screen.screenState = "loading"
        verify(!screen.continueButton.enabled)
        screen.continueButton.forceActiveFocus()
        keyClick(Qt.Key_Return)
        compare(spy.count, 1)

        // Error: Continue disabled → no signal
        screen.screenState = "error"
        verify(!screen.continueButton.enabled)
        screen.continueButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spy.count, 1)

        // Empty with a disk still chosen: Continue enabled again
        screen.screenState = "empty"
        verify(screen.continueButton.enabled)
        screen.continueButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spy.count, 2)

        screen.destroy()
    }

    // ── Keyboard focus reaches actionable controls ─────────────────
    // A disabled Control is not focusable, so Continue is skipped in
    // the Tab chain until a destination disk is selected — that is the
    // correct behavior for a validation-gated primary action.
    function test_keyboardFocus() {
        var screen = createScreen()
        wait(100) // let the hosted window activate so Tab reaches the controls
        var hostWindow = _hostWindows[_hostWindows.length - 1]

        // Before any disk is chosen: list + Back are reachable; the
        // disabled Continue is correctly absent from the focus chain
        // (disabled controls are skipped for keyboard and screen-reader
        // users).
        var found = {}
        for (var tab = 0; tab < 80; ++tab) {
            keyClick(Qt.Key_Tab)
            var focusItem = hostWindow.activeFocusItem
            if (focusItem && focusItem.objectName)
                found[focusItem.objectName] = true
        }
        verify(found["diskItem0"], "focus must reach diskItem0")
        verify(found["diskBack"], "focus must reach diskBack")
        verify(!found["diskContinue"], "disabled Continue must not take focus")

        // After choosing a disk, Continue is enabled and joins the
        // focus chain (real behavior — the walk wraps, so 80 presses
        // cover every control).
        screen.selectDisk(0)
        var foundEnabled = {}
        for (var t2 = 0; t2 < 80; ++t2) {
            keyClick(Qt.Key_Tab)
            var fi2 = hostWindow.activeFocusItem
            if (fi2 && fi2.objectName)
                foundEnabled[fi2.objectName] = true
        }
        verify(foundEnabled["diskContinue"],
               "focus must reach diskContinue after a disk is selected")

        screen.destroy()
    }

    // ── Arrow keys move the list; Enter/Space select ───────────────
    function test_listKeyboardSelection() {
        var screen = createScreen()
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'diskSelectionRequested' }",
            screen, "diskListSpy")
        spy.target = screen

        screen.diskList.forceActiveFocus()
        verify(screen.diskList.activeFocus)
        // Move from Samsung (0) to Seagate (1) with Down, then select
        keyClick(Qt.Key_Down)
        compare(screen.diskList.currentIndex, 1)
        keyClick(Qt.Key_Return)
        compare(screen.selectedDiskLabel, "Seagate BarraCuda (1 TB)")
        compare(screen.selectedDiskDevice, "sda")
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "sda")

        // Space also selects (SanDisk → sdb)
        keyClick(Qt.Key_Down)
        keyClick(Qt.Key_Space)
        compare(screen.selectedDiskLabel, "SanDisk Ultra Fit (128 GB)")
        compare(screen.selectedDiskDevice, "sdb")

        screen.destroy()
    }

    // ── Shift+Tab walks the focus chain backward ──────────────────
    function test_shiftTabNavigatesBackward() {
        var screen = createScreen()
        wait(100)
        screen.selectDisk(0) // Continue must be enabled to hold focus
        var hostWindow = _hostWindows[_hostWindows.length - 1]

        // Warm up the hosted window (first key event on a fresh window
        // is consumed by window activation on this build).
        screen.continueButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        screen.continueButton.forceActiveFocus()
        verify(screen.continueButton.activeFocus)

        // Backward walk: Continue → Back → disk list (current item 0)
        keyClick(Qt.Key_Tab, Qt.ShiftModifier)
        var item1 = hostWindow.activeFocusItem
        verify(item1 && item1.objectName === "diskBack",
               "Shift+Tab from Continue must reach Back, got " +
               (item1 ? item1.objectName : "null"))

        keyClick(Qt.Key_Tab, Qt.ShiftModifier)
        var item2 = hostWindow.activeFocusItem
        verify(item2 && item2.objectName === "diskItem0",
               "Shift+Tab from Back must reach the disk list, got " +
               (item2 ? item2.objectName : "null"))

        screen.destroy()
    }

    // ── Escape navigates back ──────────────────────────────────────
    function test_escapeNavigatesBack() {
        var screen = createScreen()
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'backRequested' }",
            screen, "diskEscSpy")
        spy.target = screen

        // Warm up the hosted window before asserting the real Escape
        // behavior: the first key event on a fresh window is consumed by
        // window activation on this build (verified empirically), so an
        // extra key is sent first to absorb that activation. The warm-up
        // Space lands on Continue (fires continueRequested, never
        // backRequested), keeping the backRequested count clean.
        screen.selectDisk(0)
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
            "import org.mission.ui 1.0; MissionPage { pageTitle: 'Installer'; DiskSelection { objectName: 'diskInPage' } }",
            root, "diskInPage")
        verify(page !== null)
        verify(page.data.length > 0)
        page.destroy()
    }

    function test_missionWindowIntegration() {
        var screen = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionWindow { width: 1024; height: 768; DiskSelection { objectName: 'diskInWindow' } }",
            root, "diskInWindow")
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
        verify(!screen.continueButton.enabled)
        // Selection + advance still work with reduced motion
        screen.selectDisk(0)
        verify(screen.continueButton.enabled)
        compare(screen.selectedDiskDevice, screen.diskOptions[0].device)
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
