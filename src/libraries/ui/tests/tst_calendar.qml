// Mission OS — Calendar (MOS-DES-006) QtTest suite
//
// Runtime validation of the Calendar overlay screen. Follows the
// foundation smoke-test pattern (tests/tst_smoke.qml), the Desktop
// family suites (tests/tst_desktop.qml, tst_workspace_switcher.qml,
// tst_notifications.qml, tst_quick_settings.qml, tst_search.qml) and
// docs/engineering/TESTING_STRATEGY.md (QML → Qt Test / qmltestrunner).
//
// Coverage:
//   - screen loads without QML errors (token singletons resolve)
//   - MissionTheme works; light/dark rendering bindings re-evaluate
//   - overlay treatment: scrim + top-right panel with the month title
//     (the taskbar Calendar function — 02_DESKTOP.md §Taskbar)
//   - 42-cell month grid renders; weekday header is localized
//     Sunday-first (7 labels)
//   - today is marked (Accessible name carries ", today") and the
//     today cell is focused on load (keyboard-first)
//   - month navigation: Prev / Next move the anchor (and wrap across
//     year boundaries); the header follows the anchor
//   - the date-picker selection step: click, Enter and Space emit
//     dateSelected(iso) and record selectedDate (visible caption)
//   - host-pinned anchor (currentDate) drives the grid like the
//     Desktop clock contract
//   - keyboard navigation: arrows move across the 7-day grid
//     (Left/Right ±1, Up/Down ±7, wrapping)
//   - accessibility roles (heading; Prev/Next buttons; day cells
//     announced as buttons with the full date + state tags)
//   - Escape is deliberately unmapped (no signal fires, no state
//     change — the host owns overlay dismissal)
//   - MissionPage / MissionWindow integration introduces no runtime errors
//   - reduced motion does not break rendering
//
// Notes on createScreen(extra): every extra is a single QML property
// assignment (the validated family pattern). Where a test needs several
// properties, they are separated with semicolons — commas are not valid
// between QML property assignments (empirically verified on this
// toolchain).
//
// Many tests pin the anchor to February 2027 so the grid is fully
// deterministic (no collision with the real "today" regardless of when
// the suite runs); the today-related tests use the real current date.
//
// Run via qmltestrunner (see CMakeLists.txt CTest registration):
//   qmltestrunner -import <build>/src/libraries/ui/qml \
//                 -input src/libraries/ui/tests/tst_calendar.qml
//
// Exit code: 0 = all checks passed; non-zero = failure (CI gate).

import QtQuick
import QtTest
import org.mission.ui 1.0

