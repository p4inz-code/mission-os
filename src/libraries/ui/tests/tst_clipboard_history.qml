// Mission OS — Clipboard History (MOS-DES-007) QtTest suite
//
// Runtime validation of the Clipboard History overlay screen. Follows
// the foundation smoke-test pattern (tests/tst_smoke.qml), the Desktop
// family suites (tests/tst_desktop.qml, tst_notifications.qml,
// tst_quick_settings.qml, tst_search.qml, tst_calendar.qml) and
// docs/engineering/TESTING_STRATEGY.md (QML → Qt Test / qmltestrunner).
//
// Coverage:
//   - screen loads without QML errors (token singletons resolve)
//   - MissionTheme works; light/dark rendering bindings re-evaluate
//   - overlay treatment: scrim + top-right panel with a
//     "Clipboard History" heading (registry §19 Global Overlay)
//   - entries render from the host model (type tags Text/Image, text
//     preview, time) with Accessible names carrying pinned/sensitive
//     state (color is never the only indicator)
//   - the entry action step: click, Enter and Space emit
//     entryActivated(id)
//   - pin toggle: the Pin button emits pinToggled(id); pinned state
//     renders from the model and re-evaluates when the host flips it
//   - sensitive entries carry a "Sensitive" tag + "(sensitive)" name
//   - Clear all emits clearAllRequested and is disabled when empty
//   - searchable history: the search field filters locally
//     (case-insensitive text match); no-match overlay + Clear search
//   - history may be disabled: historyEnabled=false hides the list
//     behind a hint (reference: "Clipboard history may be disabled")
//   - keyboard navigation: Up/Down move focus across the rows
//     (wrapping)
//   - accessibility roles (heading; editable text field; entries and
//     pin buttons announced as buttons)
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
//                 -input src/libraries/ui/tests/tst_clipboard_history.qml
//
// Exit code: 0 = all checks passed; non-zero = failure (CI gate).

import QtQuick
import QtTest
import org.mission.ui 1.0

