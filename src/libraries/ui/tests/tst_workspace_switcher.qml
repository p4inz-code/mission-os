// Mission OS — Workspace Switcher (MOS-DES-002) QtTest suite
//
// Runtime validation of the Workspace Switcher screen. Follows the
// foundation smoke-test pattern (tests/tst_smoke.qml), the Desktop
// suite (tests/tst_desktop.qml), the lock-family suites and
// docs/engineering/TESTING_STRATEGY.md (QML → Qt Test / qmltestrunner).
//
// Coverage:
//   - screen loads without QML errors (token singletons resolve)
//   - MissionTheme works; light/dark rendering bindings re-evaluate
//   - overlay treatment: scrim + centered card with a "Workspaces"
//     heading
//   - workspace rows render from the host model (name, optional window
//     count, current-workspace highlight)
//   - currentWorkspace is host-driven and clamps out-of-range indices
//   - the Workspace Flow's "Choose Workspace" step: click, Enter and
//     Space emit workspaceSelected(id); selecting the current
//     workspace again still emits (host decides)
//   - keyboard navigation: Up/Down/Left/Right move focus between rows
//     (wrapping); the current row is focused on load (keyboard-first)
//   - empty workspaces degrade to a neutral hint without errors
//   - accessibility roles (heading, radio rows with checked state)
//   - Escape is deliberately unmapped (no signal fires — the host owns
//     overlay dismissal)
//   - MissionPage / MissionWindow integration introduces no runtime errors
//   - reduced motion does not break rendering
//
// Notes on createScreen(extra): every extra is a single QML property
// assignment (the validated family pattern). Where a test needs several
// properties, they are separated with semicolons — commas are not valid
// between QML property assignments (empirically verified on this
// toolchain).
//
// Run via qmltestrunner (see CMakeLists.txt CTest registration):
//   qmltestrunner -import <build>/src/libraries/ui/qml \
//                 -input src/libraries/ui/tests/tst_workspace_switcher.qml
//
// Exit code: 0 = all checks passed; non-zero = failure (CI gate).

import QtQuick
import QtTest
import org.mission.ui 1.0

