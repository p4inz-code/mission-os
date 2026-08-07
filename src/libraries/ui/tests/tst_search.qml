// Mission OS — Search (MOS-DES-005) QtTest suite
//
// Runtime validation of the Search overlay screen. Follows the
// foundation smoke-test pattern (tests/tst_smoke.qml), the Desktop and
// Workspace Switcher suites (tests/tst_desktop.qml,
// tests/tst_workspace_switcher.qml), the Notifications suite
// (tests/tst_notifications.qml), the Quick Settings suite
// (tests/tst_quick_settings.qml) and docs/engineering/TESTING_STRATEGY.md
// (QML → Qt Test / qmltestrunner).
//
// Coverage:
//   - screen loads without QML errors (token singletons resolve)
//   - MissionTheme works; light/dark rendering bindings re-evaluate
//   - overlay treatment: scrim + centered panel with a "Search" heading
//     (07_DESKTOP_LAYOUT.md §8 — Search opens centered on screen)
//   - results render from the host model (title, subtitle, category
//     tag) with Accessible names carrying the category when present
//   - the result action step: click, Enter and Space emit
//     resultActivated(id)
//   - recent searches render as chips and click/Enter emit
//     recentSearchActivated(text)
//   - the query field: host query binds to the field; typing updates
//     the query property ("results update live" is host-side)
//   - empty states: no query + no recents shows the start-typing hint
//     (with the offline/privacy caption); query with no results shows
//     the no-results hint whose Clear search button empties the query
//   - keyboard navigation: Up/Down move focus across the results
//     (wrapping); the query field is focused on load (keyboard-first)
//   - accessibility roles (heading; editable text field; results
//     announced as buttons)
//   - Escape is deliberately unmapped (no signal fires, query is
//     preserved — the host owns overlay dismissal)
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
//                 -input src/libraries/ui/tests/tst_search.qml
//
// Exit code: 0 = all checks passed; non-zero = failure (CI gate).

import QtQuick
import QtTest
import org.mission.ui 1.0

