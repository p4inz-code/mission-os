// Mission OS — Workspace Confirmation (MOS-INS-015) QtTest suite
//
// Runtime validation of the Workspace Confirmation screen. Follows the
// foundation smoke-test pattern (tests/tst_smoke.qml) and the
// MOS-INS-001→014 Installer suites (in particular the Encryption
// single-select suite) per docs/engineering/TESTING_STRATEGY.md
// (QML → Qt Test / qmltestrunner).
//
// Coverage (only behaviors required by the authoritative sources —
// reference § "Screen 17 — Workspace Confirmation", § "Screen 11 —
// Workspace Profile", registry MOS-INS-015):
//   - screen loads without QML errors (token singletons resolve)
//   - default state: step 15 of 17, the seven reference profiles shown,
//     first profile preselected (non-emitting), Continue enabled (valid
//     preselected choice), Back enabled (step 15 > 1)
//   - no spurious action or host-change signals on load
//   - the seven profiles exactly as listed in the reference (Creator,
//     Developer, Privacy, Security, Student, General, Minimal), in
//     order; every profile carries the "changing the profile updates"
//     list (default applications, shortcuts, desktop layout,
//     recommended settings)
//   - selecting a profile fires workspaceChangeRequested exactly once
//     per user action, carrying the profile code
//   - out-of-range selection requests are ignored (no signal)
//   - required signals fire from the right controls (continue/back/retry)
//   - required state transitions (empty/loading/error/success/offline)
//   - Continue is blocked while loading/error (validation-before-continue)
//   - state banners render with positive height (banner-height regression)
//   - keyboard navigation: list focus, Up/Down, Enter/Space selection
//   - keyboard focus reaches all list rows, Back and Continue
//   - Escape navigates back
//   - accessibility roles/names (heading, list + items, buttons)
//   - responsive compact layout (help panel collapses)
//   - reduced motion does not break rendering
//   - MissionPage / MissionWindow integration introduces no runtime errors
//
// Run via qmltestrunner (see CMakeLists.txt CTest registration):
//   qmltestrunner -import <build>/src/libraries/ui/qml \
//                 -input src/libraries/ui/tests/tst_workspace_confirmation.qml
//
// Exit code: 0 = all checks passed; non-zero = failure (CI gate).

import QtQuick
import QtTest
import org.mission.ui 1.0

