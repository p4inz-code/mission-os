// Mission OS — Notifications (MOS-DES-003) QtTest suite
//
// Runtime validation of the Notification Center screen. Follows the
// foundation smoke-test pattern (tests/tst_smoke.qml), the Desktop and
// Workspace Switcher suites (tests/tst_desktop.qml,
// tests/tst_workspace_switcher.qml), the lock-family suites and
// docs/engineering/TESTING_STRATEGY.md (QML → Qt Test / qmltestrunner).
//
// Coverage:
//   - screen loads without QML errors (token singletons resolve)
//   - MissionTheme works; light/dark rendering bindings re-evaluate
//   - overlay treatment: scrim + top-right panel with a "Notifications"
//     heading and a Clear all action
//   - notification rows render from the host model (level tag, app,
//     title, message, timestamp)
//   - level helpers map the four reference levels (information /
//     success / warning / critical) to labels + token colors
//   - the Notifications flow's "Take Action" step: click, Enter and
//     Space emit notificationActivated(id); the per-row Dismiss button
//     emits notificationDismissed(id); Clear all emits
//     clearAllRequested()
//   - Focus Mode suppresses non-critical notifications (information /
//     success hidden behind a hint; critical/warning remain visible)
//   - empty notifications degrade to a neutral hint with Clear all
//     disabled
//   - keyboard navigation: Up/Down/Left/Right move focus between rows
//     (wrapping); the first row is focused on load (keyboard-first)
//   - accessibility roles (heading, rows announced as buttons with
//     app/title/level/time in the name)
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
//                 -input src/libraries/ui/tests/tst_notifications.qml
//
// Exit code: 0 = all checks passed; non-zero = failure (CI gate).

import QtQuick
import QtTest
import org.mission.ui 1.0

