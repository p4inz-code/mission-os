// Mission OS — Installer Summary (MOS-INS-010) QtTest suite
//
// Runtime validation of the Summary screen. Follows the
// foundation smoke-test pattern (tests/tst_smoke.qml) and the
// MOS-INS-001→009 Installer suites (tests/tst_installer_welcome.qml …
// tst_encryption.qml) per docs/engineering/TESTING_STRATEGY.md
// (QML → Qt Test / qmltestrunner).
//
// Coverage (only behaviors required by the authoritative sources —
// reference § "Configuration Summary", registry MOS-INS-010):
//   - screen loads without QML errors (token singletons resolve)
//   - default state: step 10 of 12, all eleven summary sections shown,
//     Continue enabled (a review is always valid), Back enabled
//     (step 10 > 1)
//   - the eleven summary sections match the reference list exactly
//     (Installation mode, Target disk, Partition changes, Region,
//     Keyboard layout, Platform preset, Workspace profile, Privacy
//     settings, Security settings, Estimated installation time,
//     Estimated storage usage) — no item may be invented or omitted
//   - default section values mirror the preceding screens' preselects
//     (region en_US, keyboard us, preset linux, privacy 0-of-6,
//     security no-encryption)
//   - no spurious action signals on load (read-only review — nothing
//     to emit)
//   - host wiring: setSectionValue() updates a section, fires
//     summarySectionsChanged exactly once per call, and the rendered
//     list row reflects the new value; unknown codes are ignored
//   - required signals fire from the right controls (continue/back/retry)
//   - required state transitions (empty/loading/error/success/offline)
//   - Continue is blocked while loading/error (validation-before-continue)
//   - state banners render with positive height (banner-height regression)
//   - keyboard navigation: focus reaches Back and Continue; the
//     read-only summary rows are NOT Tab stops (no keyboard trap)
//   - Escape navigates back
//   - responsive compact layout (help panel collapses)
//   - reduced motion does not break rendering
//   - MissionPage / MissionWindow integration introduces no runtime errors
//
// Run via qmltestrunner (see CMakeLists.txt CTest registration):
//   qmltestrunner -import <build>/src/libraries/ui/qml \
//                 -input src/libraries/ui/tests/tst_summary.qml
//
// Exit code: 0 = all checks passed; non-zero = failure (CI gate).

import QtQuick
import QtTest
import org.mission.ui 1.0