TestCase {
    id: root
    name: "ClipboardHistory"

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
                     "    ClipboardHistory { id: screen; width: 1280; height: 720; " +
                     (extra || "") + " }\n" +
                     "}"
        var host = Qt.createQmlObject(source, root, "clipboardHost")
        _hostWindows.push(host)
        return host.screen
    }

    // Recursive objectName lookup for the Pin buttons nested inside the
    // entry rows (the family tests address interactive children by
    // objectName; the pin button is one level inside the row content).
    function findChildByName(item, name) {
        if (item === null || item === undefined)
            return null
        if (item.objectName === name)
            return item
        for (var i = 0; i < item.children.length; ++i) {
            var found = findChildByName(item.children[i], name)
            if (found !== null)
                return found
        }
        return null
    }

    // ── Screen loads; tokens resolve; no QML errors ────────────────
    function test_screenLoads() {
        var screen = createScreen("entries: [ { id: 'a', text: 'Alpha note', time: '10:30' } ]")
        verify(screen !== null)
        verify(screen.height > 0)
        // Overlay treatment: scrim + top-right panel + heading
        verify(screen.backdropScrim !== null)
        verify(screen.historyPanel !== null)
        compare(screen.titleLabel.text, "Clipboard History")
        // Clear all is disabled while the history is empty; the search
        // field is focused on load (searchable history — keyboard-first)
        verify(screen.clearAllButton !== null)
        verify(screen.searchField !== null)
        verify(screen.searchField.activeFocus,
               "the search field must be focused on load")
        // Privacy footer always visible (reference: passwords are never
        // permanently stored)
        verify(screen.privacyCaption.visible)
        verify(screen.privacyCaption.text.length > 0)
        screen.destroy()
    }

    // ── MissionTheme light/dark rendering bindings ─────────────────
    function test_themeLightAndDark() {
        var screen = createScreen("entries: [ { id: 'a', text: 'Alpha note' }, " +
                                  "{ id: 'b', text: 'Beta link' } ]")
        // Disable the rows' Behavior on color (reduced-motion) so theme
        // flips apply instantly instead of animating over Motion.colorChange
        screen.reducedMotion = true
        var row0 = screen.entryRows.itemAt(0)

        MissionTheme.darkMode = false
        verify(Qt.colorEqual(screen.backdropScrim.color, Colors.scrim))
        verify(Qt.colorEqual(screen.historyPanel.color, MissionTheme.surface))
        verify(Qt.colorEqual(screen.titleLabel.color, MissionTheme.textPrimary))
        verify(Qt.colorEqual(row0.color, MissionTheme.surfaceDim))

        MissionTheme.darkMode = true
        verify(Qt.colorEqual(row0.color, MissionTheme.surfaceDim))
        verify(Qt.colorEqual(screen.titleLabel.color, MissionTheme.textPrimary))
        verify(Qt.colorEqual(screen.historyPanel.color, MissionTheme.surface))

        MissionTheme.darkMode = false
        screen.destroy()
    }

    // ── Entries render type tags, state tags and Accessible names ──
    function test_entriesRender() {
        var screen = createScreen("entries: [ { id: 'a', text: 'Alpha note', time: '10:30', pinned: true }, " +
                                  "{ id: 'b', text: 'Beta link', sensitive: true }, " +
                                  "{ id: 'c', image: 'data:image/png;base64,AAAA', time: '09:00' } ]")
        verify(screen.entryRows.count === 3)
        var row0 = screen.entryRows.itemAt(0)
        var row1 = screen.entryRows.itemAt(1)
        var row2 = screen.entryRows.itemAt(2)
        verify(row0 !== null && row1 !== null && row2 !== null)
        verify(row0.visible && row1.visible && row2.visible)
        // Type helpers: text vs image support (reference)
        compare(screen.typeLabel(row0.modelData), "Text")
        compare(screen.typeLabel(row2.modelData), "Image")
        // State helpers (host-driven, never mutated here)
        verify(screen.isPinned(row0.modelData))
        verify(!screen.isPinned(row1.modelData))
        verify(screen.isSensitive(row1.modelData))
        verify(!screen.isSensitive(row0.modelData))
        // Accessible names carry the content + type + state tags (color
        // is never the only indicator)
        compare(row0.Accessible.name, "Alpha note, Text, pinned")
        compare(row1.Accessible.name, "Beta link, Text, sensitive")
        compare(row2.Accessible.name, "Image")
        // Preview helper: text elided for readability; type fallback
        compare(screen.previewFor(row0.modelData), "Alpha note")
        compare(screen.previewFor(row2.modelData), "Image")
        compare(screen.entryCount, 3)
        screen.destroy()
    }

    // ── Entry activation: click, Enter and Space emit the id ───────
    function test_entryActivation() {
        var screen = createScreen("entries: [ { id: 'a', text: 'Alpha note' }, " +
                                  "{ id: 'b', text: 'Beta link' }, " +
                                  "{ id: 'c', text: 'Gamma draft' } ]")
        wait(100) // window activation for key delivery
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'entryActivated' }",
            screen, "entrySpy")
        spy.target = screen

        // Mouse click on the first row
        var row0 = screen.entryRows.itemAt(0)
        mouseClick(row0, row0.width / 2, row0.height / 2)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "a")

        // Enter on the second row
        var row1 = screen.entryRows.itemAt(1)
        row1.forceActiveFocus()
        keyClick(Qt.Key_Return)
        compare(spy.count, 2)
        compare(spy.signalArguments[1][0], "b")

        // Space on the third row
        var row2 = screen.entryRows.itemAt(2)
        row2.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spy.count, 3)
        compare(spy.signalArguments[2][0], "c")

        screen.destroy()
    }

    // ── Pin toggle: emits the id; pinned state is host-rendered ────
    function test_pinToggle() {
        var screen = createScreen("entries: [ { id: 'a', text: 'Alpha note', pinned: true }, " +
                                  "{ id: 'b', text: 'Beta link', pinned: false } ]")
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'pinToggled' }",
            screen, "pinSpy")
        spy.target = screen

        var pin0 = findChildByName(screen.entryRows.itemAt(0), "clipPin0")
        var pin1 = findChildByName(screen.entryRows.itemAt(1), "clipPin1")
        verify(pin0 !== null && pin1 !== null)

        // Pinned state reflects the model (button text + Accessible)
        compare(pin0.text, "Pinned")
        compare(pin1.text, "Pin")

        // Clicking emits the entry id
        pin0.clicked()
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "a")
        pin1.clicked()
        compare(spy.count, 2)
        compare(spy.signalArguments[1][0], "b")

        // The screen never mutates the model — the host flips it and the
        // rendering re-evaluates
        screen.entries = [ { id: "a", text: "Alpha note", pinned: false } ]
        wait(50)
        compare(screen.entryRows.itemAt(0).Accessible.name, "Alpha note, Text")
        compare(findChildByName(screen.entryRows.itemAt(0), "clipPin0").text, "Pin")

        screen.destroy()
    }

    // ── Sensitive entries: tag + "(sensitive)" Accessible name ─────
    function test_sensitiveTag() {
        var screen = createScreen("entries: [ { id: 'a', text: 'Alpha note' }, " +
                                  "{ id: 'b', text: 'one-time-code-4821', sensitive: true } ]")
        var row1 = screen.entryRows.itemAt(1)
        verify(screen.isSensitive(row1.modelData))
        verify(row1.Accessible.name.indexOf(", sensitive") >= 0)
        compare(screen.entryRows.itemAt(0).Accessible.name, "Alpha note, Text")
        screen.destroy()
    }

    // ── Clear all: signal + disabled while empty ───────────────────
    function test_clearAll() {
        var screen = createScreen("entries: [ { id: 'a', text: 'Alpha note' } ]")
        verify(screen.clearAllButton.enabled)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'clearAllRequested' }",
            screen, "clearSpy")
        spy.target = screen
        screen.clearAllButton.clicked()
        compare(spy.count, 1)

        // Empty history disables the action
        screen.entries = []
        wait(50)
        verify(!screen.clearAllButton.enabled)
        verify(screen.emptyHint.visible)

        screen.destroy()
    }

    // ── Searchable history: local filter + no-match overlay ────────
    function test_searchFilter() {
        var screen = createScreen("entries: [ { id: 'a', text: 'Alpha note' }, " +
                                  "{ id: 'b', text: 'Beta link' }, " +
                                  "{ id: 'c', text: 'Alpha draft' } ]")
        // Empty query shows the whole history
        verify(screen.entryRows.count === 3)
        verify(!screen.noMatchesHint.visible)

        // Case-insensitive text match narrows the list
        screen.searchText = "alpha"
        wait(50)
        verify(screen.entryRows.count === 2)

        // No match → explanatory overlay with a Clear action
        screen.searchText = "zzz-not-there"
        wait(50)
        verify(screen.entryRows.count === 0)
        verify(screen.noMatchesHint.visible)
        screen.clearSearchButton.clicked()
        compare(screen.searchText, "")
        verify(screen.entryRows.count === 3)

        screen.destroy()
    }

    // ── History may be disabled (reference) ────────────────────────
    function test_historyDisabled() {
        var screen = createScreen("entries: [ { id: 'a', text: 'Alpha note' } ]")
        verify(!screen.disabledHint.visible)
        verify(screen.searchField.visible)
        verify(!screen.emptyHint.visible)

        screen.historyEnabled = false
        wait(50)
        verify(screen.disabledHint.visible)
        verify(!screen.searchField.visible)
        verify(!screen.emptyHint.visible)
        verify(screen.privacyCaption.visible)

        screen.historyEnabled = true
        wait(50)
        verify(!screen.disabledHint.visible)
        verify(screen.searchField.visible)

        screen.destroy()
    }

    // ── Keyboard navigation: Up/Down move across the rows ──────────
    function test_keyboardNavigation() {
        var screen = createScreen("entries: [ { id: 'a', text: 'Alpha note' }, " +
                                  "{ id: 'b', text: 'Beta link' }, " +
                                  "{ id: 'c', text: 'Gamma draft' } ]")
        wait(100) // window activation for key delivery
        var r0 = screen.entryRows.itemAt(0)
        var r1 = screen.entryRows.itemAt(1)
        var r2 = screen.entryRows.itemAt(2)

        r0.forceActiveFocus()
        verify(r0.activeFocus)
        keyClick(Qt.Key_Down)
        verify(r1.activeFocus, "Down must move focus to the next row")
        keyClick(Qt.Key_Down)
        verify(r2.activeFocus, "Down must move focus to the next row")
        keyClick(Qt.Key_Up)
        verify(r1.activeFocus, "Up must move focus to the previous row")

        // Wrapping: Up from the first row lands on the last
        r0.forceActiveFocus()
        keyClick(Qt.Key_Up)
        verify(r2.activeFocus, "Up must wrap around to the last row")
        keyClick(Qt.Key_Down)
        verify(r0.activeFocus, "Down must wrap around to the first row")

        screen.destroy()
    }

    // ── Accessibility roles ────────────────────────────────────────
    function test_accessibleRoles() {
        var screen = createScreen("entries: [ { id: 'a', text: 'Alpha note', pinned: true }, " +
                                  "{ id: 'b', text: 'Beta link' } ]")
        // Heading announced for the panel title
        verify(screen.titleLabel.Accessible.role === Accessible.Heading)
        verify(screen.titleLabel.Accessible.name.length > 0)
        // Search field announced as editable text
        verify(screen.searchField.Accessible.role === Accessible.EditableText)
        verify(screen.searchField.Accessible.name.length > 0)
        // Entries announced as buttons with content + state in the name
        var row0 = screen.entryRows.itemAt(0)
        verify(row0.Accessible.role === Accessible.Button)
        compare(row0.Accessible.name, "Alpha note, Text, pinned")
        // Pin buttons announced with their state
        var pin1 = findChildByName(screen.entryRows.itemAt(1), "clipPin1")
        verify(pin1.Accessible.role === Accessible.Button)
        compare(pin1.Accessible.name, "Pin")
        screen.destroy()
    }

    // ── Keyboard focus reaches the rows and pin buttons ────────────
    function test_keyboardFocus() {
        var screen = createScreen("entries: [ { id: 'a', text: 'Alpha note' }, " +
                                  "{ id: 'b', text: 'Beta link' } ]")
        wait(100) // let the hosted window activate so Tab reaches the rows
        var hostWindow = _hostWindows[_hostWindows.length - 1]
        var found = { "clipEntry0": false, "clipEntry1": false,
                      "clipPin0": false, "clipPin1": false }

        for (var tab = 0; tab < 40; ++tab) {
            keyClick(Qt.Key_Tab)
            var focusItem = hostWindow.activeFocusItem
            if (focusItem && focusItem.objectName)
                found[focusItem.objectName] = true
        }

        verify(found["clipEntry0"], "focus must reach the clipboard rows")
        verify(found["clipEntry1"], "focus must reach the clipboard rows")
        verify(found["clipPin0"], "focus must reach the pin buttons")
        verify(found["clipPin1"], "focus must reach the pin buttons")

        screen.destroy()
    }

    // ── Escape is deliberately unmapped (no signal fires) ──────────
    function test_noEscapeMapping() {
        var screen = createScreen("entries: [ { id: 'a', text: 'Alpha note' } ]")
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'entryActivated' }",
            screen, "escSpy")
        spy.target = screen

        // Escape with a row focused must not activate it and must not
        // dismiss or alter the search (the host owns dismissal)
        screen.entryRows.itemAt(0).forceActiveFocus()
        keyClick(Qt.Key_Escape)
        compare(spy.count, 0)
        compare(screen.searchText, "")

        screen.destroy()
    }

    // ── MissionPage / MissionWindow integration ────────────────────
    function test_missionPageIntegration() {
        var page = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionPage { pageTitle: 'Clipboard History'; ClipboardHistory { objectName: 'clipboardInPage' } }",
            root, "clipboardInPage")
        verify(page !== null)
        verify(page.data.length > 0)
        page.destroy()
    }

    function test_missionWindowIntegration() {
        var screen = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionWindow { width: 1280; height: 720; ClipboardHistory { objectName: 'clipboardInWindow' } }",
            root, "clipboardInWindow")
        verify(screen !== null)
        verify(screen.width > 0)
        screen.destroy()
    }

    // ── Reduced motion does not break rendering ────────────────────
    function test_reducedMotion() {
        var screen = createScreen("entries: [ { id: 'a', text: 'Alpha note' }, " +
                                  "{ id: 'b', text: 'Beta link' } ]")
        screen.reducedMotion = true
        verify(screen.entryRows.count === 2)
        verify(screen.historyPanel.visible)
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