TestCase {
    id: root
    name: "Calendar"

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
                     "    Calendar { id: screen; width: 1280; height: 720; " +
                     (extra || "") + " }\n" +
                     "}"
        var host = Qt.createQmlObject(source, root, "calendarHost")
        _hostWindows.push(host)
        return host.screen
    }

    // ── Screen loads; tokens resolve; no QML errors ────────────────
    function test_screenLoads() {
        var screen = createScreen()
        verify(screen !== null)
        verify(screen.height > 0)
        // Overlay treatment: scrim + top-right panel + month heading
        verify(screen.backdropScrim !== null)
        verify(screen.calendarPanel !== null)
        verify(screen.monthLabel.text.length > 0)
        // Weekday header (Sunday-first, localized) + 42-cell grid
        verify(screen.weekdayLabels.length === 7)
        verify(screen.weekdayLabels[0].length > 0)
        verify(screen.dayRepeater.count === 42)
        // Keyboard-first: the today cell is focused on load
        verify(screen.todayCellIndex >= 0)
        verify(screen.dayRepeater.itemAt(screen.todayCellIndex).activeFocus,
               "the today cell must be focused on load")
        screen.destroy()
    }

    // ── MissionTheme light/dark rendering bindings ─────────────────
    function test_themeLightAndDark() {
        var screen = createScreen("currentDate: new Date(2027, 1, 10)")
        // Disable the cells' Behavior on color (reduced-motion) so theme
        // flips apply instantly instead of animating over Motion.colorChange
        screen.reducedMotion = true
        var cell0 = screen.dayRepeater.itemAt(0)

        MissionTheme.darkMode = false
        verify(Qt.colorEqual(screen.backdropScrim.color, Colors.scrim))
        verify(Qt.colorEqual(screen.calendarPanel.color, MissionTheme.surface))
        verify(Qt.colorEqual(screen.monthLabel.color, MissionTheme.textPrimary))
        // Unselected in-month cells are transparent in both themes
        verify(Qt.colorEqual(cell0.color, "transparent"))

        MissionTheme.darkMode = true
        verify(Qt.colorEqual(screen.monthLabel.color, MissionTheme.textPrimary))
        verify(Qt.colorEqual(screen.calendarPanel.color, MissionTheme.surface))
        verify(Qt.colorEqual(cell0.color, "transparent"))

        MissionTheme.darkMode = false
        screen.destroy()
    }

    // ── Month navigation: Prev / Next move the anchor, wrap years ──
    function test_monthNavigation() {
        var screen = createScreen("currentDate: new Date(2027, 1, 10)") // February 2027
        compare(screen.monthLabel.text, "February 2027")

        screen.nextButton.clicked()
        compare(screen.monthLabel.text, "March 2027")

        screen.prevButton.clicked()
        compare(screen.monthLabel.text, "February 2027")

        // Year boundary: from January 2027, Prev wraps to December 2026
        screen.currentDate = new Date(2027, 0, 1)
        compare(screen.monthLabel.text, "January 2027")
        screen.prevButton.clicked()
        compare(screen.monthLabel.text, "December 2026")

        screen.destroy()
    }

    // ── Today is marked and rendered in the current month ──────────
    function test_todayRendered() {
        var screen = createScreen()
        // The today cell carries the ", today" tag in its Accessible
        // name (color is never the only indicator)
        var todayCell = screen.dayRepeater.itemAt(screen.todayCellIndex)
        verify(todayCell.Accessible.name.indexOf(", today") >= 0)
        verify(screen.dayCells[screen.todayCellIndex].isToday)
        screen.destroy()
    }

    // ── Date selection: click, Enter and Space emit the ISO date ───
    function test_dateSelection() {
        // Pinned to February 2027: fully deterministic (never collides
        // with the real today). Cell [offset] is always the 1st.
        var screen = createScreen("currentDate: new Date(2027, 1, 10)")
        wait(100) // window activation for key delivery
        var offset = new Date(2027, 1, 1).getDay()
        var cell0 = screen.dayRepeater.itemAt(offset)
        verify(cell0 !== null)

        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'dateSelected' }",
            screen, "dateSpy")
        spy.target = screen

        // Mouse click on the 1st of the month
        mouseClick(cell0, cell0.width / 2, cell0.height / 2)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "2027-02-01")
        compare(screen.selectedDate, "2027-02-01")
        // Selection is visible (caption) and announced on the cell
        verify(screen.selectionCaption.visible)
        verify(screen.selectionCaption.text.indexOf("2027-02-01") >= 0)
        verify(cell0.Accessible.name.indexOf(", selected") >= 0)

        // Enter on another day (the 2nd)
        var cell1 = screen.dayRepeater.itemAt(offset + 1)
        cell1.forceActiveFocus()
        keyClick(Qt.Key_Return)
        compare(spy.count, 2)
        compare(spy.signalArguments[1][0], "2027-02-02")
        compare(screen.selectedDate, "2027-02-02")

        // Space on the 3rd
        var cell2 = screen.dayRepeater.itemAt(offset + 2)
        cell2.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spy.count, 3)
        compare(spy.signalArguments[2][0], "2027-02-03")

        screen.destroy()
    }

    // ── Host-pinned anchor drives the grid (clock contract) ────────
    function test_hostPinnedDate() {
        var screen = createScreen()
        wait(100) // window activation for key delivery
        // Default: the grid shows the current month
        var defaultTitle = screen.monthLabel.text
        verify(defaultTitle.length > 0)

        // Host pins the anchor; the grid + header follow
        screen.currentDate = new Date(2030, 5, 15)
        compare(screen.monthLabel.text, "June 2030")
        verify(screen.dayRepeater.count === 42)

        // A selection from the pinned month is recorded + emitted
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'dateSelected' }",
            screen, "pinSpy")
        spy.target = screen
        var offset = new Date(2030, 5, 1).getDay()
        screen.dayRepeater.itemAt(offset).forceActiveFocus()
        keyClick(Qt.Key_Return)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "2030-06-01")

        screen.destroy()
    }

    // ── Keyboard navigation: arrows move across the 7-day grid ─────
    function test_keyboardNavigation() {
        var screen = createScreen("currentDate: new Date(2027, 1, 10)")
        wait(100) // window activation for key delivery
        var offset = new Date(2027, 1, 1).getDay()
        var day1 = screen.dayRepeater.itemAt(offset)

        day1.forceActiveFocus()
        verify(day1.activeFocus)
        keyClick(Qt.Key_Right)
        verify(screen.dayRepeater.itemAt(offset + 1).activeFocus,
               "Right must move focus to the next day")
        keyClick(Qt.Key_Down)
        verify(screen.dayRepeater.itemAt(offset + 1 + 7).activeFocus,
               "Down must move focus down a week")
        keyClick(Qt.Key_Up)
        verify(screen.dayRepeater.itemAt(offset + 1).activeFocus,
               "Up must move focus up a week")

        // Wrapping: Left from the first cell wraps to the last
        screen.focusDay(0)
        verify(screen.dayRepeater.itemAt(0).activeFocus)
        keyClick(Qt.Key_Left)
        verify(screen.dayRepeater.itemAt(41).activeFocus,
               "Left must wrap around to the last cell")
        keyClick(Qt.Key_Right)
        verify(screen.dayRepeater.itemAt(0).activeFocus,
               "Right must wrap around to the first cell")

        screen.destroy()
    }

    // ── Accessibility roles ────────────────────────────────────────
    function test_accessibleRoles() {
        var screen = createScreen("currentDate: new Date(2027, 1, 10)")
        // Heading announced for the month title
        verify(screen.monthLabel.Accessible.role === Accessible.Heading)
        verify(screen.monthLabel.Accessible.name.length > 0)
        // Prev / Next announced with their month descriptions
        verify(screen.prevButton.Accessible.role === Accessible.Button)
        compare(screen.prevButton.Accessible.name, "Previous month")
        compare(screen.nextButton.Accessible.name, "Next month")
        // Day cells announced as buttons with the full date
        var offset = new Date(2027, 1, 1).getDay()
        var day1 = screen.dayRepeater.itemAt(offset)
        verify(day1.Accessible.role === Accessible.Button)
        verify(day1.Accessible.name.indexOf("February 1") >= 0)
        screen.destroy()
    }

    // ── Keyboard focus reaches the day cells ───────────────────────
    function test_keyboardFocus() {
        var screen = createScreen()
        wait(100) // let the hosted window activate so Tab reaches the cells
        var hostWindow = _hostWindows[_hostWindows.length - 1]
        var found = { "calendarDay0": false, "calendarDay15": false,
                      "calendarDay30": false }

        for (var tab = 0; tab < 50; ++tab) {
            keyClick(Qt.Key_Tab)
            var focusItem = hostWindow.activeFocusItem
            if (focusItem && focusItem.objectName)
                found[focusItem.objectName] = true
        }

        verify(found["calendarDay0"], "focus must reach the calendar cells")
        verify(found["calendarDay15"], "focus must reach the calendar cells")
        verify(found["calendarDay30"], "focus must reach the calendar cells")

        screen.destroy()
    }

    // ── Escape is deliberately unmapped (no signal fires) ──────────
    function test_noEscapeMapping() {
        var screen = createScreen("currentDate: new Date(2027, 1, 10)")
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'dateSelected' }",
            screen, "escSpy")
        spy.target = screen

        // Escape with a day focused must not pick it and must not
        // dismiss or alter the anchor (the host owns dismissal)
        screen.dayRepeater.itemAt(20).forceActiveFocus()
        keyClick(Qt.Key_Escape)
        compare(spy.count, 0)
        compare(screen.selectedDate, "")

        screen.destroy()
    }

    // ── MissionPage / MissionWindow integration ────────────────────
    function test_missionPageIntegration() {
        var page = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionPage { pageTitle: 'Calendar'; Calendar { objectName: 'calendarInPage' } }",
            root, "calendarInPage")
        verify(page !== null)
        verify(page.data.length > 0)
        page.destroy()
    }

    function test_missionWindowIntegration() {
        var screen = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionWindow { width: 1280; height: 720; Calendar { objectName: 'calendarInWindow' } }",
            root, "calendarInWindow")
        verify(screen !== null)
        verify(screen.width > 0)
        screen.destroy()
    }

    // ── Reduced motion does not break rendering ────────────────────
    function test_reducedMotion() {
        var screen = createScreen()
        screen.reducedMotion = true
        verify(screen.dayRepeater.count === 42)
        verify(screen.calendarPanel.visible)
        verify(screen.weekdayLabels.length === 7)
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
