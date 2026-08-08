// Mission OS — Desktop (MOS-DES-001) QtTest suite
//
// Runtime validation of the Desktop screen. Follows the foundation
// smoke-test pattern (tests/tst_smoke.qml), the lock-family suites
// (tests/tst_lock_screen.qml / tst_login.qml / tst_pin_entry.qml /
// tst_recovery_login.qml) and docs/engineering/TESTING_STRATEGY.md
// (QML → Qt Test / qmltestrunner).
//
// Coverage:
//   - screen loads without QML errors (token singletons resolve)
//   - MissionTheme works; light/dark rendering bindings re-evaluate
//   - top panel controls exist (Mission Menu, Search, Workspace
//     Indicator, Running Apps, Clock, System Status, User Menu) per
//     docs/design/07_DESKTOP_LAYOUT.md §3
//   - dock exists with pinned-application tiles (per §4)
//   - running apps render as taskbar buttons and emit
//     runningAppActivated(appId)
//   - pinned dock tiles render, show the app initial, show a running
//     indicator when the id is in runningApps, and emit
//     pinnedAppActivated(appId)
//   - wireframe states: idle · notifications · workspace switching ·
//     search active — the matching panel control highlights (dot +
//     "(active)" Accessible name) and the workspace scrim dims
//   - overlay routing: menu/user-menu/notifications/quick-settings/
//     search/workspace-switch signals fire from their panel controls
//   - dock visibility is host-driven (dockVisible)
//   - workspace indicator text follows currentWorkspace/workspaceCount
//   - network/battery status indicators react to host properties
//   - clock text is host-pinnable and seeded at load
//   - user menu button reflects the signed-in user name
//   - keyboard focus reaches the panel controls and dock tiles; Escape
//     is deliberately unmapped (no signal fires)
//   - MissionPage / MissionWindow integration introduces no runtime errors
//   - accessibility roles (clock, status chips, dock tiles with
//     running state in the name)
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
//                 -input src/libraries/ui/tests/tst_desktop.qml
//
// Exit code: 0 = all checks passed; non-zero = failure (CI gate).

import QtQuick
import QtTest
import org.mission.ui 1.0

