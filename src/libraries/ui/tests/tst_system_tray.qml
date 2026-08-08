// Mission OS — System Tray (MOS-DES-008) QtTest suite
//
// Runtime validation of the System Tray overlay screen. Follows
// the foundation smoke-test pattern (tests/tst_smoke.qml), the Desktop
// family suites (tests/tst_desktop.qml, tst_notifications.qml,
// tst_quick_settings.qml, tst_search.qml, tst_calendar.qml,
// tst_clipboard_history.qml) and docs/engineering/TESTING_STRATEGY.md
// (QML → Qt Test / qmltestrunner).
//
// Coverage:
//   - screen loads without QML errors (token singletons resolve)
//   - MissionTheme works; light/dark rendering bindings re-evaluate
//   - overlay treatment: scrim + top-right panel with a "System Tray"
//     heading (02_DESKTOP.md §System Tray)
//   - tray items render from the host model (label fallback to id,
//     status text, level dot + tag) with Accessible names carrying
//     label + status + level (color is never the only indicator)
//   - level text tag logic: shown when the level is notable
//     (warning/critical) or when the host supplied no status text;
//     hidden for OK items that carry a status
//   - the activation step: click, Enter and Space emit
//     trayItemActivated(id)
//   - defensive handling of incomplete model data (missing label /
//     status / level fields degrade to the documented defaults)
//   - empty tray degrades to a neutral hint
//   - keyboard navigation: Up/Down move focus across the rows
//     (wrapping)
//   - accessibility roles (heading; rows announced as buttons)
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
//                 -input src/libraries/ui/tests/tst_system_tray.qml
//
// Exit code: 0 = all checks passed; non-zero = failure (CI gate).

import QtQuick
import QtTest
import org.mission.ui 1.0