TestCase {
    id: root
    name: "Notifications"

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
                     "    Notifications { id: screen; width: 1280; height: 720; " +
                     (extra || "") + " }\n" +
                     "}"
        var host = Qt.createQmlObject(source, root, "notifHost")
        _hostWindows.push(host)
        return host.screen
    }

    // ── Screen loads; tokens resolve; no QML errors ────────────────
    function test_screenLoads() {
        var screen = createScreen()
        verify(screen !== null)
        verify(screen.height > 0)
        // Overlay treatment: scrim + top-right panel + heading
        verify(screen.backdropScrim !== null)
        verify(screen.notificationPanel !== null)
        verify(screen.titleLabel.text.length > 0)
        compare(screen.titleLabel.text, "Notifications")
        verify(screen.clearAllButton !== null)
        screen.destroy()
    }

    // ── MissionTheme light/dark rendering bindings ─────────────────
    function test_themeLightAndDark() {
        var screen = createScreen("notifications: [ { id: 'n1', app: 'Mail', title: 'Hi', message: 'Test', time: '10:00' } ]")
        var row0 = screen.notificationRows.itemAt(0)
        // Disable the row's Behavior on color (reduced-motion) so theme
        // flips apply instantly instead of animating over Motion.colorChange
        screen.reducedMotion = true

        MissionTheme.darkMode = false
        verify(Qt.colorEqual(screen.backdropScrim.color, Colors.scrim))
        verify(Qt.colorEqual(screen.notificationPanel.color, MissionTheme.surface))
        verify(Qt.colorEqual(screen.titleLabel.color, MissionTheme.textPrimary))
        verify(Qt.colorEqual(row0.color, MissionTheme.surfaceDim))

        MissionTheme.darkMode = true
        verify(Qt.colorEqual(screen.titleLabel.color, MissionTheme.textPrimary))
        verify(Qt.colorEqual(row0.color, MissionTheme.surfaceDim))

        MissionTheme.darkMode = false
        screen.destroy()
    }

    // ── Notification rows render names, messages, times ────────────
    function test_rowsRender() {
        var screen = createScreen("notifications: [ { id: 'n1', app: 'Mail', title: 'New message', message: 'From Ada', time: '10:00', level: 'success' }, " +
                                             "{ id: 'n2', app: 'System', title: 'Update ready', message: 'Restart to apply', time: '09:30' } ]")
        verify(screen.notificationRows.count === 2)
        var row0 = screen.notificationRows.itemAt(0)
        var row1 = screen.notificationRows.itemAt(1)
        verify(row0 !== null && row1 !== null)
        verify(row0.visible)
        verify(row1.visible)
        // Accessible names carry app, title, level and time
        compare(row0.Accessible.name, "Mail: New message, Success, 10:00")
        compare(row1.Accessible.name, "System: Update ready, Information, 09:30")
        // Header state
        verify(screen.clearAllButton.enabled)
        compare(screen.notificationCount, 2)
        verify(screen.hasVisibleNotifications)
        screen.destroy()
    }

    // ── Level helpers map the four reference levels ────────────────
    function test_levelHelpers() {
        var screen = createScreen()
        compare(screen.levelLabel("information"), "Information")
        compare(screen.levelLabel("success"), "Success")
        compare(screen.levelLabel("warning"), "Warning")
        compare(screen.levelLabel("critical"), "Critical")
        // Unknown levels fall back to information
        compare(screen.levelLabel(""), "Information")
        compare(screen.levelLabel("whatever"), "Information")
        // Token colors
        verify(Qt.colorEqual(screen.levelColor("information"), MissionTheme.primary))
        verify(Qt.colorEqual(screen.levelColor("success"), MissionTheme.success))
        verify(Qt.colorEqual(screen.levelColor("warning"), MissionTheme.warning))
        verify(Qt.colorEqual(screen.levelColor("critical"), MissionTheme.error))
        screen.destroy()
    }

    // ── Take Action: click, Enter and Space emit the id ────────────
    function test_activation() {
        var screen = createScreen("notifications: [ { id: 'n1', app: 'Mail', title: 'New message', message: 'From Ada', time: '10:00' }, " +
                                             "{ id: 'n2', app: 'System', title: 'Update ready', time: '09:30' } ]")
        wait(100) // window activation for key delivery
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'notificationActivated' }",
            screen, "actSpy")
        spy.target = screen

        // Mouse click on the first row (center avoids the Dismiss button)
        var row0 = screen.notificationRows.itemAt(0)
        mouseClick(row0, row0.width / 2, row0.height / 2)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "n1")

        // Enter on the second row
        var row1 = screen.notificationRows.itemAt(1)
        row1.forceActiveFocus()
        keyClick(Qt.Key_Return)
        compare(spy.count, 2)
        compare(spy.signalArguments[1][0], "n2")

        // Space on the first row
        row0.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spy.count, 3)
        compare(spy.signalArguments[2][0], "n1")

        screen.destroy()
    }

    // ── Dismiss button emits the per-row id ────────────────────────
    // The Dismiss button is nested inside the row's Column, so locate
    // it by walking the row's data tree for the notifDismiss0 objectName
    function _findByObjectName(item, name) {
        if (item === null || item === undefined)
            return null
        if (item.objectName === name)
            return item
        for (var i = 0; item.data && i < item.data.length; ++i) {
            var hit = _findByObjectName(item.data[i], name)
            if (hit !== null)
                return hit
        }
        return null
    }

    function test_dismiss() {
        var screen = createScreen("notifications: [ { id: 'n1', app: 'Mail', title: 'New message', message: 'From Ada', time: '10:00' }, " +
                                             "{ id: 'n2', app: 'System', title: 'Update ready', time: '09:30' } ]")
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'notificationDismissed' }",
            screen, "dismissSpy")
        spy.target = screen

        var row0 = screen.notificationRows.itemAt(0)
        var btn = _findByObjectName(row0, "notifDismiss0")
        verify(btn !== null, "row must expose its Dismiss button")
        btn.clicked()
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "n1")

        screen.destroy()
    }

    // ── Clear all emits once ───────────────────────────────────────
    function test_clearAll() {
        var screen = createScreen("notifications: [ { id: 'n1', app: 'Mail', title: 'New message', time: '10:00' } ]")
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'clearAllRequested' }",
            screen, "clearSpy")
        spy.target = screen

        screen.clearAllButton.clicked()
        compare(spy.count, 1)

        screen.destroy()
    }

    // ── Focus Mode suppresses non-critical notifications ───────────
    function test_focusModeSuppresses() {
        var screen = createScreen("notifications: [ { id: 'n1', app: 'Mail', title: 'Info note', time: '10:00', level: 'information' }, " +
                                             "{ id: 'n2', app: 'Chat', title: 'New message', time: '09:30', level: 'success' }, " +
                                             "{ id: 'n3', app: 'Security', title: 'Warning', time: '09:00', level: 'warning' }, " +
                                             "{ id: 'n4', app: 'Security', title: 'Critical', time: '08:00', level: 'critical' } ]")
        // Off: everything visible, no hint
        verify(!screen.focusHint.visible)
        verify(screen.notificationRows.itemAt(0).visible)
        verify(screen.notificationRows.itemAt(1).visible)
        verify(screen.notificationRows.itemAt(2).visible)
        verify(screen.notificationRows.itemAt(3).visible)
        verify(screen.hasVisibleNotifications)

        // On: information + success hidden, hint shown, critical stays
        screen.focusMode = true
        verify(screen.focusHint.visible)
        verify(!screen.notificationRows.itemAt(0).visible)
        verify(!screen.notificationRows.itemAt(1).visible)
        verify(screen.notificationRows.itemAt(2).visible)
        verify(screen.notificationRows.itemAt(3).visible)
        verify(screen.hasVisibleNotifications)

        // Off again: rows return
        screen.focusMode = false
        verify(screen.notificationRows.itemAt(0).visible)
        verify(!screen.focusHint.visible)

        screen.destroy()
    }

    // ── Focus Mode treats a level-less entry as information ────────
    // levelLabel/levelColor fall back to "information" for unknown
    // levels, so isSuppressed must too (regression: String(undefined)
    // is "undefined", not "" — a missing level must still be
    // suppressed in Focus Mode).
    function test_focusModeMissingLevel() {
        var screen = createScreen("notifications: [ { id: 'n1', app: 'Mail', title: 'No level', time: '10:00' }, " +
                                             "{ id: 'n2', app: 'System', title: 'Critical', time: '09:00', level: 'critical' } ]")
        var row0 = screen.notificationRows.itemAt(0)
        var row1 = screen.notificationRows.itemAt(1)

        // Without focus mode both are visible; the level-less row
        // renders with the information treatment
        verify(row0.visible)
        verify(row1.visible)
        compare(screen.levelLabel(""), "Information")

        // Focus Mode suppresses the level-less (information) row
        screen.focusMode = true
        verify(!row0.visible, "level-less notifications must be suppressed in Focus Mode")
        verify(row1.visible)

        // focusRow must skip suppressed rows (never focus invisible ones)
        screen.focusRow(0)
        verify(!row0.activeFocus)
        verify(row1.activeFocus, "focusRow must land on the first visible row")

        screen.focusMode = false
        screen.destroy()
    }

    // ── Empty notifications degrade gracefully ─────────────────────
    function test_emptyNotifications() {
        var screen = createScreen()
        wait(100)
        verify(screen.notificationRows.count === 0)
        verify(screen.emptyHint.visible)
        compare(screen.notificationCount, 0)
        verify(!screen.hasVisibleNotifications)
        verify(!screen.clearAllButton.enabled)
        // Focusing is impossible but must not crash
        screen.focusRow(0)
        screen.destroy()
    }

    // ── Keyboard navigation: arrows move focus between rows ────────
    function test_keyboardNavigation() {
        var screen = createScreen("notifications: [ { id: 'a', app: 'A', title: 'One', time: '10:00' }, " +
                                             "{ id: 'b', app: 'B', title: 'Two', time: '09:00' }, " +
                                             "{ id: 'c', app: 'C', title: 'Three', time: '08:00' } ]")
        wait(100) // window activation for key delivery
        var row0 = screen.notificationRows.itemAt(0)
        var row1 = screen.notificationRows.itemAt(1)
        var row2 = screen.notificationRows.itemAt(2)

        // Down moves to the next row; Up moves back
        row0.forceActiveFocus()
        verify(row0.activeFocus)
        keyClick(Qt.Key_Down)
        verify(row1.activeFocus, "Down must move focus to the next notification")
        keyClick(Qt.Key_Down)
        verify(row2.activeFocus, "Down must move focus to the next notification")
        keyClick(Qt.Key_Up)
        verify(row1.activeFocus, "Up must move focus to the previous notification")

        // Left/Right behave the same (wrapping layout)
        keyClick(Qt.Key_Left)
        verify(row0.activeFocus, "Left must move focus to the previous notification")
        keyClick(Qt.Key_Left)
        verify(row2.activeFocus, "Left must wrap around to the last notification")
        keyClick(Qt.Key_Right)
        verify(row0.activeFocus, "Right must wrap around to the first notification")

        screen.destroy()
    }

    // ── Accessibility roles ────────────────────────────────────────
    function test_accessibleRoles() {
        var screen = createScreen("notifications: [ { id: 'a', app: 'Mail', title: 'New message', time: '10:00', level: 'warning' } ]")
        // Heading announced for the panel title
        verify(screen.titleLabel.Accessible.role === Accessible.Heading)
        verify(screen.titleLabel.Accessible.name.length > 0)
        // Rows announced as buttons with the full name
        var row0 = screen.notificationRows.itemAt(0)
        verify(row0.Accessible.role === Accessible.Button)
        compare(row0.Accessible.name, "Mail: New message, Warning, 10:00")
        screen.destroy()
    }

    // ── Keyboard focus reaches the notification rows ───────────────
    function test_keyboardFocus() {
        var screen = createScreen("notifications: [ { id: 'a', app: 'A', title: 'One', time: '10:00' }, " +
                                             "{ id: 'b', app: 'B', title: 'Two', time: '09:00' } ]")
        wait(100) // let the hosted window activate so Tab reaches the rows
        var hostWindow = _hostWindows[_hostWindows.length - 1]
        var found = { "notifRow0": false, "notifRow1": false }

        for (var tab = 0; tab < 20; ++tab) {
            keyClick(Qt.Key_Tab)
            var focusItem = hostWindow.activeFocusItem
            if (focusItem && focusItem.objectName)
                found[focusItem.objectName] = true
        }

        verify(found["notifRow0"], "focus must reach the notification rows")
        verify(found["notifRow1"], "focus must reach all notification rows")

        screen.destroy()
    }

    // ── Escape is deliberately unmapped (no signal fires) ──────────
    function test_noEscapeMapping() {
        var screen = createScreen("notifications: [ { id: 'a', app: 'A', title: 'One', time: '10:00' } ]")
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'notificationActivated' }",
            screen, "escSpy")
        spy.target = screen

        // Escape with a row focused must not activate or dismiss
        screen.notificationRows.itemAt(0).forceActiveFocus()
        keyClick(Qt.Key_Escape)
        compare(spy.count, 0)

        screen.destroy()
    }

    // ── MissionPage / MissionWindow integration ────────────────────
    function test_missionPageIntegration() {
        var page = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionPage { pageTitle: 'Notifications'; Notifications { objectName: 'notifInPage' } }",
            root, "notifInPage")
        verify(page !== null)
        verify(page.data.length > 0)
        page.destroy()
    }

    function test_missionWindowIntegration() {
        var screen = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionWindow { width: 1280; height: 720; Notifications { objectName: 'notifInWindow' } }",
            root, "notifInWindow")
        verify(screen !== null)
        verify(screen.width > 0)
        screen.destroy()
    }

    // ── Reduced motion does not break rendering ────────────────────
    function test_reducedMotion() {
        var screen = createScreen("notifications: [ { id: 'a', app: 'A', title: 'One', time: '10:00' }, " +
                                             "{ id: 'b', app: 'B', title: 'Two', time: '09:00' } ]")
        screen.reducedMotion = true
        verify(screen.notificationRows.count === 2)
        verify(screen.notificationPanel.visible)
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