TestCase {
    id: root
    name: "Desktop"

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
                     "    Desktop { id: screen; width: 1280; height: 720; " +
                     (extra || "") + " }\n" +
                     "}"
        var host = Qt.createQmlObject(source, root, "desktopHost")
        _hostWindows.push(host)
        return host.screen
    }

    // ── Screen loads; tokens resolve; no QML errors ────────────────
    function test_screenLoads() {
        var screen = createScreen()
        verify(screen !== null)
        verify(screen.height > 0)
        // Token singletons must resolve through the screen's bindings
        verify(Qt.colorEqual(screen.backdropColor, Colors.background))
        // Clock is seeded at load (Component.onCompleted)
        verify(screen.clockLabel.text.length > 0)
        // Core regions exist (wireframe: Top Panel · Dock · Workspace)
        verify(screen.topPanel !== null)
        verify(screen.dock !== null)
        verify(screen.workspaceScrim !== null)
        screen.destroy()
    }

    // ── MissionTheme light/dark rendering bindings ─────────────────
    function test_themeLightAndDark() {
        var screen = createScreen()
        MissionTheme.darkMode = false
        verify(Qt.colorEqual(screen.backdropColor, Colors.background))
        verify(Qt.colorEqual(screen.backdropColor, MissionTheme.background))
        verify(Qt.colorEqual(screen.clockLabel.color, MissionTheme.textPrimary))

        MissionTheme.darkMode = true
        verify(Qt.colorEqual(screen.backdropColor, Colors.darkBackground))
        verify(Qt.colorEqual(screen.backdropColor, MissionTheme.background))
        verify(Qt.colorEqual(screen.clockLabel.color, MissionTheme.textPrimary))

        MissionTheme.darkMode = false
        verify(Qt.colorEqual(screen.backdropColor, Colors.background))
        screen.destroy()
    }

    // ── Top panel controls exist (07_DESKTOP_LAYOUT.md §3) ─────────
    function test_panelControlsExist() {
        var screen = createScreen("userName: 'Alex'")
        // Mission Menu · Workspace Indicator · Running Apps · Clock ·
        // System Status · User Menu
        verify(screen.missionMenuButton !== null)
        verify(screen.searchButton !== null)
        verify(screen.workspaceIndicator !== null)
        verify(screen.clockLabel !== null)
        verify(screen.networkChip !== null)
        verify(screen.batteryChip !== null)
        verify(screen.userMenuButton !== null)
        // Overlay routing entries (separate registry screens 003/004/005)
        verify(screen.notificationsButton !== null)
        verify(screen.quickSettingsButton !== null)
        verify(screen.missionMenuButton.visible)
        verify(screen.dock.visible)
        compare(screen.userMenuButton.text, "Alex")
        screen.destroy()
    }

    // ── Workspace indicator follows the host properties ────────────
    function test_workspaceIndicator() {
        var screen = createScreen("currentWorkspace: 2; workspaceCount: 4")
        compare(screen.workspaceIndicator.text, "2 / 4")
        compare(screen.workspaceIndicator.Accessible.name, "Workspace 2 of 4")
        screen.currentWorkspace = 3
        compare(screen.workspaceIndicator.text, "3 / 4")
        screen.destroy()
    }

    // ── Running apps render as taskbar buttons and activate ────────
    function test_runningApps() {
        var screen = createScreen("runningApps: [ { id: 'files', name: 'Files' }, " +
                                            "{ id: 'terminal', name: 'Terminal' } ]")
        verify(screen.runningAppsRepeater.count === 2)
        var button0 = screen.runningAppsRepeater.itemAt(0)
        var button1 = screen.runningAppsRepeater.itemAt(1)
        verify(button0 !== null && button1 !== null)
        compare(button0.text, "Files")
        compare(button1.text, "Terminal")

        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'runningAppActivated' }",
            screen, "runningSpy")
        spy.target = screen
        button0.clicked()
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "files")
        button1.clicked()
        compare(spy.count, 2)
        compare(spy.signalArguments[1][0], "terminal")

        screen.destroy()
    }

    // ── Pinned dock tiles render, show initials + indicators ───────
    function test_pinnedApps() {
        var screen = createScreen("pinnedApps: [ { id: 'files', name: 'Files' }, " +
                                           "{ id: 'browser', name: 'Browser' } ]; " +
                                           "runningApps: [ { id: 'files', name: 'Files' } ]")
        verify(screen.dockRepeater.count === 2)
        var tile0 = screen.dockRepeater.itemAt(0)
        var tile1 = screen.dockRepeater.itemAt(1)
        verify(tile0 !== null && tile1 !== null)
        // App initial rendered on each tile
        verify(tile0.childrenRect.width > 0)
        compare(tile0.Accessible.name, "Files (running)") // files is running
        compare(tile1.Accessible.name, "Browser")         // browser is not

        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'pinnedAppActivated' }",
            screen, "pinnedSpy")
        spy.target = screen
        mouseClick(tile0, tile0.width / 2, tile0.height / 2)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "files")

        screen.destroy()
    }

    // ── Dock running indicator follows isRunning() ─────────────────
    function test_runningIndicatorToggles() {
        var screen = createScreen("pinnedApps: [ { id: 'a', name: 'Alpha' } ]; " +
                                           "runningApps: [ { id: 'b', name: 'Beta' } ]")
        var tile0 = screen.dockRepeater.itemAt(0)
        verify(tile0 !== null)
        compare(tile0.Accessible.name, "Alpha") // 'a' not running yet

        screen.runningApps = [ { id: "a", name: "Alpha" } ]
        compare(tile0.Accessible.name, "Alpha (running)")
        screen.destroy()
    }

    // ── Wireframe states: idle · notifications · workspace switching
    //    · search active ────────────────────────────────────────────
    function test_overlayStates() {
        var screen = createScreen()
        // Disable the scrim's opacity Behavior so the scrim checks are
        // synchronous (the animation would otherwise still be running
        // when the assertions execute).
        screen.reducedMotion = true
        // idle: no active dots, no scrim
        verify(!screen.searchActiveDot.visible)
        verify(!screen.workspaceActiveDot.visible)
        verify(!screen.notificationsActiveDot.visible)
        compare(screen.workspaceScrim.opacity, 0.0)
        compare(screen.searchButton.Accessible.name, "Search")

        // search active
        screen.overlayState = "search"
        verify(screen.searchActiveDot.visible)
        verify(!screen.workspaceActiveDot.visible)
        verify(!screen.notificationsActiveDot.visible)
        verify(screen.workspaceScrim.opacity > 0.0)
        compare(screen.searchButton.Accessible.name, "Search (active)")

        // workspace switching
        screen.overlayState = "workspaceSwitching"
        verify(!screen.searchActiveDot.visible)
        verify(screen.workspaceActiveDot.visible)
        verify(!screen.notificationsActiveDot.visible)
        compare(screen.workspaceIndicator.Accessible.name, "Workspace 1 of 1 (active)")

        // notifications
        screen.overlayState = "notifications"
        verify(!screen.searchActiveDot.visible)
        verify(!screen.workspaceActiveDot.visible)
        verify(screen.notificationsActiveDot.visible)
        compare(screen.notificationsButton.Accessible.name, "Notifications (active)")

        // back to idle clears everything
        screen.overlayState = "idle"
        verify(!screen.searchActiveDot.visible)
        verify(!screen.workspaceActiveDot.visible)
        verify(!screen.notificationsActiveDot.visible)
        compare(screen.workspaceScrim.opacity, 0.0)

        screen.destroy()
    }

    // ── Overlay routing signals fire from their panel controls ─────
    function test_overlayRoutingSignals() {
        var screen = createScreen()
        // Each control must fire its own dedicated signal
        var names = ["missionMenuRequested", "userMenuRequested", "notificationsRequested",
                     "quickSettingsRequested", "searchRequested", "workspaceSwitchRequested"]
        var counts = []
        for (var i = 0; i < names.length; ++i) {
            var s = Qt.createQmlObject(
                "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: '" +
                names[i] + "' }", screen, "routeSpy" + i)
            s.target = screen
            counts.push(s)
        }

        screen.missionMenuButton.clicked()
        compare(counts[0].count, 1)
        screen.userMenuButton.clicked()
        compare(counts[1].count, 1)
        screen.notificationsButton.clicked()
        compare(counts[2].count, 1)
        screen.quickSettingsButton.clicked()
        compare(counts[3].count, 1)
        screen.searchButton.clicked()
        compare(counts[4].count, 1)
        screen.workspaceIndicator.clicked()
        compare(counts[5].count, 1)

        screen.destroy()
    }

    // ── Dock visibility is host-driven ─────────────────────────────
    function test_dockVisibleToggle() {
        var screen = createScreen()
        verify(screen.dock.visible)
        screen.dockVisible = false
        verify(!screen.dock.visible)
        screen.dockVisible = true
        verify(screen.dock.visible)
        screen.destroy()
    }

    // ── Status indicators react to host properties ─────────────────
    function test_statusIndicators() {
        var screen = createScreen()
        screen.networkStatusText = "Offline"
        screen.networkConnected = false
        compare(screen.networkStatusLabel.text, "Offline")
        verify(Qt.colorEqual(screen.networkDot.color, MissionTheme.textTertiary))

        screen.networkConnected = true
        verify(Qt.colorEqual(screen.networkDot.color, MissionTheme.success))

        screen.batteryStatusText = "10%"
        screen.batteryLevel = 10
        compare(screen.batteryStatusLabel.text, "10%")
        verify(Qt.colorEqual(screen.batteryFill.color, MissionTheme.warning))

        screen.batteryLevel = 80
        verify(Qt.colorEqual(screen.batteryFill.color, MissionTheme.success))

        screen.destroy()
    }

    // ── Host-absent defaults are neutral (FABRICATION-9 regression) ─
    // The battery/network indicators must never fabricate "100%" or
    // "Connected" before the host supplies real state.
    function test_hostAbsentDefaultsNeutral() {
        var screen = createScreen()
        compare(screen.batteryStatusText, "")
        compare(screen.networkStatusText, "")
        verify(!screen.networkConnected)
        verify(screen.batteryLevel < 0)
        verify(!screen.batteryFill.visible, "battery fill must be hidden when the level is unknown")
        compare(screen.batteryStatusLabel.text, "")
        compare(screen.networkStatusLabel.text, "")
        screen.destroy()
    }

    // ── Clock: seeded at load, host-pinnable ───────────────────────
    function test_clockHostPin() {
        var screen = createScreen()
        // Host pins the displayed text and stops the live timer
        screen.clockTimeText = "06:15"
        screen.clockRunning = false
        compare(screen.clockLabel.text, "06:15")

        // updateClock() refreshes from the system clock on demand
        screen.updateClock()
        verify(screen.clockLabel.text.length > 0)

        screen.destroy()
    }

    // ── User menu button reflects the signed-in user ───────────────
    function test_userNameLabel() {
        var screen = createScreen()
        compare(screen.userMenuButton.text, "User") // neutral while no user
        screen.userName = "Alex"
        compare(screen.userMenuButton.text, "Alex")
        screen.userName = ""
        compare(screen.userMenuButton.text, "User")
        screen.destroy()
    }

    // ── Keyboard focus reaches panel controls + dock tiles ─────────
    function test_keyboardFocus() {
        var screen = createScreen("runningApps: [ { id: 'files', name: 'Files' } ]; " +
                                           "pinnedApps: [ { id: 'files', name: 'Files' }, " +
                                                        "{ id: 'browser', name: 'Browser' } ]")
        wait(100) // let the hosted window activate so Tab reaches the controls
        var hostWindow = _hostWindows[_hostWindows.length - 1]
        var controls = ["desktopMenu", "desktopSearch", "desktopWorkspace",
                        "desktopNotifications", "desktopQuickSettings", "desktopUserMenu",
                        "desktopRunning0", "desktopPinned0", "desktopPinned1"]
        var found = {}
        for (var i = 0; i < controls.length; ++i)
            found[controls[i]] = false

        for (var tab = 0; tab < 40; ++tab) {
            keyClick(Qt.Key_Tab)
            var focusItem = hostWindow.activeFocusItem
            if (focusItem && focusItem.objectName)
                found[focusItem.objectName] = true
        }

        for (var c = 0; c < controls.length; ++c)
            verify(found[controls[c]], "focus must reach " + controls[c])

        screen.destroy()
    }

    // ── Escape is deliberately unmapped (no signal fires) ──────────
    function test_noEscapeMapping() {
        var screen = createScreen()
        wait(100)
        var spies = []
        var names = ["missionMenuRequested", "userMenuRequested", "notificationsRequested",
                     "quickSettingsRequested", "searchRequested", "workspaceSwitchRequested",
                     "runningAppActivated", "pinnedAppActivated"]
        for (var i = 0; i < names.length; ++i) {
            var spy = Qt.createQmlObject(
                "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: '" +
                names[i] + "' }", screen, "escSpy" + i)
            spy.target = screen
            spies.push(spy)
        }

        // Escape with the desktop focused must not dismiss it (host
        // owns any overlay dismissal)
        screen.forceActiveFocus()
        keyClick(Qt.Key_Escape)
        for (var s = 0; s < spies.length; ++s)
            compare(spies[s].count, 0, names[s] + " must not fire on Escape")

        screen.destroy()
    }

    // ── MissionPage / MissionWindow integration ────────────────────
    function test_missionPageIntegration() {
        var page = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionPage { pageTitle: 'Desktop'; Desktop { objectName: 'desktopInPage' } }",
            root, "desktopInPage")
        verify(page !== null)
        verify(page.data.length > 0)
        page.destroy()
    }

    function test_missionWindowIntegration() {
        var screen = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionWindow { width: 1280; height: 720; Desktop { objectName: 'desktopInWindow' } }",
            root, "desktopInWindow")
        verify(screen !== null)
        verify(screen.width > 0)
        screen.destroy()
    }

    // ── Accessibility roles ────────────────────────────────────────
    function test_accessibleRoles() {
        var screen = createScreen("runningApps: [ { id: 'files', name: 'Files' } ]; " +
                                           "pinnedApps: [ { id: 'files', name: 'Files' } ]")
        // Clock announced as static text
        verify(screen.clockLabel.Accessible.role === Accessible.StaticText)
        verify(screen.clockLabel.Accessible.name.length > 0)
        // Status indicators announced as named groups
        verify(screen.networkChip.Accessible.role === Accessible.Grouping)
        verify(screen.networkChip.Accessible.name.length > 0)
        verify(screen.batteryChip.Accessible.role === Accessible.Grouping)
        verify(screen.batteryChip.Accessible.name.length > 0)
        // Panel controls announced as buttons with descriptions
        verify(screen.searchButton.Accessible.role === Accessible.Button)
        verify(screen.searchButton.Accessible.description.length > 0)
        // Dock tiles announced as buttons with the running state in
        // the name (color is never the only indicator)
        var tile0 = screen.dockRepeater.itemAt(0)
        verify(tile0.Accessible.role === Accessible.Button)
        compare(tile0.Accessible.name, "Files (running)")
        screen.destroy()
    }

    // ── Reduced motion does not break rendering ────────────────────
    function test_reducedMotion() {
        var screen = createScreen()
        screen.reducedMotion = true
        screen.overlayState = "search"
        verify(screen.searchActiveDot.visible)
        verify(screen.workspaceScrim.opacity > 0.0)
        screen.overlayState = "idle"
        verify(!screen.searchActiveDot.visible)
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
