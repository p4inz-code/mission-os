// Mission OS — Mission Hub Recovery (MOS-HUB-007) QtTest suite
import QtQuick
import QtTest
import org.mission.ui 1.0

TestCase {
    id: root
    name: "MissionHubRecovery"

    property var _hostWindows: []

    function createScreen(extra) {
        var source = "import QtQuick\nimport org.mission.ui 1.0\nWindow {\nwidth: 1280; height: 720; visible: true\nproperty alias screen: screen\nMissionHubRecovery { id: screen; width: 1280; height: 720; " + (extra || "") + " }\n}"
        var host = Qt.createQmlObject(source, root, "hubRecoveryHost")
        _hostWindows.push(host)
        return host.screen
    }

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

    function test_headerRenders() {
        var screen = createScreen("version: '2.0.0'; buildType: 'Stable'")
        compare(screen.titleLabel.text, "Mission Hub")
        verify(screen.headerBar.visible)
        screen.destroy()
    }

    function test_sidebarNavigation() {
        var screen = createScreen("")
        verify(screen.navRepeater.count === 11)
        var recItem = screen.navRepeater.itemAt(4)
        verify(recItem !== null)
        verify(recItem.Accessible.selected)
        verify(screen.sidebarExpanded)
        screen.destroy()
    }

    function test_recoveryStatusRender() {
        var screen = createScreen(
            "screenState: 'normal'; recoveryStatus: ({ recoveryPartition: true, recoveryUsb: false, latestBackup: '2024-01-15', backupEncrypted: true })")
        verify(screen.recoveryStatus.recoveryPartition === true)
        verify(screen.recoveryStatus.recoveryUsb === false)
        verify(screen.recoveryStatus.latestBackup === "2024-01-15")
        verify(screen.recoveryStatus.backupEncrypted === true)
        screen.destroy()
    }

    function test_recoveryOptionsRender() {
        var screen = createScreen(
            "screenState: 'normal'; recoveryOptions: [" +
            "{ id: 'o1', name: 'Startup Repair', description: 'Fix boot issues', destructive: false, available: true }," +
            "{ id: 'o2', name: 'Factory Reset', description: 'Erase all data', destructive: true, available: true }" +
            "]")
        verify(screen.optionCount === 2)
        verify(screen.optionRepeater.count === 2)
        var o0 = screen.optionRepeater.itemAt(0)
        verify(o0 !== null)
        verify(o0.visible)
        verify(o0.Accessible.name.length > 0)
        compare(o0.Accessible.role, Accessible.Button)
        screen.destroy()
    }

    function test_optionActivation() {
        var screen = createScreen(
            "screenState: 'normal'; recoveryOptions: [{ id: 'o1', name: 'Startup Repair' }]")
        wait(100)
        var spy = Qt.createQmlObject("import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'optionActivated' }", screen, "optSpy")
        spy.target = screen
        var o0 = screen.optionRepeater.itemAt(0)
        mouseClick(o0, o0.width / 2, o0.height / 2)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "o1")
        screen.destroy()
    }

    function test_backupRequestedSignal() {
        var screen = createScreen("screenState: 'normal'")
        verify(typeof screen.backupRequested === "function")
        screen.destroy()
    }

    function test_navigationActivation() {
        var screen = createScreen("")
        wait(100)
        var spy = Qt.createQmlObject("import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'navigationActivated' }", screen, "navSpy")
        spy.target = screen
        var dashItem = screen.navRepeater.itemAt(0)
        mouseClick(dashItem, dashItem.width / 2, dashItem.height / 2)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "dashboard")
        compare(screen.selectedNavId, "dashboard")
        screen.destroy()
    }

    function test_emptyState() {
        var screen = createScreen("screenState: 'empty'")
        verify(screen.emptyHint.visible)
        verify(!screen.loadingIndicator.visible)
        verify(!screen.errorBanner.visible)
        verify(!screen.offlineBanner.visible)
        screen.destroy()
    }

    function test_loadingState() {
        var screen = createScreen("screenState: 'loading'")
        verify(screen.loadingIndicator.visible)
        screen.destroy()
    }

    function test_errorState() {
        var screen = createScreen("screenState: 'error'")
        verify(screen.errorBanner.visible)
        screen.destroy()
    }

    function test_offlineState() {
        var screen = createScreen("screenState: 'offline'")
        verify(screen.offlineBanner.visible)
        screen.destroy()
    }

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

    function test_focusVisible() {
        var screen = createScreen("")
        wait(100)
        var nav0 = screen.navRepeater.itemAt(0)
        nav0.forceActiveFocus()
        verify(nav0.activeFocus)
        screen.destroy()
    }

    function test_accessibilityRoles() {
        var screen = createScreen("screenState: 'normal'")
        verify(screen.titleLabel.Accessible.role === Accessible.Heading)
        verify(screen.titleLabel.Accessible.name.length > 0)
        var nav0 = screen.navRepeater.itemAt(0)
        compare(nav0.Accessible.role, Accessible.Button)
        verify(nav0.Accessible.name.length > 0)
        screen.destroy()
    }

    function test_noEscapeMapping() {
        var screen = createScreen("")
        wait(100)
        var spy = Qt.createQmlObject("import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'navigationActivated' }", screen, "escSpy")
        spy.target = screen
        screen.navRepeater.itemAt(0).forceActiveFocus()
        keyClick(Qt.Key_Escape)
        compare(spy.count, 0)
        screen.destroy()
    }

    function test_missionPageIntegration() {
        var page = Qt.createQmlObject("import org.mission.ui 1.0; MissionPage { pageTitle: 'Recovery'; MissionHubRecovery { objectName: 'hubRecInPage' } }", root, "hubRecInPage")
        verify(page !== null)
        verify(page.data.length > 0)
        page.destroy()
    }

    function test_missionWindowIntegration() {
        var screen = Qt.createQmlObject("import org.mission.ui 1.0; MissionWindow { width: 1280; height: 720; MissionHubRecovery { objectName: 'hubRecInWindow' } }", root, "hubRecInWindow")
        verify(screen !== null)
        verify(screen.width > 0)
        screen.destroy()
    }

    function test_reducedMotion() {
        var screen = createScreen("screenState: 'normal'")
        screen.reducedMotion = true
        verify(screen.navRepeater.count === 11)
        verify(screen.headerBar.visible)
        verify(screen.sidebar.visible)
        screen.reducedMotion = false
        screen.destroy()
    }

    function test_defensiveIncompleteData() {
        var screen = createScreen("screenState: 'normal'; recoveryOptions: [{ id: 'o1' }]")
        verify(screen.optionRepeater.count === 1)
        var o0 = screen.optionRepeater.itemAt(0)
        verify(o0 !== null)
        verify(o0.visible)
        screen.destroy()
    }

    function test_responsiveSidebar() {
        var screen = createScreen("")
        verify(screen.sidebarExpanded)
        screen.width = 600
        verify(!screen.sidebarExpanded)
        screen.width = 1280
        verify(screen.sidebarExpanded)
        screen.destroy()
    }

    function test_noOptions() {
        var screen = createScreen("screenState: 'normal'")
        verify(screen.optionCount === 0)
        screen.destroy()
    }

    function cleanup() {
        for (var i = 0; i < _hostWindows.length; ++i) _hostWindows[i].destroy()
        _hostWindows = []
        MissionTheme.darkMode = false
    }
}
