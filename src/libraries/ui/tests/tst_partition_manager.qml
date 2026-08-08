// Mission OS — Installer Partition Manager (MOS-INS-007) QtTest suite
//
// Runtime validation of the Partition Manager screen. Follows the
// foundation smoke-test pattern (tests/tst_smoke.qml) and the
// MOS-INS-001 InstallerWelcome, MOS-INS-002 Language, MOS-INS-003
// Keyboard, MOS-INS-004 Network, MOS-INS-005 Privacy and MOS-INS-006
// Disk suites (tests/tst_installer_welcome.qml … tst_disk_selection.qml)
// per docs/engineering/TESTING_STRATEGY.md (QML → Qt Test /
// qmltestrunner).
//
// Coverage (only behaviors required by the authoritative sources —
// reference Screen 07 "Partition Review", registry MOS-INS-007):
//   - screen loads without QML errors (token singletons resolve)
//   - default state: review screen, Continue available (no selection
//     gate — this step reviews the plan the host provided)
//   - no spurious action signals on load (this screen has no host-change
//     signal at all: it reviews, it does not mutate)
//   - the full partition plan is exposed with every Screen 07 field
//     (existing partitions, proposed changes, filesystem, mount points,
//     boot partition, recovery partition)
//   - destructive actions are clearly highlighted (error container
//     background + "Destructive" marker, non-color indicator)
//   - boot and recovery role badges are correct
//   - required signals fire from the right controls (continue/back/retry)
//   - required state transitions (empty/loading/error/success/offline)
//   - Continue is blocked while loading/error (validation-before-continue)
//   - state banners render with positive height (banner-height regression)
//   - keyboard focus reaches the actionable controls; read-only plan
//     rows never take focus; Tab / Shift+Tab; Escape navigates back
//   - responsive compact layout (help panel collapses)
//   - reduced motion does not break rendering
//   - MissionPage / MissionWindow integration introduces no runtime errors
//
// Run via qmltestrunner (see CMakeLists.txt CTest registration):
//   qmltestrunner -import <build>/src/libraries/ui/qml \
//                 -input src/libraries/ui/tests/tst_partition_manager.qml
//
// Exit code: 0 = all checks passed; non-zero = failure (CI gate).

import QtQuick
import QtTest
import org.mission.ui 1.0