TestCase {
    id: root
    name: "Search"

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
                     "    Search { id: screen; width: 1280; height: 720; " +
                     (extra || "") + " }\n" +
                     "}"
        var host = Qt.createQmlObject(source, root, "searchHost")
        _hostWindows.push(host)
        return host.screen
    }

    // ── Screen loads; tokens resolve; no QML errors ────────────────
    function test_screenLoads() {
        var screen = createScreen()
        verify(screen !== null)
        verify(screen.height > 0)
        // Overlay treatment: scrim + centered panel + heading
        verify(screen.backdropScrim !== null)
        verify(screen.searchPanel !== null)
        compare(screen.titleLabel.text, "Search")
        // Query field present; keyboard-first: focused on load
        verify(screen.searchField !== null)
        verify(screen.searchField.activeFocus, "the query field must be focused on load")
        screen.destroy()
    }

    // ── MissionTheme light/dark rendering bindings ─────────────────
    function test_themeLightAndDark() {
        var screen = createScreen("query: 'calc'; " +
                                  "results: [ { id: 'calc', title: 'Calculator', category: 'Apps' }, " +
                                  "{ id: 'report', title: 'Report.pdf', subtitle: '~/Documents', category: 'Files' } ]")
        var row0 = screen.resultRows.itemAt(0)
        var row1 = screen.resultRows.itemAt(1)
        // Disable the rows' Behavior on color (reduced-motion) so theme
        // flips apply instantly instead of animating over Motion.colorChange
        screen.reducedMotion = true

        MissionTheme.darkMode = false
        verify(Qt.colorEqual(screen.backdropScrim.color, Colors.scrim))
        verify(Qt.colorEqual(screen.searchPanel.color, MissionTheme.surface))
        verify(Qt.colorEqual(screen.titleLabel.color, MissionTheme.textPrimary))
        verify(Qt.colorEqual(row0.color, MissionTheme.surfaceDim))
        verify(Qt.colorEqual(row1.color, MissionTheme.surfaceDim))

        MissionTheme.darkMode = true
        verify(Qt.colorEqual(row0.color, MissionTheme.surfaceDim))
        verify(Qt.colorEqual(row1.color, MissionTheme.surfaceDim))
        verify(Qt.colorEqual(screen.titleLabel.color, MissionTheme.textPrimary))
        verify(Qt.colorEqual(screen.searchPanel.color, MissionTheme.surface))

        MissionTheme.darkMode = false
        screen.destroy()
    }

    // ── Results render labels, category tags and Accessible names ──
    function test_resultsRender() {
        var screen = createScreen("query: 'x'; " +
                                  "results: [ { id: 'calc', title: 'Calculator', category: 'Apps' }, " +
                                  "{ id: 'report', title: 'Report.pdf', subtitle: '~/Documents', category: 'Files' }, " +
                                  "{ id: 'brightness', title: 'Brightness', category: 'Settings' }, " +
                                  "{ id: 'convert', title: 'km to miles', category: 'Calculator' } ]")
        verify(screen.resultRows.count === 4)
        var row0 = screen.resultRows.itemAt(0)
        var row1 = screen.resultRows.itemAt(1)
        verify(row0 !== null && row1 !== null)
        verify(row0.visible)
        verify(row1.visible)
        // Accessible names carry title + category (color is never the
        // only indicator)
        compare(row0.Accessible.name, "Calculator, Apps")
        compare(row1.Accessible.name, "Report.pdf, Files")
        compare(screen.resultRows.itemAt(2).Accessible.name, "Brightness, Settings")
        compare(screen.resultRows.itemAt(3).Accessible.name, "km to miles, Calculator")
        // Category helper
        compare(screen.categoryLabel(row0.modelData), "Apps")
        compare(screen.categoryLabel(row1.modelData), "Files")
        compare(screen.resultCount, 4)
        screen.destroy()
    }

    // ── No category: tag hidden; Accessible name is the title only ──
    function test_noCategory() {
        var screen = createScreen("query: 'x'; " +
                                  "results: [ { id: 'note', title: 'notes.txt' } ]")
        var row0 = screen.resultRows.itemAt(0)
        compare(screen.categoryLabel(row0.modelData), "")
        compare(row0.Accessible.name, "notes.txt")
        screen.destroy()
    }

    // ── Result activation: click, Enter and Space emit the id ──────
    function test_resultActivation() {
        var screen = createScreen("query: 'x'; " +
                                  "results: [ { id: 'calc', title: 'Calculator', category: 'Apps' }, " +
                                  "{ id: 'report', title: 'Report.pdf', category: 'Files' }, " +
                                  "{ id: 'brightness', title: 'Brightness', category: 'Settings' } ]")
        wait(100) // window activation for key delivery
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'resultActivated' }",
            screen, "resultSpy")
        spy.target = screen

        // Mouse click on the first result
        var row0 = screen.resultRows.itemAt(0)
        mouseClick(row0, row0.width / 2, row0.height / 2)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "calc")

        // Enter on the second result
        var row1 = screen.resultRows.itemAt(1)
        row1.forceActiveFocus()
        keyClick(Qt.Key_Return)
        compare(spy.count, 2)
        compare(spy.signalArguments[1][0], "report")

        // Space on the third result
        var row2 = screen.resultRows.itemAt(2)
        row2.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spy.count, 3)
        compare(spy.signalArguments[2][0], "brightness")

        screen.destroy()
    }

    // ── Recent searches: chips render; click/Enter emit the text ───
    function test_recentSearches() {
        var screen = createScreen("recentSearches: [ 'Calculator', 'VPN settings', 'Report.pdf' ]")
        wait(100)
        verify(screen.recentChips.count === 3)
        var chip0 = screen.recentChips.itemAt(0)
        verify(chip0.visible)
        compare(chip0.Accessible.name, "Calculator")

        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'recentSearchActivated' }",
            screen, "recentSpy")
        spy.target = screen

        // Mouse click
        mouseClick(chip0, chip0.width / 2, chip0.height / 2)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "Calculator")

        // Enter on the second chip
        var chip1 = screen.recentChips.itemAt(1)
        chip1.forceActiveFocus()
        keyClick(Qt.Key_Return)
        compare(spy.count, 2)
        compare(spy.signalArguments[1][0], "VPN settings")

        screen.destroy()
    }

    // ── Query binding: host property drives the field; typing updates ──
    function test_queryBinding() {
        var screen = createScreen("results: [ { id: 'a', title: 'Alpha', category: 'Apps' } ]")
        wait(100) // let bindings settle

        // Host query renders in the field
        screen.query = "al"
        wait(50)
        compare(screen.searchField.text, "al")

        // Typing in the field updates the query property (live results
        // contract: the host reads `query`)
        screen.query = ""
        wait(50)
        screen.searchField.forceActiveFocus()
        keyClick(Qt.Key_T)
        keyClick(Qt.Key_E)
        compare(screen.query, "te")
        compare(screen.searchField.text, "te")

        screen.destroy()
    }

    // ── Empty states: start-typing hint + no-results hint ──────────
    function test_emptyStates() {
        // No query, no recents → start-typing hint (with offline caption)
        var screen = createScreen()
        verify(screen.noQueryHint.visible)
        verify(!screen.noResultsHint.visible)

        // Query with no results → no-results hint + Clear empties the query
        screen.query = "zzz"
        wait(50)
        verify(!screen.noQueryHint.visible)
        verify(screen.noResultsHint.visible)
        verify(screen.noResultsLabel.text.indexOf("zzz") >= 0)
        screen.clearButton.clicked()
        compare(screen.query, "")
        verify(screen.noQueryHint.visible)

        // Recents present + empty query → chips, no start-typing hint
        var screen2 = createScreen("recentSearches: [ 'Calculator' ]")
        verify(!screen2.noQueryHint.visible)
        verify(screen2.recentChips.count === 1)
        screen2.destroy()

        screen.destroy()
    }

    // ── Keyboard navigation: Up/Down move across the results ───────
    function test_keyboardNavigation() {
        var screen = createScreen("query: 'x'; " +
                                  "results: [ { id: 'a', title: 'A', category: 'Apps' }, " +
                                  "{ id: 'b', title: 'B', category: 'Apps' }, " +
                                  "{ id: 'c', title: 'C', category: 'Apps' }, " +
                                  "{ id: 'd', title: 'D', category: 'Apps' } ]")
        wait(100) // window activation for key delivery
        var r0 = screen.resultRows.itemAt(0)
        var r1 = screen.resultRows.itemAt(1)
        var r2 = screen.resultRows.itemAt(2)
        var r3 = screen.resultRows.itemAt(3)

        r0.forceActiveFocus()
        verify(r0.activeFocus)
        keyClick(Qt.Key_Down)
        verify(r1.activeFocus, "Down must move focus to the next result")
        keyClick(Qt.Key_Down)
        verify(r2.activeFocus, "Down must move focus to the next result")
        keyClick(Qt.Key_Up)
        verify(r1.activeFocus, "Up must move focus to the previous result")

        // Wrapping: Up from the first row lands on the last, Down from
        // the last wraps to the first
        r0.forceActiveFocus()
        keyClick(Qt.Key_Up)
        verify(r3.activeFocus, "Up must wrap around to the last result")
        keyClick(Qt.Key_Down)
        verify(r0.activeFocus, "Down must wrap around to the first result")

        screen.destroy()
    }

    // ── Accessibility roles ────────────────────────────────────────
    function test_accessibleRoles() {
        var screen = createScreen("query: 'x'; " +
                                  "results: [ { id: 'calc', title: 'Calculator', category: 'Apps' }, " +
                                  "{ id: 'report', title: 'Report.pdf', category: 'Files' } ]")
        // Heading announced for the panel title
        verify(screen.titleLabel.Accessible.role === Accessible.Heading)
        verify(screen.titleLabel.Accessible.name.length > 0)
        // Query field announced as editable text
        verify(screen.searchField.Accessible.role === Accessible.EditableText)
        verify(screen.searchField.Accessible.name.length > 0)
        // Results announced as buttons with the category in the name
        var row0 = screen.resultRows.itemAt(0)
        verify(row0.Accessible.role === Accessible.Button)
        compare(row0.Accessible.name, "Calculator, Apps")
        screen.destroy()
    }

    // ── Keyboard focus reaches the results ─────────────────────────
    function test_keyboardFocus() {
        var screen = createScreen("query: 'x'; " +
                                  "results: [ { id: 'a', title: 'A', category: 'Apps' }, " +
                                  "{ id: 'b', title: 'B', category: 'Apps' } ]")
        wait(100) // let the hosted window activate so Tab reaches the rows
        var hostWindow = _hostWindows[_hostWindows.length - 1]
        var found = { "searchResult0": false, "searchResult1": false }

        for (var tab = 0; tab < 20; ++tab) {
            keyClick(Qt.Key_Tab)
            var focusItem = hostWindow.activeFocusItem
            if (focusItem && focusItem.objectName)
                found[focusItem.objectName] = true
        }

        verify(found["searchResult0"], "focus must reach the search results")
        verify(found["searchResult1"], "focus must reach all search results")

        screen.destroy()
    }

    // ── Escape is deliberately unmapped (no signal fires, no state change) ──
    function test_noEscapeMapping() {
        var screen = createScreen("query: 'x'; " +
                                  "results: [ { id: 'a', title: 'A', category: 'Apps' } ]")
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'resultActivated' }",
            screen, "escSpy")
        spy.target = screen

        // Escape with a result focused must not activate anything and
        // must not dismiss or alter the query (the host owns dismissal)
        screen.resultRows.itemAt(0).forceActiveFocus()
        keyClick(Qt.Key_Escape)
        compare(spy.count, 0)
        compare(screen.query, "x")

        screen.destroy()
    }

    // ── MissionPage / MissionWindow integration ────────────────────
    function test_missionPageIntegration() {
        var page = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionPage { pageTitle: 'Search'; Search { objectName: 'searchInPage' } }",
            root, "searchInPage")
        verify(page !== null)
        verify(page.data.length > 0)
        page.destroy()
    }

    function test_missionWindowIntegration() {
        var screen = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionWindow { width: 1280; height: 720; Search { objectName: 'searchInWindow' } }",
            root, "searchInWindow")
        verify(screen !== null)
        verify(screen.width > 0)
        screen.destroy()
    }

    // ── Reduced motion does not break rendering ────────────────────
    function test_reducedMotion() {
        var screen = createScreen("query: 'x'; " +
                                  "results: [ { id: 'a', title: 'A', category: 'Apps' }, " +
                                  "{ id: 'b', title: 'B', category: 'Apps' } ]; " +
                                  "recentSearches: [ 'A' ]")
        screen.reducedMotion = true
        verify(screen.resultRows.count === 2)
        verify(screen.recentChips.count === 1)
        verify(screen.searchPanel.visible)
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
