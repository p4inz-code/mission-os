// Mission OS — Mission Hub Updates (MOS-HUB-004) QtTest suite
//
// Runtime validation of the Mission Hub Updates screen. Follows
// the established Mission Hub test pattern.

import QtQuick
import QtTest
import org.mission.ui 1.0

TestCase {
    id: root
    name: "MissionHubUpdates"

    property var _hostWindows: []

    function createScreen(extra) {
        var source = "import QtQuick\n" +
                     "import org.mission.ui 1.0\n" +
                     "Window {\n" +
                     "    width: 1280; height: 720; visible: true\n" +
                     "    property alias screen: screen\n" +
                     "    MissionHubUpdates { id: screen; width: 1280; height: 720; " +
                     (extra || "") + " }\n" +
                     "}"
        var host = Qt.createQmlObject(source, root, "hubUpdatesHost")
        _hostWindows.push(host)
        return host.screen
    }

    // ── Screen loads; tokens resolve; no QML errors ────────────────
    function test_screenLoads() {
        var screen = createScreen("")
        verify(screen !== null)
        verify(screen.height > 0)
        verify(screen.headerBar !== null)
        verify(screen.sidebar !== null)
        verify(screen.mainContent !== null)
        compare(screen.titleLabel.text, "Mission Hub")
        verify(screen.navRepeater.count > 0)
        screen.destroy()
    }

    // ── MissionTheme light/dark rendering bindings ─────────────────
    function test_themeLightAndDark() {
        var screen = createScreen("screenState: 'normal'")
        screen.reducedMotion = true

        MissionTheme.darkMode = false
        verify(Qt.colorEqual(screen.headerBar.color, MissionTheme.surface))

        MissionTheme.darkMode = true
        verify(Qt.colorEqual(screen.headerBar.color, MissionTheme.surface))

        MissionTheme.darkMode = false
        screen.destroy()
    }

    // ── Header renders correctly ───────────────────────────────────
    function test_headerRenders() {
        var screen = createScreen("version: '2.0.0'; buildType: 'Stable'")
        compare(screen.titleLabel.text, "Mission Hub")
        verify(screen.headerBar.visible)
        verify(screen.headerBar.height > 0)
        screen.destroy()
    }

    // ── Sidebar navigation renders all items ───────────────────────
    function test_sidebarNavigation() {
        var screen = createScreen("")
        verify(screen.navRepeater.count === 11)
        // Updates is selected by default
        var updItem = screen.navRepeater.itemAt(3)
        verify(updItem !== null)
        verify(updItem.Accessible.selected)
        verify(screen.sidebarExpanded)
        screen.destroy()
    }

    // ── Pending updates render from host model ─────────────────────
    function test_pendingUpdatesRender() {
        var screen = createScreen(
            "screenState: 'normal'; pendingUpdates: [" +
            "{ id: 'u1', name: 'Kernel', version: '6.1.0', type: 'system', size: '45 MB' }," +
            "{ id: 'u2', name: 'Firefox', version: '120.0', type: 'application', security: true }" +
            "]")
        verify(screen.pendingCount === 2)
        verify(screen.hasPendingUpdates)
        verify(screen.pendingRepeater.count === 2)
        var u0 = screen.pendingRepeater.itemAt(0)
        verify(u0 !== null)
        verify(u0.visible)
        verify(u0.Accessible.name.length > 0)
        compare(u0.Accessible.role, Accessible.Button)
        screen.destroy()
    }

    // ── Update history renders ─────────────────────────────────────
    function test_updateHistoryRender() {
        var screen = createScreen(
            "screenState: 'normal'; updateHistory: [" +
            "{ id: 'h1', name: 'Kernel', version: '6.0.0', installedDate: '2024-01-15', type: 'system' }" +
            "]")
        verify(screen.historyCount === 1)
        verify(screen.historyRepeater.count === 1)
        screen.destroy()
    }

    // ── Version info displays ──────────────────────────────────────
    function test_versionInfo() {
        var screen = createScreen(
            "screenState: 'normal'; currentVersion: '1.0.0'; latestVersion: '1.1.0'")
        compare(screen.currentVersion, "1.0.0")
        compare(screen.latestVersion, "1.1.0")
        verify(!screen.isUpToDate)
        verify(screen.hasPendingUpdates || screen.currentVersion !== screen.latestVersion)
        screen.destroy()
    }

    // ── Up to date state ───────────────────────────────────────────
    function test_upToDateState() {
        var screen = createScreen(
            "screenState: 'normal'; currentVersion: '1.0.0'; latestVersion: '1.0.0'")
        verify(screen.isUpToDate)
        screen.destroy()
    }

    // ── Reboot required banner ─────────────────────────────────────
    function test_rebootRequired() {
        var screen = createScreen("screenState: 'normal'; rebootRequired: true")
        verify(screen.rebootBanner.visible)
        screen.destroy()
    }

    // ── Update activation emits signals ────────────────────────────
    function test_updateActivation() {
        var screen = createScreen(
            "screenState: 'normal'; pendingUpdates: [{ id: 'u1', name: 'Kernel' }]")
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'updateActivated' }",
            screen, "updSpy")
        spy.target = screen

        var u0 = screen.pendingRepeater.itemAt(0)
        mouseClick(u0, u0.width / 2, u0.height / 2)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "u1")
        screen.destroy()
    }

    // ── Check for updates signal ───────────────────────────────────
    function test_checkForUpdates() {
        var screen = createScreen("screenState: 'normal'")
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'checkForUpdates' }",
            screen, "checkSpy")
        spy.target = screen

        // Find the "Check for Updates" button
        // It's a MissionButton inside the header row — we test the signal exists
        verify(typeof screen.checkForUpdates === "function")
        screen.destroy()
    }

    // ── Update all signal ──────────────────────────────────────────
    function test_updateAllSignal() {
        var screen = createScreen(
            "screenState: 'normal'; pendingUpdates: [{ id: 'u1', name: 'Kernel' }]")
        verify(typeof screen.updateAll === "function")
        screen.destroy()
    }

    // ── Navigation items emit signals ──────────────────────────────
    function test_navigationActivation() {
        var screen = createScreen("")
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'navigationActivated' }",
            screen, "navSpy")
        spy.target = screen

        var secItem = screen.navRepeater.itemAt(1)
        mouseClick(secItem, secItem.width / 2, secItem.height / 2)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "security")
        compare(screen.selectedNavId, "security")
        screen.destroy()
    }

    // ── Empty state ────────────────────────────────────────────────
    function test_emptyState() {
        var screen = createScreen("screenState: 'empty'")
        verify(screen.emptyHint.visible)
        verify(!screen.loadingIndicator.visible)
        verify(!screen.errorBanner.visible)
        verify(!screen.offlineBanner.visible)
        screen.destroy()
    }

    // ── Loading state ──────────────────────────────────────────────
    function test_loadingState() {
        var screen = createScreen("screenState: 'loading'")
        verify(screen.loadingIndicator.visible)
        screen.destroy()
    }

    // ── Error state ────────────────────────────────────────────────
    function test_errorState() {
        var screen = createScreen("screenState: 'error'")
        verify(screen.errorBanner.visible)
        screen.destroy()
    }

    // ── Offline state ──────────────────────────────────────────────
    function test_offlineState() {
        var screen = createScreen("screenState: 'offline'")
        verify(screen.offlineBanner.visible)
        screen.destroy()
    }

    // ── Keyboard navigation ────────────────────────────────────────
    function test_keyboardNavigation() {
        var screen = createScreen("")
        wait(100)
        var nav0 = screen.navRepeater.itemAt(0)
        nav0.forceActiveFocus()
        verify(nav0.activeFocus)
        keyClick(Qt.Key_Down)
        var nav1 = screen.navRepeater.itemAt(1)
        verify(nav1.activeFocus, "Down must move focus to the next nav item")
        keyClick(Qt.Key_Up)
        verify(nav0.activeFocus, "Up must move focus to the previous nav item")
        screen.destroy()
    }

    // ── Focus visible ──────────────────────────────────────────────
    function test_focusVisible() {
        var screen = createScreen("")
        wait(100)
        var nav0 = screen.navRepeater.itemAt(0)
        nav0.forceActiveFocus()
        verify(nav0.activeFocus)
        screen.destroy()
    }

    // ── Accessibility roles and names ──────────────────────────────
    function test_accessibilityRoles() {
        var screen = createScreen("screenState: 'normal'")
        verify(screen.titleLabel.Accessible.role === Accessible.Heading)
        verify(screen.titleLabel.Accessible.name.length > 0)
        var nav0 = screen.navRepeater.itemAt(0)
        compare(nav0.Accessible.role, Accessible.Button)
        verify(nav0.Accessible.name.length > 0)
        screen.destroy()
    }

    // ── Escape is deliberately unmapped ────────────────────────────
    function test_noEscapeMapping() {
        var screen = createScreen("")
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'navigationActivated' }",
            screen, "escSpy")
        spy.target = screen
        screen.navRepeater.itemAt(0).forceActiveFocus()
        keyClick(Qt.Key_Escape)
        compare(spy.count, 0)
        screen.destroy()
    }

    // ── MissionPage / MissionWindow integration ────────────────────
    function test_missionPageIntegration() {
        var page = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionPage { pageTitle: 'Updates'; MissionHubUpdates { objectName: 'hubUpdInPage' } }",
            root, "hubUpdInPage")
        verify(page !== null)
        verify(page.data.length > 0)
        page.destroy()
    }

    function test_missionWindowIntegration() {
        var screen = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionWindow { width: 1280; height: 720; MissionHubUpdates { objectName: 'hubUpdInWindow' } }",
            root, "hubUpdInWindow")
        verify(screen !== null)
        verify(screen.width > 0)
        screen.destroy()
    }

    // ── Reduced motion does not break rendering ────────────────────
    function test_reducedMotion() {
        var screen = createScreen("screenState: 'normal'")
        screen.reducedMotion = true
        verify(screen.navRepeater.count === 11)
        verify(screen.headerBar.visible)
        verify(screen.sidebar.visible)
        screen.reducedMotion = false
        screen.destroy()
    }

    // ── Defensive handling of incomplete model data ────────────────
    function test_defensiveIncompleteData() {
        var screen = createScreen(
            "screenState: 'normal'; pendingUpdates: [{ id: 'u1' }]")
        verify(screen.pendingRepeater.count === 1)
        var u0 = screen.pendingRepeater.itemAt(0)
        verify(u0 !== null)
        verify(u0.visible)
        screen.destroy()
    }

    // ── Responsive sidebar collapse ────────────────────────────────
    function test_responsiveSidebar() {
        var screen = createScreen("")
        verify(screen.sidebarExpanded)
        screen.width = 600
        verify(!screen.sidebarExpanded)
        screen.width = 1280
        verify(screen.sidebarExpanded)
        screen.destroy()
    }

    // ── Security update indicator ──────────────────────────────────
    function test_securityUpdateIndicator() {
        var screen = createScreen(
            "screenState: 'normal'; pendingUpdates: [{ id: 'u1', name: 'Fix', security: true }]")
        verify(screen.pendingRepeater.count === 1)
        screen.destroy()
    }

    // ── No pending updates: status is UNKNOWN, never fabricated ────
    // The previous default (currentVersion == latestVersion == "0.1.0")
    // made isUpToDate true with no host data — this regression locks
    // the neutral behavior (FABRICATION-9).
    function test_noPendingUpdates() {
        var screen = createScreen("screenState: 'normal'")
        verify(!screen.hasPendingUpdates)
        verify(!screen.versionKnown)
        verify(!screen.isUpToDate)
        compare(screen.statusBadge.text, "Unknown")
        screen.destroy()
    }

    // ── Host-absent: versions empty, status neutral ────────────────
    function test_hostAbsentStatusNeutral() {
        var screen = createScreen("screenState: 'normal'")
        compare(screen.currentVersion, "")
        compare(screen.latestVersion, "")
        verify(!screen.versionKnown)
        verify(!screen.isUpToDate)
        compare(screen.statusBadge.text, "Unknown")
        screen.destroy()
    }

    // ── Loading state: status stays neutral ────────────────────────
    function test_loadingStatusNeutral() {
        var screen = createScreen("screenState: 'loading'")
        verify(screen.loadingIndicator.visible)
        compare(screen.statusBadge.text, "Unknown")
        screen.destroy()
    }

    // ── Valid host data: explicitly up to date renders correctly ───
    function test_hostReportedUpToDate() {
        var screen = createScreen(
            "screenState: 'normal'; currentVersion: '1.0.0'; latestVersion: '1.0.0'")
        verify(screen.versionKnown)
        verify(screen.isUpToDate)
        compare(screen.statusBadge.text, "Up to date")
        screen.destroy()
    }

    // ── Valid host data: pending updates render as pending ─────────
    function test_hostReportedPending() {
        var screen = createScreen(
            "screenState: 'normal'; currentVersion: '1.0.0'; latestVersion: '1.1.0'; " +
            "pendingUpdates: [{ id: 'u1', name: 'Kernel', version: '1.1.0' }]")
        verify(screen.versionKnown)
        verify(!screen.isUpToDate)
        verify(screen.hasPendingUpdates)
        screen.destroy()
    }

    function cleanup() {
        for (var i = 0; i < _hostWindows.length; ++i)
            _hostWindows[i].destroy()
        _hostWindows = []
        MissionTheme.darkMode = false
    }
}