TestCase {
    id: root
    name: "WorkspaceSwitcher"

    // ── Helpers ────────────────────────────────────────────────────
    // The qmltestrunner harness does not show its own test window, so
    // items hosted directly under the TestCase report visible=false on
    // this Qt build (verified empirically). To validate real
    // visibility and keyboard-focus behavior, every screen under test
    // is hosted inside an explicit visible Window; cleanup() destroys
    // the host windows afterwards.
    property var _hostWindows: []

    function createScreen(extra) {
        var source = "import QtQuick\n" +
                     "import org.mission.ui 1.0\n" +
                     "Window {\n" +
                     "    width: 1280; height: 720; visible: true\n" +
                     "    property alias screen: screen\n" +
                     "    WorkspaceSwitcher { id: screen; width: 1280; height: 720; " +
                     (extra || "") + " }\n" +
                     "}"
        var host = Qt.createQmlObject(source, root, "wsHost")
        _hostWindows.push(host)
        return host.screen
    }

    // ── Screen loads; tokens resolve; no QML errors ────────────────
    function test_screenLoads() {
        var screen = createScreen()
        verify(screen !== null)
        verify(screen.height > 0)
        // Overlay treatment: scrim + centered card + heading
        verify(screen.backdropScrim !== null)
        verify(screen.switcherCard !== null)
        verify(screen.titleLabel.text.length > 0)
        compare(screen.titleLabel.text, "Workspaces")
        screen.destroy()
    }

    // ── MissionTheme light/dark rendering bindings ─────────────────
    function test_themeLightAndDark() {
        var screen = createScreen("workspaces: [ { id: 'w1', name: 'Main' } ]")
        var row0 = screen.workspaceRows.itemAt(0)
        // Disable the row's Behavior on color (reduced-motion) so theme
        // flips apply instantly instead of animating over Motion.colorChange
        screen.reducedMotion = true

        MissionTheme.darkMode = false
        verify(Qt.colorEqual(screen.backdropScrim.color, Colors.scrim))
        verify(Qt.colorEqual(screen.titleLabel.color, MissionTheme.textPrimary))
        // Current row uses the light primaryContainer treatment
        verify(Qt.colorEqual(row0.color, MissionTheme.primaryContainer))

        MissionTheme.darkMode = true
        verify(Qt.colorEqual(screen.titleLabel.color, MissionTheme.textPrimary))
        // Current row uses the dark primary treatment
        verify(Qt.colorEqual(row0.color, MissionTheme.primary))

        MissionTheme.darkMode = false
        screen.destroy()
    }

    // ── Workspace rows render with names, counts and highlight ─────
    function test_workspacesRender() {
        var screen = createScreen("workspaces: [ { id: 'w1', name: 'Main', windowCount: 3 }, " +
                                            "{ id: 'w2', name: 'Dev', windowCount: 1 }, " +
                                            "{ id: 'w3', name: 'Media' } ]; " +
                                            "currentWorkspace: 1")
        verify(screen.workspaceRows.count === 3)
        var row0 = screen.workspaceRows.itemAt(0)
        var row1 = screen.workspaceRows.itemAt(1)
        var row2 = screen.workspaceRows.itemAt(2)
        verify(row0 !== null && row1 !== null && row2 !== null)
        // Names via the Accessible name (index 1-based)
        compare(row0.Accessible.name, "Workspace 1 of 3: Main")
        compare(row1.Accessible.name, "Workspace 2 of 3: Dev (current)")
        compare(row2.Accessible.name, "Workspace 3 of 3: Media")
        // Current workspace is checked
        verify(!row0.Accessible.checked)
        verify(row1.Accessible.checked)
        verify(!row2.Accessible.checked)
        // Derived helpers
        compare(screen.clampedCurrent, 1)
        compare(screen.currentWorkspaceName, "Dev")
        compare(screen.currentWorkspaceEntry.id, "w2")
        screen.destroy()
    }

    // ── currentWorkspace clamps out-of-range indices ───────────────
    function test_currentWorkspaceClamp() {
        var screen = createScreen("workspaces: [ { id: 'a', name: 'A' }, " +
                                            "{ id: 'b', name: 'B' } ]")
        // Default 0 → first row is current
        compare(screen.clampedCurrent, 0)
        verify(screen.workspaceRows.itemAt(0).Accessible.checked)
        // Out of range below
        screen.currentWorkspace = -5
        compare(screen.clampedCurrent, 0)
        // Out of range above
        screen.currentWorkspace = 99
        compare(screen.clampedCurrent, 1)
        verify(screen.workspaceRows.itemAt(1).Accessible.checked)
        screen.destroy()
    }

    // ── Choose Workspace: click, Enter and Space emit the id ───────
    function test_selection() {
        var screen = createScreen("workspaces: [ { id: 'w1', name: 'Main' }, " +
                                            "{ id: 'w2', name: 'Dev' } ]")
        wait(100) // window activation for key delivery
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'workspaceSelected' }",
            screen, "wsSpy")
        spy.target = screen

        // Mouse click on the second row
        var row1 = screen.workspaceRows.itemAt(1)
        mouseClick(row1, row1.width / 2, row1.height / 2)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "w2")

        // Enter on the first row
        var row0 = screen.workspaceRows.itemAt(0)
        row0.forceActiveFocus()
        keyClick(Qt.Key_Return)
        compare(spy.count, 2)
        compare(spy.signalArguments[1][0], "w1")

        // Space on the current row still emits (host decides)
        row0.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spy.count, 3)
        compare(spy.signalArguments[2][0], "w1")

        screen.destroy()
    }

    // ── Keyboard navigation: arrows move focus between rows ────────
    function test_keyboardNavigation() {
        var screen = createScreen("workspaces: [ { id: 'a', name: 'A' }, " +
                                            "{ id: 'b', name: 'B' }, " +
                                            "{ id: 'c', name: 'C' } ]")
        wait(100) // window activation for key delivery
        var row0 = screen.workspaceRows.itemAt(0)
        var row1 = screen.workspaceRows.itemAt(1)
        var row2 = screen.workspaceRows.itemAt(2)

        // Down moves to the next row; Up moves back
        row0.forceActiveFocus()
        verify(row0.activeFocus)
        keyClick(Qt.Key_Down)
        verify(row1.activeFocus, "Down must move focus to the next workspace")
        keyClick(Qt.Key_Down)
        verify(row2.activeFocus, "Down must move focus to the next workspace")
        keyClick(Qt.Key_Up)
        verify(row1.activeFocus, "Up must move focus to the previous workspace")

        // Left/Right behave the same (wrapping layout)
        keyClick(Qt.Key_Left)
        verify(row0.activeFocus, "Left must move focus to the previous workspace")
        keyClick(Qt.Key_Left)
        verify(row2.activeFocus, "Left must wrap around to the last workspace")
        keyClick(Qt.Key_Right)
        verify(row0.activeFocus, "Right must wrap around to the first workspace")

        screen.destroy()
    }

    // ── Empty workspaces degrade gracefully ────────────────────────
    function test_emptyWorkspaces() {
        var screen = createScreen()
        wait(100)
        verify(screen.workspaceRows.count === 0)
        verify(screen.emptyHint.visible)
        compare(screen.currentWorkspaceName, "")
        compare(screen.clampedCurrent, 0)
        // Selecting is impossible but must not crash
        screen.focusRow(0)
        screen.destroy()
    }

    // ── Optional window count is shown only when present/positive ──
    function test_windowCountDisplay() {
        var screen = createScreen("workspaces: [ { id: 'w1', name: 'Main', windowCount: 3 }, " +
                                            "{ id: 'w2', name: 'Media' }, " +
                                            "{ id: 'w3', name: 'Idle', windowCount: 0 } ]")
        // windowCountFor returns a label for positive counts, "" otherwise
        compare(screen.windowCountFor(screen.workspaces[0]), "3 windows")
        compare(screen.windowCountFor(screen.workspaces[1]), "")
        compare(screen.windowCountFor(screen.workspaces[2]), "")
        screen.destroy()
    }

    // ── Accessibility roles ────────────────────────────────────────
    function test_accessibleRoles() {
        var screen = createScreen("workspaces: [ { id: 'a', name: 'A' }, " +
                                            "{ id: 'b', name: 'B' } ]")
        // Heading announced for the card title
        verify(screen.titleLabel.Accessible.role === Accessible.Heading)
        verify(screen.titleLabel.Accessible.name.length > 0)
        // Rows announced as radios with checked state
        var row0 = screen.workspaceRows.itemAt(0)
        var row1 = screen.workspaceRows.itemAt(1)
        verify(row0.Accessible.role === Accessible.RadioButton)
        verify(row0.Accessible.name.length > 0)
        verify(row0.Accessible.checked)
        verify(!row1.Accessible.checked)
        screen.destroy()
    }

    // ── Keyboard focus reaches the workspace rows ──────────────────
    function test_keyboardFocus() {
        var screen = createScreen("workspaces: [ { id: 'a', name: 'A' }, " +
                                            "{ id: 'b', name: 'B' } ]")
        wait(100) // let the hosted window activate so Tab reaches the rows
        var hostWindow = _hostWindows[_hostWindows.length - 1]
        var found = { "wsRow0": false, "wsRow1": false }

        for (var tab = 0; tab < 20; ++tab) {
            keyClick(Qt.Key_Tab)
            var focusItem = hostWindow.activeFocusItem
            if (focusItem && focusItem.objectName)
                found[focusItem.objectName] = true
        }

        verify(found["wsRow0"], "focus must reach the workspace rows")
        verify(found["wsRow1"], "focus must reach all workspace rows")

        screen.destroy()
    }

    // ── Escape is deliberately unmapped (no signal fires) ──────────
    function test_noEscapeMapping() {
        var screen = createScreen("workspaces: [ { id: 'a', name: 'A' } ]")
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'workspaceSelected' }",
            screen, "escSpy")
        spy.target = screen

        // Escape with a row focused must not dismiss or select
        screen.workspaceRows.itemAt(0).forceActiveFocus()
        keyClick(Qt.Key_Escape)
        compare(spy.count, 0)

        screen.destroy()
    }

    // ── MissionPage / MissionWindow integration ────────────────────
    function test_missionPageIntegration() {
        var page = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionPage { pageTitle: 'Workspaces'; WorkspaceSwitcher { objectName: 'wsInPage' } }",
            root, "wsInPage")
        verify(page !== null)
        verify(page.data.length > 0)
        page.destroy()
    }

    function test_missionWindowIntegration() {
        var screen = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionWindow { width: 1280; height: 720; WorkspaceSwitcher { objectName: 'wsInWindow' } }",
            root, "wsInWindow")
        verify(screen !== null)
        verify(screen.width > 0)
        screen.destroy()
    }

    // ── Reduced motion does not break rendering ────────────────────
    function test_reducedMotion() {
        var screen = createScreen("workspaces: [ { id: 'a', name: 'A' }, " +
                                            "{ id: 'b', name: 'B' } ]")
        screen.reducedMotion = true
        verify(screen.workspaceRows.count === 2)
        verify(screen.switcherCard.visible)
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