TestCase {
    id: root
    name: "WorkspaceConfirmation"

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
                     "    WorkspaceConfirmation { id: screen; width: " + width +
                     "; height: " + height + "; " + (extra || "") + " }\n" +
                     "}"
        var host = Qt.createQmlObject(source, root, "wsHost" + _hostWindows.length)
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
        // Step context: Workspace Confirmation is installer step 15 of 17
        compare(screen.step, 15)
        compare(screen.totalSteps, 17)
        // All seven supported profiles exist (reference § "Screen 17")
        compare(screen.profileCount, 7)
        // Defaults: first profile preselected (non-emitting), Continue
        // enabled (valid choice), Back enabled (step > 1).
        compare(screen.selectedProfileIndex, 0)
        compare(screen.currentProfileCode, "creator")
        compare(screen.currentProfileLabel, "Creator")
        verify(screen.selectedProfile !== null)
        compare(screen.selectedProfile.code, "creator")
        verify(screen.continueButton.enabled)
        verify(screen.backButton.enabled)
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
                     "    property alias spyW: spyW\n" +
                     "    WorkspaceConfirmation { id: screen; width: 1024; height: 768\n" +
                     "        SignalSpy { id: spyC; signalName: 'continueRequested'; target: screen }\n" +
                     "        SignalSpy { id: spyB; signalName: 'backRequested'; target: screen }\n" +
                     "        SignalSpy { id: spyR; signalName: 'retryRequested'; target: screen }\n" +
                     "        SignalSpy { id: spyW; signalName: 'workspaceChangeRequested'; target: screen }\n" +
                     "    }\n" +
                     "}\n"
        var host = Qt.createQmlObject(source, root, "wsLoadHost")
        _hostWindows.push(host)
        compare(host.spyC.count, 0)
        compare(host.spyB.count, 0)
        compare(host.spyR.count, 0)
        compare(host.spyW.count, 0)
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

    // ── The seven profiles match the reference exactly ─────────────
    // Reference § "Screen 17": "Examples: Creator, Developer, Privacy,
    // Security, Student, General, Minimal." No profile may be invented
    // or omitted.
    function test_profilesMatchReference() {
        var screen = createScreen()
        var expected = [
            ["creator",   "Creator"],
            ["developer", "Developer"],
            ["privacy",   "Privacy"],
            ["security",  "Security"],
            ["student",   "Student"],
            ["general",   "General"],
            ["minimal",   "Minimal"]
        ]
        compare(screen.workspaceProfiles.length, expected.length)
        for (var i = 0; i < expected.length; ++i) {
            compare(screen.workspaceProfiles[i].code, expected[i][0], "profile " + i + " code")
            compare(screen.workspaceProfiles[i].label, expected[i][1], "profile " + i + " label")
        }
        screen.destroy()
    }

    // ── Every profile explains what changing it updates ────────────
    // Reference § "Screen 17": "Changing the profile updates: default
    // applications, shortcuts, desktop layout, recommended settings.
    // No reinstall is required."
    function test_profileExplanationsPresent() {
        var screen = createScreen()
        for (var i = 0; i < screen.workspaceProfiles.length; ++i) {
            var profile = screen.workspaceProfiles[i]
            verify(profile.role.length > 0,
                   "profile " + profile.code + " must carry a role explanation")
            verify(profile.configures.length > 0,
                   "profile " + profile.code + " must explain what it updates")
            verify(profile.configures.indexOf("Default applications") >= 0,
                   "profile " + profile.code + " must mention default applications")
            verify(profile.configures.indexOf("desktop layout") >= 0,
                   "profile " + profile.code + " must mention desktop layout")
            verify(profile.configures.indexOf("shortcuts") >= 0,
                   "profile " + profile.code + " must mention shortcuts")
            verify(profile.configures.indexOf("recommended settings") >= 0,
                   "profile " + profile.code + " must mention recommended settings")
        }
        // All seven rows are present in the list model
        verify(screen.profileList.count === 7)
        screen.destroy()
    }

    // ── Selecting a profile fires the host-change signal exactly ───
    function test_selectionEmitsChange() {
        var screen = createScreen()
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'workspaceChangeRequested' }",
            screen, "wsSelectSpy")
        spy.target = screen

        // Select "Developer" (index 1)
        screen.selectProfile(1)
        compare(screen.selectedProfileIndex, 1)
        compare(screen.currentProfileCode, "developer")
        compare(screen.currentProfileLabel, "Developer")
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "developer")

        // Select "Minimal" (index 6)
        screen.selectProfile(6)
        compare(screen.selectedProfileIndex, 6)
        compare(screen.currentProfileCode, "minimal")
        compare(spy.count, 2)
        compare(spy.signalArguments[1][0], "minimal")

        // Live selection caption reflects the current choice and the
        // "no reinstall required" confirmation (reference § "Screen 17")
        verify(screen.selectionCaption.visible)
        verify(screen.selectionCaption.text.indexOf("Minimal") >= 0)
        verify(screen.selectionCaption.text.indexOf("no reinstall required") >= 0)

        screen.destroy()
    }

    // ── Host wiring: the host can re-feed the real selection ───────
    // The installer's configuration is host-fed (no in-flow profile
    // screen); the host sets the selection made during installation.
    function test_hostWiring() {
        var screen = createScreen()
        screen.selectProfile(4) // Student, as if fed by the host
        compare(screen.currentProfileCode, "student")
        compare(screen.currentProfileLabel, "Student")
        // The read-back row highlight follows the selection
        wait(50)
        var item4 = screen.profileList.itemAtIndex(4)
        verify(item4 !== null)
        verify(item4.Accessible.selected, "row 4 must be announced as selected")
        screen.destroy()
    }

    // ── Out-of-range selection requests are ignored ────────────────
    function test_outOfRangeSelectionIgnored() {
        var screen = createScreen()
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'workspaceChangeRequested' }",
            screen, "wsRangeSpy")
        spy.target = screen

        screen.selectProfile(-1)
        screen.selectProfile(99)
        compare(spy.count, 0)
        compare(screen.selectedProfileIndex, 0)
        compare(screen.currentProfileCode, "creator")

        screen.destroy()
    }

    // ── Keyboard: list focus, Up/Down, Enter/Space selection ───────
    function test_keyboardSelection() {
        var screen = createScreen()
        wait(100) // let the hosted window activate so key events reach it
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'workspaceChangeRequested' }",
            screen, "wsKbdSpy")
        spy.target = screen

        // Warm up the hosted window (first key event is consumed by
        // window activation on this build — same pattern as 001–014).
        keyClick(Qt.Key_Tab)

        // Give the list focus; Down moves the current row
        screen.profileList.forceActiveFocus()
        verify(screen.profileList.activeFocus)
        keyClick(Qt.Key_Down)
        compare(screen.profileList.currentIndex, 1)

        // Return confirms the focused row (real keyboard interaction)
        keyClick(Qt.Key_Return)
        compare(screen.selectedProfileIndex, 1)
        compare(screen.currentProfileCode, "developer")
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "developer")

        // Down again, Space confirms the next row
        keyClick(Qt.Key_Down)
        compare(screen.profileList.currentIndex, 2)
        keyClick(Qt.Key_Space)
        compare(screen.selectedProfileIndex, 2)
        compare(screen.currentProfileCode, "privacy")
        compare(spy.count, 2)
        compare(spy.signalArguments[1][0], "privacy")

        // Up moves back and Return re-confirms
        keyClick(Qt.Key_Up)
        compare(screen.profileList.currentIndex, 1)
        keyClick(Qt.Key_Return)
        compare(screen.currentProfileCode, "developer")
        compare(spy.count, 3)

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
                spyNames[i] + "' }", screen, "wsSpy" + i)
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
        // empty (default): no banner, Continue enabled (valid choice)
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
            screen, "wsContSpy")
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

        // Empty: valid preselected choice → Continue enabled → keyboard advances
        screen.screenState = "empty"
        verify(screen.continueButton.enabled)
        screen.continueButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spy.count, 1)

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

        // The list is a single Tab stop: the current row's delegate is
        // the focused item while the list holds focus.
        verify(found["workspaceItem0"], "focus must reach the current workspace row")
        verify(found["workspaceBack"], "focus must reach workspaceBack")
        verify(found["workspaceContinue"], "focus must reach workspaceContinue")

        // Every list row is keyboard-reachable: Down moves focus onto
        // each row's delegate in turn.
        screen.profileList.forceActiveFocus()
        for (var row = 1; row < 7; ++row) {
            keyClick(Qt.Key_Down)
            compare(screen.profileList.currentIndex, row)
            verify(hostWindow.activeFocusItem.objectName === "workspaceItem" + row,
                   "focus must follow the list to row " + row)
        }

        // Up navigates back through the rows
        keyClick(Qt.Key_Up)
        compare(screen.profileList.currentIndex, 5)
        verify(hostWindow.activeFocusItem.objectName === "workspaceItem5",
               "focus must follow the list back to row 5")

        screen.destroy()
    }

    // ── Escape navigates back ──────────────────────────────────────
    function test_escapeNavigatesBack() {
        var screen = createScreen()
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'backRequested' }",
            screen, "wsEscSpy")
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
        screen.selectProfile(2) // Privacy — selected row for assertions

        // Heading is announced as a heading with a name
        verify(screen.headingLabel.Accessible.role === Accessible.Heading)
        verify(screen.headingLabel.Accessible.name.length > 0)

        // Profile list is a named list; its items are list items with
        // the selected state announced
        verify(screen.profileList.Accessible.role === Accessible.List)
        verify(screen.profileList.Accessible.name.length > 0)
        var item2 = screen.profileList.itemAtIndex(2)
        verify(item2.Accessible.role === Accessible.ListItem)
        verify(item2.Accessible.name.indexOf("Privacy") >= 0)
        verify(item2.Accessible.selected, "selected row must be announced")

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

    // ── MissionPage / MissionWindow integration ────────────────────
    function test_missionPageIntegration() {
        var page = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionPage { pageTitle: 'First Boot'; WorkspaceConfirmation { objectName: 'wsInPage' } }",
            root, "wsInPage")
        verify(page !== null)
        verify(page.data.length > 0)
        page.destroy()
    }

    function test_missionWindowIntegration() {
        var screen = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionWindow { width: 1024; height: 768; WorkspaceConfirmation { objectName: 'wsInWindow' } }",
            root, "wsInWindow")
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
        // Selection still works with reduced motion
        screen.selectProfile(5)
        compare(screen.selectedProfileIndex, 5)
        compare(screen.currentProfileCode, "general")
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