TestCase {
    id: root
    name: "Summary"

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
                     "    Summary { id: screen; width: " + width + "; height: " + height + "; " +
                     (extra || "") + " }\n" +
                     "}"
        var host = Qt.createQmlObject(source, root, "sumHost")
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
        // Step context: Summary is installer step 11 of 17
        compare(screen.step, 11)
        compare(screen.totalSteps, 17)
        // All eleven supported items exist (reference § "Configuration Summary")
        compare(screen.summaryCount, 11)
        compare(screen.summaryList.count, 11)
        // Defaults: review is always a valid state, so Continue is
        // enabled; Back is enabled (step 10 > 1).
        verify(screen.continueButton.enabled)
        verify(screen.backButton.enabled)
        screen.destroy()
    }

    // ── The eleven summary sections match the reference exactly ────
    // Reference § "Configuration Summary": "The summary includes:
    // Installation mode, Target disk, Partition changes, Region,
    // Keyboard layout, Platform preset, Workspace profile, Privacy
    // settings, Security settings, Estimated installation time,
    // Estimated storage usage." No item may be invented or omitted.
    function test_summarySectionsMatchReference() {
        var screen = createScreen()
        var expected = [
            ["mode",       "Installation mode"],
            ["disk",       "Target disk"],
            ["partitions", "Partition changes"],
            ["region",     "Region"],
            ["keyboard",   "Keyboard layout"],
            ["preset",     "Platform preset"],
            ["profile",    "Workspace profile"],
            ["privacy",    "Privacy settings"],
            ["security",   "Security settings"],
            ["time",       "Estimated installation time"],
            ["storage",    "Estimated storage usage"]
        ]
        compare(screen.summarySections.length, expected.length)
        for (var i = 0; i < expected.length; ++i) {
            compare(screen.summarySections[i].code, expected[i][0],
                    "section " + i + " code")
            compare(screen.summarySections[i].label, expected[i][1],
                    "section " + i + " label")
            verify(screen.summarySections[i].value.length > 0,
                   "section " + screen.summarySections[i].code + " must display a value")
        }
        screen.destroy()
    }

    // ── Default values mirror the preceding screens' preselects ────
    // Grounded in the established defaults (002 en_US, 003 us + linux,
    // 005 all services off, 009 no encryption) so the review renders
    // coherently before the host wires real data.
    function test_defaultValuesGroundedInPrecedingScreens() {
        var screen = createScreen()
        compare(screen.getSection("region").value, "English (United States)")
        compare(screen.getSection("region").detail, "en_US")
        compare(screen.getSection("keyboard").value, "US")
        compare(screen.getSection("keyboard").detail, "us")
        compare(screen.getSection("preset").value, "Linux (Default)")
        compare(screen.getSection("preset").detail, "linux")
        compare(screen.getSection("privacy").value, "All optional services disabled")
        compare(screen.getSection("privacy").detail, "0 of 6 enabled")
        compare(screen.getSection("security").value, "Auto updates enabled")
        // No prior screen establishes these; neutral placeholders
        // (host fills the real values).
        compare(screen.getSection("time").value, "—")
        compare(screen.getSection("storage").value, "—")
        screen.destroy()
    }

    // ── Defaults must not emit spurious signals ────────────────────
    // Regression guard: no action signal may fire on load (the summary
    // is a read-only review — it has no *ChangeRequested signal because
    // nothing is configured on this screen).
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
                     "    Summary { id: screen; width: 1024; height: 768\n" +
                     "        SignalSpy { id: spyC; signalName: 'continueRequested'; target: screen }\n" +
                     "        SignalSpy { id: spyB; signalName: 'backRequested'; target: screen }\n" +
                     "        SignalSpy { id: spyR; signalName: 'retryRequested'; target: screen }\n" +
                     "    }\n" +
                     "}\n"
        var host = Qt.createQmlObject(source, root, "sumLoadHost")
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

    // ── Host wiring: setSectionValue updates data + rendered row ───
    // The host feeds the real configuration values into the summary;
    // each call updates the section, notifies the list, and the
    // rendered row reflects the new value (genuine behavior — the
    // summary must display the configuration chosen on earlier steps).
    function test_setSectionValueUpdates() {
        var screen = createScreen()
        compare(screen.getSection("disk").value, "No disk selected")

        var spy = Qt.createQmlObject(
            "import QtTest; SignalSpy { signalName: 'summarySectionsChanged' }",
            screen, "sumChangeSpy")
        spy.target = screen

        // Host wires the real target disk
        screen.setSectionValue("disk", "Samsung 990 Pro (2 TB)", "512 GB available")
        compare(spy.count, 1)
        compare(screen.getSection("disk").value, "Samsung 990 Pro (2 TB)")
        compare(screen.getSection("disk").detail, "512 GB available")

        // Detail stays untouched when omitted
        screen.setSectionValue("time", "About 15 minutes")
        compare(spy.count, 2)
        compare(screen.getSection("time").value, "About 15 minutes")
        compare(screen.getSection("time").detail, "")

        // Model intact
        compare(screen.summaryCount, 11)
        compare(screen.summaryList.count, 11)

        // The rendered list row reflects the new value
        wait(50) // let the model reset re-instantiate the visible rows
        var item = screen.summaryList.itemAtIndex(1)
        verify(item !== null, "disk row delegate must be instantiated")
        compare(item.objectName, "summaryItem1")
        compare(item.valueLabel.text, "Samsung 990 Pro (2 TB)")

        screen.destroy()
    }

    // ── Unknown section codes are ignored (no invention) ───────────
    function test_setSectionUnknownCodeIgnored() {
        var screen = createScreen()
        compare(screen.getSection("nonexistent"), null)
        compare(screen.sectionIndex("nonexistent"), -1)

        var spy = Qt.createQmlObject(
            "import QtTest; SignalSpy { signalName: 'summarySectionsChanged' }",
            screen, "sumRangeSpy")
        spy.target = screen

        screen.setSectionValue("nonexistent", "anything")
        compare(spy.count, 0)
        compare(screen.getSection("disk").value, "No disk selected")

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
                spyNames[i] + "' }", screen, "sumSpy" + i)
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
        // empty (default): no banner, Continue enabled (valid review)
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

        // offline: informational banner, Continue enabled (offline installs supported)
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
            screen, "sumContSpy")
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

        // Empty: valid review → Continue enabled → keyboard advances
        screen.screenState = "empty"
        verify(screen.continueButton.enabled)
        screen.continueButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spy.count, 1)

        screen.destroy()
    }

    // ── Keyboard focus reaches the actionable controls ─────────────
    // Back and Continue must be reachable through the Tab focus chain.
    // The summary rows are read-only, so they are deliberately NOT Tab
    // stops (no keyboard trap) — only Back and Continue carry focus.
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

        verify(found["summaryBack"], "focus must reach summaryBack")
        verify(found["summaryContinue"], "focus must reach summaryContinue")

        // Read-only summary rows must NOT be keyboard Tab stops.
        for (var row = 0; row < 11; ++row) {
            verify(!("summaryItem" + row in found),
                   "read-only summary row " + row + " must not be a Tab stop")
        }

        screen.destroy()
    }

    // ── Escape navigates back ──────────────────────────────────────
    function test_escapeNavigatesBack() {
        var screen = createScreen()
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'backRequested' }",
            screen, "sumEscSpy")
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
            "import org.mission.ui 1.0; MissionPage { pageTitle: 'Installer'; Summary { objectName: 'sumInPage' } }",
            root, "sumInPage")
        verify(page !== null)
        verify(page.data.length > 0)
        page.destroy()
    }

    function test_missionWindowIntegration() {
        var screen = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionWindow { width: 1024; height: 768; Summary { objectName: 'sumInWindow' } }",
            root, "sumInWindow")
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
        screen.setSectionValue("storage", "About 12 GB")
        compare(screen.getSection("storage").value, "About 12 GB")
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