TestCase {
    id: root
    name: "PartitionManager"

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
                     "    PartitionManager { id: screen; width: " + width + "; height: " + height + "; " +
                     (extra || "") + " }\n" +
                     "}"
        var host = Qt.createQmlObject(source, root, "partHost")
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
        // Neutral default: no fabricated partition plan (FABRICATION-8);
        // the host provides partitionOptions.
        compare(screen.partitionCount, 0)
        compare(screen.destructiveCount, 0)
        // Step context: Partition Manager is installer step 7 of 12
        compare(screen.step, 7)
        compare(screen.totalSteps, 17)
        // Default state: review screen — Continue is available (nothing
        // on this screen gates it beyond loading/error)
        verify(screen.continueButton.enabled)
        screen.destroy()
    }

    // ── Defaults must not emit spurious signals ────────────────────
    // Regression guard: the review screen has no host-change signal and
    // performs no action during initialization, so no signal may fire on
    // load (same contract as 002/003/004/005/006).
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
                     "    PartitionManager { id: screen; width: 1024; height: 768\n" +
                     "        SignalSpy { id: spyC; signalName: 'continueRequested'; target: screen }\n" +
                     "        SignalSpy { id: spyB; signalName: 'backRequested'; target: screen }\n" +
                     "        SignalSpy { id: spyR; signalName: 'retryRequested'; target: screen }\n" +
                     "    }\n" +
                     "}\n"
        var host = Qt.createQmlObject(source, root, "partLoadHost")
        _hostWindows.push(host)
        compare(host.spyC.count, 0)
        compare(host.spyB.count, 0)
        compare(host.spyR.count, 0)
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
        verify(screen.partitionRows.count === 0)
        verify(screen.continueButton.visible)
        verify(screen.continueButton.enabled)
        // Back is enabled on step 7 (Partition Manager is the seventh step)
        verify(screen.backButton.enabled)
        // Continue is primary variant; Back is secondary
        compare(screen.continueButton.variant, MissionButton.Variant.Primary)
        compare(screen.backButton.variant, MissionButton.Variant.Secondary)
        screen.destroy()
    }

    // ── Partition plan catalog (Screen 07 fields) ──────────────────
    // Every partition exposes: name, device label, size, filesystem,
    // mount point, proposed change, destructive flag; the plan includes
    // a boot partition and a recovery partition.
    function test_partitionCatalog() {
        // Host-provided plan renders; no fabricated defaults (FABRICATION-8)
        var screen = createScreen(
            "screenState: 'normal'; partitionOptions: [" +
            "{ name: 'EFI System Partition', label: 'nvme0n1p1', size: '512 MB', filesystem: 'FAT32', mountPoint: '/boot/efi', boot: true, recovery: false, change: 'Create', destructive: false }," +
            "{ name: 'Boot', label: 'nvme0n1p2', size: '1 GB', filesystem: 'ext4', mountPoint: '/boot', boot: false, recovery: false, change: 'Create', destructive: false }," +
            "{ name: 'Root', label: 'nvme0n1p3', size: '40 GB', filesystem: 'ext4', mountPoint: '/', boot: false, recovery: false, change: 'Format', destructive: true }," +
            "{ name: 'Home', label: 'nvme0n1p4', size: '1.3 TB', filesystem: 'ext4', mountPoint: '/home', boot: false, recovery: false, change: 'Format', destructive: true }," +
            "{ name: 'Recovery', label: 'nvme0n1p5', size: '16 GB', filesystem: 'ext4', mountPoint: '/recovery', boot: false, recovery: true, change: 'Create', destructive: false }" +
            "]")
        var expectedNames = ["EFI System Partition", "Boot", "Root", "Home", "Recovery"]
        var expectedMounts = ["/boot/efi", "/boot", "/", "/home", "/recovery"]
        var expectedChanges = ["Create", "Create", "Format", "Format", "Create"]
        compare(screen.partitionOptions.length, expectedNames.length)
        for (var i = 0; i < screen.partitionOptions.length; ++i) {
            compare(screen.partitionOptions[i].name, expectedNames[i])
            compare(screen.partitionOptions[i].mountPoint, expectedMounts[i])
            compare(screen.partitionOptions[i].change, expectedChanges[i])
        }
        // Boot partition: EFI System Partition (row 0)
        compare(screen.partitionOptions[0].boot, true)
        compare(screen.partitionOptions[0].mountPoint, "/boot/efi")
        // Recovery partition: Recovery (row 4)
        compare(screen.partitionOptions[4].recovery, true)
        compare(screen.partitionOptions[4].mountPoint, "/recovery")
        // Destructive actions: Root and Home are "Format"
        compare(screen.partitionOptions[2].destructive, true)
        compare(screen.partitionOptions[3].destructive, true)
        compare(screen.destructiveCount, 2)
        screen.destroy()
    }

    // ── Every partition exposes all required display fields ────────
    function test_partitionFields() {
        // Host-provided plan; no fabricated defaults (FABRICATION-8)
        var screen = createScreen(
            "screenState: 'normal'; partitionOptions: [" +
            "{ name: 'EFI System Partition', label: 'nvme0n1p1', size: '512 MB', filesystem: 'FAT32', mountPoint: '/boot/efi', boot: true, recovery: false, change: 'Create', destructive: false }," +
            "{ name: 'Root', label: 'nvme0n1p3', size: '40 GB', filesystem: 'ext4', mountPoint: '/', boot: false, recovery: false, change: 'Format', destructive: true }" +
            "]")
        for (var i = 0; i < screen.partitionOptions.length; ++i) {
            var p = screen.partitionOptions[i]
            verify(p.name.length > 0, "partition " + i + " must have a name")
            verify(p.label.length > 0, "partition " + i + " must have a device label")
            verify(p.size.length > 0, "partition " + i + " must state its size")
            verify(p.filesystem.length > 0, "partition " + i + " must state its filesystem")
            verify(p.mountPoint.length > 0, "partition " + i + " must state its mount point")
            verify(p.change.length > 0, "partition " + i + " must state its proposed change")
            verify(p.destructive !== undefined, "partition " + i + " must state whether the change is destructive")
        }
        screen.destroy()
    }

    // ── Destructive actions are clearly highlighted ────────────────
    // Reference Screen 07: "Every destructive action should be clearly
    // highlighted." Real rendering behavior: destructive rows use the
    // error container background; non-destructive rows use the surface.
    function test_destructiveHighlight() {
        // Host-provided plan; no fabricated defaults (FABRICATION-8)
        var screen = createScreen(
            "screenState: 'normal'; partitionOptions: [" +
            "{ name: 'Boot', label: 'nvme0n1p2', size: '1 GB', filesystem: 'ext4', mountPoint: '/boot', boot: false, recovery: false, change: 'Create', destructive: false }," +
            "{ name: 'Root', label: 'nvme0n1p3', size: '40 GB', filesystem: 'ext4', mountPoint: '/', boot: false, recovery: false, change: 'Format', destructive: true }" +
            "]")
        MissionTheme.darkMode = false
        for (var i = 0; i < screen.partitionOptions.length; ++i) {
            var row = screen.partitionRows.itemAt(i)
            verify(row !== null, "partition row " + i + " must exist")
            // The change badge states the proposed change and is
            // error-styled exactly when the change is destructive.
            compare(row.changeBadgeText, screen.partitionOptions[i].change,
                    "row " + i + " change badge must state the proposed change")
            if (screen.partitionOptions[i].destructive) {
                verify(Qt.colorEqual(row.rowBackground.color, Colors.errorContainer),
                       "destructive row " + i + " must render on the error container")
                // Non-color indicator: the explicit "Destructive" marker
                verify(row.destructiveMarker.visible,
                       "destructive row " + i + " must show the Destructive marker")
                verify(Qt.colorEqual(row.changeBadge.color, MissionTheme.error),
                       "destructive row " + i + " change badge must be error-styled")
            } else {
                verify(Qt.colorEqual(row.rowBackground.color, MissionTheme.surface),
                       "non-destructive row " + i + " must render on the surface")
                verify(!row.destructiveMarker.visible,
                       "non-destructive row " + i + " must not show the Destructive marker")
                verify(Qt.colorEqual(row.changeBadge.color, MissionTheme.surfaceDim),
                       "non-destructive row " + i + " change badge must be neutral")
            }
        }
        screen.destroy()
    }

    // ── Boot / recovery role badges ────────────────────────────────
    // Reference Screen 07 displays the boot partition and the recovery
    // partition; the badges are the visual role indicators.
    function test_bootAndRecoveryBadges() {
        // Host-provided plan; no fabricated defaults (FABRICATION-8)
        var screen = createScreen(
            "screenState: 'normal'; partitionOptions: [" +
            "{ name: 'EFI System Partition', label: 'nvme0n1p1', size: '512 MB', filesystem: 'FAT32', mountPoint: '/boot/efi', boot: true, recovery: false, change: 'Create', destructive: false }," +
            "{ name: 'Recovery', label: 'nvme0n1p5', size: '16 GB', filesystem: 'ext4', mountPoint: '/recovery', boot: false, recovery: true, change: 'Create', destructive: false }" +
            "]")
        for (var i = 0; i < screen.partitionOptions.length; ++i) {
            var row = screen.partitionRows.itemAt(i)
            compare(row.bootBadge.visible, screen.partitionOptions[i].boot,
                    "row " + i + " boot badge visibility")
            compare(row.recoveryBadge.visible, screen.partitionOptions[i].recovery,
                    "row " + i + " recovery badge visibility")
        }
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
                spyNames[i] + "' }", screen, "partSpy" + i)
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
            screen, "partContSpy")
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
    // The partition rows are read-only review content and must never
    // take focus; only Back and Continue are in the focus chain.
    function test_keyboardFocus() {
        var screen = createScreen()
        wait(100) // let the hosted window activate so Tab reaches the controls
        var hostWindow = _hostWindows[_hostWindows.length - 1]
        var found = {}
        var never = {}

        // Walk the whole focus chain with Tab (the chain wraps, so 80
        // presses cover every control).
        for (var tab = 0; tab < 80; ++tab) {
            keyClick(Qt.Key_Tab)
            var focusItem = hostWindow.activeFocusItem
            if (focusItem && focusItem.objectName) {
                found[focusItem.objectName] = true
                never[focusItem.objectName] = true
            }
        }

        verify(found["partitionBack"], "focus must reach partitionBack")
        verify(found["partitionContinue"], "focus must reach partitionContinue")
        verify(!never["partitionItem0"],
               "read-only partition rows must never take focus (review display only)")

        screen.destroy()
    }

    // ── Shift+Tab walks the focus chain backward ───────────────────
    function test_shiftTabNavigatesBackward() {
        var screen = createScreen()
        wait(100)
        var hostWindow = _hostWindows[_hostWindows.length - 1]

        // Warm up the hosted window (first key event on a fresh window
        // is consumed by window activation on this build).
        screen.continueButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        screen.continueButton.forceActiveFocus()
        verify(screen.continueButton.activeFocus)

        keyClick(Qt.Key_Tab, Qt.ShiftModifier)
        var item1 = hostWindow.activeFocusItem
        verify(item1 && item1.objectName === "partitionBack",
               "Shift+Tab from Continue must reach Back, got " +
               (item1 ? item1.objectName : "null"))

        screen.destroy()
    }

    // ── Escape navigates back ──────────────────────────────────────
    function test_escapeNavigatesBack() {
        var screen = createScreen()
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'backRequested' }",
            screen, "partEscSpy")
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
            "import org.mission.ui 1.0; MissionPage { pageTitle: 'Installer'; PartitionManager { objectName: 'partInPage' } }",
            root, "partInPage")
        verify(page !== null)
        verify(page.data.length > 0)
        page.destroy()
    }

    function test_missionWindowIntegration() {
        var screen = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionWindow { width: 1024; height: 768; PartitionManager { objectName: 'partInWindow' } }",
            root, "partInWindow")
        verify(screen !== null)
        verify(screen.width > 0)
        screen.destroy()
    }

    // ── Reduced motion does not break rendering ────────────────────
    function test_reducedMotion() {
        // Host-provided plan; no fabricated defaults (FABRICATION-8)
        var screen = createScreen(
            "screenState: 'normal'; partitionOptions: [" +
            "{ name: 'EFI System Partition', label: 'nvme0n1p1', size: '512 MB', filesystem: 'FAT32', mountPoint: '/boot/efi', boot: true, recovery: false, change: 'Create', destructive: false }," +
            "{ name: 'Boot', label: 'nvme0n1p2', size: '1 GB', filesystem: 'ext4', mountPoint: '/boot', boot: false, recovery: false, change: 'Create', destructive: false }," +
            "{ name: 'Root', label: 'nvme0n1p3', size: '40 GB', filesystem: 'ext4', mountPoint: '/', boot: false, recovery: false, change: 'Format', destructive: true }," +
            "{ name: 'Home', label: 'nvme0n1p4', size: '1.3 TB', filesystem: 'ext4', mountPoint: '/home', boot: false, recovery: false, change: 'Format', destructive: true }," +
            "{ name: 'Recovery', label: 'nvme0n1p5', size: '16 GB', filesystem: 'ext4', mountPoint: '/recovery', boot: false, recovery: true, change: 'Create', destructive: false }" +
            "]")
        screen.reducedMotion = true
        screen.screenState = "loading"
        verify(screen.loadingIndicator.visible)
        verify(!screen.continueButton.enabled)
        screen.screenState = "empty"
        verify(screen.continueButton.enabled)
        // The plan still renders with reduced motion
        compare(screen.partitionRows.count, 5)
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
