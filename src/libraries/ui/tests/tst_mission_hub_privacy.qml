// Mission OS — Mission Hub Privacy (MOS-HUB-006) QtTest suite
import QtQuick
import QtTest
import org.mission.ui 1.0

TestCase {
    id: root
    name: "MissionHubPrivacy"

    property var _hostWindows: []

    function createScreen(extra) {
        var source = "import QtQuick\nimport org.mission.ui 1.0\nWindow {\nwidth: 1280; height: 720; visible: true\nproperty alias screen: screen\nMissionHubPrivacy { id: screen; width: 1280; height: 720; " + (extra || "") + " }\n}"
        var host = Qt.createQmlObject(source, root, "hubPrivacyHost")
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
        verify(screen.headerBar.height > 0)
        screen.destroy()
    }

    function test_sidebarNavigation() {
        var screen = createScreen("")
        verify(screen.navRepeater.count === 11)
        var privItem = screen.navRepeater.itemAt(2)
        verify(privItem !== null)
        verify(privItem.Accessible.selected)
        verify(screen.sidebarExpanded)
        screen.destroy()
    }

    function test_permissionsRender() {
        var screen = createScreen(
            "screenState: 'normal'; permissions: [" +
            "{ id: 'p1', app: 'Firefox', permission: 'Camera', status: 'granted' }," +
            "{ id: 'p2', app: 'Signal', permission: 'Microphone', status: 'denied' }" +
            "]")
        verify(screen.permissionCount === 2)
        verify(screen.permissionRepeater.count === 2)
        var p0 = screen.permissionRepeater.itemAt(0)
        verify(p0 !== null)
        verify(p0.visible)
        verify(p0.Accessible.name.length > 0)
        compare(p0.Accessible.role, Accessible.Button)
        screen.destroy()
    }

    function test_activeIndicatorsRender() {
        var screen = createScreen(
            "screenState: 'normal'; activeIndicators: [" +
            "{ id: 'a1', type: 'camera', app: 'Firefox' }," +
            "{ id: 'a2', type: 'microphone', app: 'Zoom' }" +
            "]")
        verify(screen.indicatorCount === 2)
        verify(screen.indicatorRepeater.count === 2)
        var a0 = screen.indicatorRepeater.itemAt(0)
        verify(a0 !== null)
        verify(a0.visible)
        screen.destroy()
    }

    function test_recommendationsRender() {
        var screen = createScreen(
            "screenState: 'normal'; recommendations: [" +
            "{ id: 'r1', title: 'Review camera permissions', severity: 'warning' }" +
            "]")
        verify(screen.recommendationCount === 1)
        verify(screen.recommendationRepeater.count === 1)
        screen.destroy()
    }

    function test_privacyStatusRender() {
        var screen = createScreen(
            "screenState: 'normal'; privacyStatus: ({ telemetry: false, crashReporting: true, locationAccess: false })")
        verify(screen.privacyStatus.telemetry === false)
        verify(screen.privacyStatus.crashReporting === true)
        verify(screen.privacyStatus.locationAccess === false)
        screen.destroy()
    }

    function test_permissionActivation() {
        var screen = createScreen(
            "screenState: 'normal'; permissions: [{ id: 'p1', permission: 'Camera' }]")
        wait(100)
        var spy = Qt.createQmlObject("import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'permissionActivated' }", screen, "permSpy")
        spy.target = screen
        var p0 = screen.permissionRepeater.itemAt(0)
        mouseClick(p0, p0.width / 2, p0.height / 2)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "p1")
        screen.destroy()
    }

    function test_indicatorActivation() {
        var screen = createScreen("screenState: 'normal'; activeIndicators: [{ id: 'a1', type: 'camera' }]")
        wait(100)
        var spy = Qt.createQmlObject("import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'indicatorActivated' }", screen, "indSpy")
        spy.target = screen
        var a0 = screen.indicatorRepeater.itemAt(0)
        mouseClick(a0, a0.width / 2, a0.height / 2)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "a1")
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
        var page = Qt.createQmlObject("import org.mission.ui 1.0; MissionPage { pageTitle: 'Privacy'; MissionHubPrivacy { objectName: 'hubPrivInPage' } }", root, "hubPrivInPage")
        verify(page !== null)
        verify(page.data.length > 0)
        page.destroy()
    }

    function test_missionWindowIntegration() {
        var screen = Qt.createQmlObject("import org.mission.ui 1.0; MissionWindow { width: 1280; height: 720; MissionHubPrivacy { objectName: 'hubPrivInWindow' } }", root, "hubPrivInWindow")
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
        var screen = createScreen("screenState: 'normal'; permissions: [{ id: 'p1' }]; recommendations: [{ id: 'r1' }]")
        verify(screen.permissionRepeater.count === 1)
        verify(screen.recommendationRepeater.count === 1)
        var p0 = screen.permissionRepeater.itemAt(0)
        verify(p0 !== null)
        verify(p0.visible)
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

    function test_noPermissions() {
        var screen = createScreen("screenState: 'normal'")
        verify(screen.permissionCount === 0)
        screen.destroy()
    }

    function cleanup() {
        for (var i = 0; i < _hostWindows.length; ++i) _hostWindows[i].destroy()
        _hostWindows = []
        MissionTheme.darkMode = false
    }
}