TestCase {
    id: root
    name: "SystemTray"

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
                     "    SystemTray { id: screen; width: 1280; height: 720; " +
                     (extra || "") + " }\n" +
                     "}"
        var host = Qt.createQmlObject(source, root, "trayHost")
        _hostWindows.push(host)
        return host.screen
    }

    // ── Screen loads; tokens resolve; no QML errors ────────────────
    function test_screenLoads() {
        var screen = createScreen("trayItems: [ { id: 'network', label: 'Network', status: 'Connected' } ]")
        verify(screen !== null)
        verify(screen.height > 0)
        // Overlay treatment: scrim + top-right panel + heading
        verify(screen.backdropScrim !== null)
        verify(screen.trayPanel !== null)
        compare(screen.titleLabel.text, "System Tray")
        // The first tray item is focused on load (keyboard-first)
        verify(screen.trayRows.itemAt(0).activeFocus,
               "the first tray item must be focused on load")
        // Privacy footer always visible (reference: applications must
        // not add tray icons without user consent)
        verify(screen.privacyCaption.visible)
        verify(screen.privacyCaption.text.length > 0)
        screen.destroy()
    }

    // ── MissionTheme light/dark rendering bindings ─────────────────
    function test_themeLightAndDark() {
        var screen = createScreen("trayItems: [ { id: 'network', label: 'Network', status: 'Connected' }, " +
                                  "{ id: 'battery', label: 'Battery', status: '12%', level: 'warning' } ]")
        // Disable the rows' Behavior on color (reduced-motion) so theme
        // flips apply instantly instead of animating over Motion.colorChange
        screen.reducedMotion = true
        var row0 = screen.trayRows.itemAt(0)

        MissionTheme.darkMode = false
        verify(Qt.colorEqual(screen.backdropScrim.color, Colors.scrim))
        verify(Qt.colorEqual(screen.trayPanel.color, MissionTheme.surface))
        verify(Qt.colorEqual(screen.titleLabel.color, MissionTheme.textPrimary))
        verify(Qt.colorEqual(row0.color, MissionTheme.surfaceDim))

        MissionTheme.darkMode = true
        verify(Qt.colorEqual(row0.color, MissionTheme.surfaceDim))
        verify(Qt.colorEqual(screen.titleLabel.color, MissionTheme.textPrimary))
        verify(Qt.colorEqual(screen.trayPanel.color, MissionTheme.surface))

        MissionTheme.darkMode = false
        screen.destroy()
    }

    // ── Tray items render labels, statuses, levels and names ───────
    function test_itemsRender() {
        var screen = createScreen("trayItems: [ { id: 'network', label: 'Network', status: 'Connected' }, " +
                                  "{ id: 'battery', label: 'Battery', status: '12%', level: 'warning' }, " +
                                  "{ id: 'updates', status: 'Up to date', level: 'critical' }, " +
                                  "{ id: 'vpn' } ]")
        verify(screen.trayRows.count === 4)
        var row0 = screen.trayRows.itemAt(0)
        var row1 = screen.trayRows.itemAt(1)
        var row2 = screen.trayRows.itemAt(2)
        var row3 = screen.trayRows.itemAt(3)
        verify(row0 !== null && row1 !== null && row2 !== null && row3 !== null)
        verify(row0.visible && row1.visible && row2.visible && row3.visible)
        // Helpers: label falls back to id; status is host text
        compare(screen.labelFor(row0.modelData), "Network")
        compare(screen.statusFor(row0.modelData), "Connected")
        compare(screen.labelFor(row2.modelData), "updates")
        compare(screen.statusFor(row2.modelData), "Up to date")
        // Levels normalize to ok/warning/critical (unknown → ok)
        compare(screen.levelOf(row0.modelData), "ok")
        compare(screen.levelOf(row1.modelData), "warning")
        compare(screen.levelOf(row2.modelData), "critical")
        compare(screen.levelOf(row3.modelData), "ok")
        compare(screen.levelLabel("warning"), "Warning")
        compare(screen.levelLabel("critical"), "Critical")
        compare(screen.levelLabel("ok"), "OK")
        compare(screen.levelColor("warning"), MissionTheme.warning)
        compare(screen.levelColor("critical"), MissionTheme.error)
        compare(screen.levelColor("ok"), MissionTheme.success)
        // Accessible names carry label + status + level (color is
        // never the only indicator — the level is always in the name)
        compare(row0.Accessible.name, "Network, Connected, OK")
        compare(row1.Accessible.name, "Battery, 12%, Warning")
        compare(row2.Accessible.name, "updates, Up to date, Critical")
        compare(row3.Accessible.name, "vpn, OK")
        compare(screen.trayCount, 4)
        screen.destroy()
    }

    // ── Level tag visibility logic (showLevelTag) ──────────────────
    function test_levelTagLogic() {
        var screen = createScreen("trayItems: [ { id: 'a', label: 'Network', status: 'Connected' }, " +
                                  "{ id: 'b', label: 'Battery', status: '12%', level: 'warning' }, " +
                                  "{ id: 'c', label: 'Updates', status: 'Critical', level: 'critical' }, " +
                                  "{ id: 'd', label: 'VPN' } ]")
        // OK + status → no tag (the status text is the indicator)
        verify(!screen.showLevelTag(screen.trayRows.itemAt(0).modelData))
        // Warning/critical → tag always rendered
        verify(screen.showLevelTag(screen.trayRows.itemAt(1).modelData))
        verify(screen.showLevelTag(screen.trayRows.itemAt(2).modelData))
        // No status text → tag rendered even for OK (a state-conveying
        // dot never appears without a non-color indicator)
        verify(screen.showLevelTag(screen.trayRows.itemAt(3).modelData))
        screen.destroy()
    }

    // ── Item activation: click, Enter and Space emit the id ────────
    function test_itemActivation() {
        var screen = createScreen("trayItems: [ { id: 'network', label: 'Network', status: 'Connected' }, " +
                                  "{ id: 'audio', label: 'Audio', status: 'Idle' }, " +
                                  "{ id: 'battery', label: 'Battery', status: '80%' } ]")
        wait(100) // window activation for key delivery
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'trayItemActivated' }",
            screen, "traySpy")
        spy.target = screen

        // Mouse click on the first row
        var row0 = screen.trayRows.itemAt(0)
        mouseClick(row0, row0.width / 2, row0.height / 2)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "network")

        // Enter on the second row
        var row1 = screen.trayRows.itemAt(1)
        row1.forceActiveFocus()
        keyClick(Qt.Key_Return)
        compare(spy.count, 2)
        compare(spy.signalArguments[1][0], "audio")

        // Space on the third row
        var row2 = screen.trayRows.itemAt(2)
        row2.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spy.count, 3)
        compare(spy.signalArguments[2][0], "battery")

        screen.destroy()
    }

    // ── Defensive handling of incomplete model data ────────────────
    function test_defensiveIncompleteData() {
        // Missing label/status/level fields must never break rendering:
        // label falls back to the id, status is omitted from the name,
        // level defaults to ok.
        var screen = createScreen("trayItems: [ { id: 'minimal' }, " +
                                  "{ id: 'x', label: 'X' } ]")
        verify(screen.trayRows.count === 2)
        var row0 = screen.trayRows.itemAt(0)
        var row1 = screen.trayRows.itemAt(1)
        compare(screen.labelFor(row0.modelData), "minimal")
        compare(screen.statusFor(row0.modelData), "")
        compare(screen.levelOf(row0.modelData), "ok")
        compare(row0.Accessible.name, "minimal, OK")
        // Helper-level defensiveness: null/undefined entries resolve to
        // the documented defaults instead of throwing
        compare(screen.labelFor(null), "")
        compare(screen.statusFor(undefined), "")
        compare(screen.levelOf(null), "ok")
        screen.destroy()
    }

    // ── Empty tray degrades to a neutral hint ──────────────────────
    function test_emptyState() {
        var screen = createScreen("trayItems: []")
        verify(screen.trayRows.count === 0)
        verify(screen.emptyHint.visible)
        verify(screen.emptyHint.children.length >= 2)
        verify(screen.privacyCaption.visible)

        // Populating the model hides the hint and shows the rows
        screen.trayItems = [ { id: "network", label: "Network", status: "Connected" } ]
        wait(50)
        verify(screen.trayRows.count === 1)
        verify(!screen.emptyHint.visible)

        // Clearing the model restores the hint
        screen.trayItems = []
        wait(50)
        verify(screen.trayRows.count === 0)
        verify(screen.emptyHint.visible)

        screen.destroy()
    }

    // ── Keyboard navigation: Up/Down move across the rows ──────────
    function test_keyboardNavigation() {
        var screen = createScreen("trayItems: [ { id: 'network', label: 'Network' }, " +
                                  "{ id: 'audio', label: 'Audio' }, " +
                                  "{ id: 'battery', label: 'Battery' } ]")
        wait(100) // window activation for key delivery
        var r0 = screen.trayRows.itemAt(0)
        var r1 = screen.trayRows.itemAt(1)
        var r2 = screen.trayRows.itemAt(2)

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
        var screen = createScreen("trayItems: [ { id: 'network', label: 'Network', status: 'Connected' }, " +
                                  "{ id: 'security', label: 'Security Status', status: 'Protected', level: 'critical' } ]")
        // Heading announced for the panel title
        verify(screen.titleLabel.Accessible.role === Accessible.Heading)
        verify(screen.titleLabel.Accessible.name.length > 0)
        // Rows announced as buttons with label + status + level in the
        // name (color is never the only indicator)
        var row0 = screen.trayRows.itemAt(0)
        verify(row0.Accessible.role === Accessible.Button)
        compare(row0.Accessible.name, "Network, Connected, OK")
        var row1 = screen.trayRows.itemAt(1)
        compare(row1.Accessible.name, "Security Status, Protected, Critical")
        screen.destroy()
    }

    // ── Keyboard focus reaches the rows ────────────────────────────
    function test_keyboardFocus() {
        var screen = createScreen("trayItems: [ { id: 'network', label: 'Network' }, " +
                                  "{ id: 'audio', label: 'Audio' } ]")
        wait(100) // let the hosted window activate so Tab reaches the rows
        var hostWindow = _hostWindows[_hostWindows.length - 1]
        var found = { "trayItem0": false, "trayItem1": false }

        for (var tab = 0; tab < 40; ++tab) {
            keyClick(Qt.Key_Tab)
            var focusItem = hostWindow.activeFocusItem
            if (focusItem && focusItem.objectName)
                found[focusItem.objectName] = true
        }

        verify(found["trayItem0"], "focus must reach the tray rows")
        verify(found["trayItem1"], "focus must reach the tray rows")

        screen.destroy()
    }

    // ── Escape is deliberately unmapped (no signal fires) ──────────
    function test_noEscapeMapping() {
        var screen = createScreen("trayItems: [ { id: 'network', label: 'Network' } ]")
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'trayItemActivated' }",
            screen, "escSpy")
        spy.target = screen

        // Escape with a row focused must not activate it and must not
        // dismiss anything (the host owns overlay dismissal)
        screen.trayRows.itemAt(0).forceActiveFocus()
        keyClick(Qt.Key_Escape)
        compare(spy.count, 0)

        screen.destroy()
    }

    // ── MissionPage / MissionWindow integration ────────────────────
    function test_missionPageIntegration() {
        var page = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionPage { pageTitle: 'System Tray'; SystemTray { objectName: 'trayInPage' } }",
            root, "trayInPage")
        verify(page !== null)
        verify(page.data.length > 0)
        page.destroy()
    }

    function test_missionWindowIntegration() {
        var screen = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionWindow { width: 1280; height: 720; SystemTray { objectName: 'trayInWindow' } }",
            root, "trayInWindow")
        verify(screen !== null)
        verify(screen.width > 0)
        screen.destroy()
    }

    // ── Reduced motion does not break rendering ────────────────────
    function test_reducedMotion() {
        var screen = createScreen("trayItems: [ { id: 'network', label: 'Network', status: 'Connected' }, " +
                                  "{ id: 'battery', label: 'Battery', status: '80%' } ]")
        screen.reducedMotion = true
        verify(screen.trayRows.count === 2)
        verify(screen.trayPanel.visible)
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
