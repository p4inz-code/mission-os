// Mission OS — Mission Hub Diagnostics (MOS-HUB-008) QtTest suite
import QtQuick
import QtTest
import org.mission.ui 1.0

TestCase {
    id: root
    name: "MissionHubDiagnostics"

    property var _hostWindows: []

    function createScreen(extra) {
        var source = "import QtQuick\nimport org.mission.ui 1.0\nWindow {\nwidth: 1280; height: 720; visible: true\nproperty alias screen: screen\nMissionHubDiagnostics { id: screen; width: 1280; height: 720; " + (extra || "") + " }\n}"
        var host = Qt.createQmlObject(source, root, "hubDiagHost")
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
        var diagItem = screen.navRepeater.itemAt(5)
        verify(diagItem !== null)
        verify(diagItem.Accessible.selected)
        verify(screen.sidebarExpanded)
        screen.destroy()
    }

    function test_diagnosticsOverviewRender() {
        var screen = createScreen(
            "screenState: 'normal'; diagnosticsOverview: ({ lastScan: '2024-01-15 10:30', hardwareIssues: 1, softwareIssues: 0 })")
        verify(screen.diagnosticsOverview.lastScan === "2024-01-15 10:30")
        verify(screen.diagnosticsOverview.hardwareIssues === 1)
        verify(screen.diagnosticsOverview.softwareIssues === 0)
        screen.destroy()
    }

    function test_diagnosticResultsRender() {
        var screen = createScreen(
            "screenState: 'normal'; diagnosticResults: [" +
            "{ id: 'd1', category: 'cpu', status: 'pass' }," +
            "{ id: 'd2', category: 'ram', status: 'warning', description: 'High usage' }," +
            "{ id: 'd3', category: 'storage', status: 'failed', description: 'Failing drive', recommendation: 'Replace drive' }" +
            "]")
        verify(screen.resultCount === 3)
        verify(screen.resultRepeater.count === 3)
        var d0 = screen.resultRepeater.itemAt(0)
        verify(d0 !== null)
        verify(d0.visible)
        verify(d0.Accessible.name.length > 0)
        compare(d0.Accessible.role, Accessible.Button)
        screen.destroy()
    }

    function test_countProperties() {
        var screen = createScreen(
            "screenState: 'normal'; diagnosticResults: [" +
            "{ id: 'd1', category: 'cpu', status: 'pass' }," +
            "{ id: 'd2', category: 'ram', status: 'pass' }," +
            "{ id: 'd3', category: 'storage', status: 'warning' }," +
            "{ id: 'd4', category: 'network', status: 'failed' }" +
            "]")
        verify(screen.passedCount === 2)
        verify(screen.warningCount === 1)
        verify(screen.failedCount === 1)
        screen.destroy()
    }

    function test_resultActivation() {
        var screen = createScreen(
            "screenState: 'normal'; diagnosticResults: [{ id: 'd1', category: 'cpu', status: 'pass' }]")
        wait(100)
        var spy = Qt.createQmlObject("import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'resultActivated' }", screen, "resSpy")
        spy.target = screen
        var d0 = screen.resultRepeater.itemAt(0)
        mouseClick(d0, d0.width / 2, d0.height / 2)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "d1")
        screen.destroy()
    }

    function test_runDiagnosticsSignal() {
        var screen = createScreen("screenState: 'normal'")
        verify(typeof screen.runDiagnostics === "function")
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
        var page = Qt.createQmlObject("import org.mission.ui 1.0; MissionPage { pageTitle: 'Diagnostics'; MissionHubDiagnostics { objectName: 'hubDiagInPage' } }", root, "hubDiagInPage")
        verify(page !== null)
        verify(page.data.length > 0)
        page.destroy()
    }

    function test_missionWindowIntegration() {
        var screen = Qt.createQmlObject("import org.mission.ui 1.0; MissionWindow { width: 1280; height: 720; MissionHubDiagnostics { objectName: 'hubDiagInWindow' } }", root, "hubDiagInWindow")
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
        var screen = createScreen("screenState: 'normal'; diagnosticResults: [{ id: 'd1' }]")
        verify(screen.resultRepeater.count === 1)
        var d0 = screen.resultRepeater.itemAt(0)
        verify(d0 !== null)
        verify(d0.visible)
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

    function test_noResults() {
        var screen = createScreen("screenState: 'normal'")
        verify(screen.resultCount === 0)
        verify(screen.passedCount === 0)
        verify(screen.warningCount === 0)
        verify(screen.failedCount === 0)
        screen.destroy()
    }

    function cleanup() {
        for (var i = 0; i < _hostWindows.length; ++i) _hostWindows[i].destroy()
        _hostWindows = []
        MissionTheme.darkMode = false
    }
}
