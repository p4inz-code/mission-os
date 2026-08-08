// Mission OS — Mission Hub Devices (MOS-HUB-009) QtTest suite
import QtQuick
import QtTest
import org.mission.ui 1.0

TestCase {
    id: root
    name: "MissionHubDevices"

    property var _hostWindows: []

    function createScreen(extra) {
        var source = "import QtQuick\nimport org.mission.ui 1.0\nWindow {\nwidth: 1280; height: 720; visible: true\nproperty alias screen: screen\nMissionHubDevices { id: screen; width: 1280; height: 720; " + (extra || "") + " }\n}"
        var host = Qt.createQmlObject(source, root, "hubDevicesHost")
        _hostWindows.push(host)
        return host.screen
    }

    // Recursive objectName lookup for the per-device action buttons
    // (established Mission Hub family test pattern).
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
        var devItem = screen.navRepeater.itemAt(8)
        verify(devItem !== null)
        verify(devItem.Accessible.selected)
        verify(screen.sidebarExpanded)
        screen.destroy()
    }

    function test_devicesRender() {
        var screen = createScreen(
            "screenState: 'normal'; devices: [" +
            "{ id: 'd1', name: 'Logitech Mouse', type: 'usb', status: 'connected', description: 'Wireless mouse' }," +
            "{ id: 'd2', name: 'Monitor', type: 'display', status: 'connected' }" +
            "]")
        verify(screen.deviceCount === 2)
        verify(screen.deviceRepeater.count === 2)
        var d0 = screen.deviceRepeater.itemAt(0)
        verify(d0 !== null)
        verify(d0.visible)
        verify(d0.Accessible.name.length > 0)
        compare(d0.Accessible.role, Accessible.StaticText)
        screen.destroy()
    }

    function test_countProperties() {
        var screen = createScreen(
            "screenState: 'normal'; devices: [" +
            "{ id: 'd1', name: 'A', type: 'usb', status: 'connected' }," +
            "{ id: 'd2', name: 'B', type: 'audio', status: 'connected' }," +
            "{ id: 'd3', name: 'C', type: 'bluetooth', status: 'disabled' }" +
            "]")
        verify(screen.deviceCount === 3)
        verify(screen.connectedCount === 2)
        verify(screen.disabledCount === 1)
        screen.destroy()
    }

    function test_deviceTypeLabels() {
        var screen = createScreen("")
        verify(screen.deviceTypeLabel("usb") === "USB")
        verify(screen.deviceTypeLabel("display") === "Display")
        verify(screen.deviceTypeLabel("audio") === "Audio")
        verify(screen.deviceTypeLabel("bluetooth") === "Bluetooth")
        verify(screen.deviceTypeLabel("network") === "Network Adapter")
        verify(screen.deviceTypeLabel("storage") === "Storage")
        verify(screen.deviceTypeLabel("input") === "Input")
        verify(screen.deviceTypeLabel("bogus") === "Unknown")
        verify(screen.deviceTypeLabel(undefined) === "Unknown")
        screen.destroy()
    }

    function test_deviceStatusLabels() {
        var screen = createScreen("")
        verify(screen.deviceStatusLabel("connected") === "Connected")
        verify(screen.deviceStatusLabel("disabled") === "Disabled")
        verify(screen.deviceStatusLabel(undefined) === "Unknown")
        verify(Qt.colorEqual(screen.deviceStatusColor("connected"), MissionTheme.success))
        verify(Qt.colorEqual(screen.deviceStatusColor("disabled"), MissionTheme.textSecondary))
        screen.destroy()
    }

    function test_refreshSignal() {
        var screen = createScreen("screenState: 'normal'")
        wait(100)
        var spy = Qt.createQmlObject("import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'refreshDevices' }", screen, "refreshSpy")
        spy.target = screen
        verify(screen.refreshButton !== null)
        mouseClick(screen.refreshButton, screen.refreshButton.width / 2, screen.refreshButton.height / 2)
        compare(spy.count, 1)
        screen.destroy()
    }

    function test_identifySignal() {
        var screen = createScreen(
            "screenState: 'normal'; devices: [{ id: 'd1', name: 'Mouse', type: 'usb', status: 'connected' }]")
        wait(100)
        var spy = Qt.createQmlObject("import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'identifyDevice' }", screen, "identifySpy")
        spy.target = screen
        var btn = findChildByName(screen, "devIdentify_d1")
        verify(btn !== null)
        mouseClick(btn, btn.width / 2, btn.height / 2)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "d1")
        screen.destroy()
    }

    function test_disableSignal() {
        var screen = createScreen(
            "screenState: 'normal'; devices: [{ id: 'd1', name: 'Mouse', type: 'usb', status: 'connected' }]")
        wait(100)
        var spy = Qt.createQmlObject("import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'disableDevice' }", screen, "disableSpy")
        spy.target = screen
        var btn = findChildByName(screen, "devDisable_d1")
        verify(btn !== null)
        verify(btn.visible)
        mouseClick(btn, btn.width / 2, btn.height / 2)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "d1")
        screen.destroy()
    }

    function test_troubleshootSignal() {
        var screen = createScreen(
            "screenState: 'normal'; devices: [{ id: 'd1', name: 'Mouse', type: 'usb', status: 'connected' }]")
        wait(100)
        var spy = Qt.createQmlObject("import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'troubleshootDevice' }", screen, "troubleSpy")
        spy.target = screen
        var btn = findChildByName(screen, "devTroubleshoot_d1")
        verify(btn !== null)
        mouseClick(btn, btn.width / 2, btn.height / 2)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "d1")
        screen.destroy()
    }

    function test_disableNotSupported() {
        var screen = createScreen(
            "screenState: 'normal'; devices: [" +
            "{ id: 'd1', name: 'A', type: 'usb', status: 'connected' }," +
            "{ id: 'd2', name: 'B', type: 'audio', status: 'connected', disableSupported: false }" +
            "]")
        wait(100)
        var btn1 = findChildByName(screen, "devDisable_d1")
        var btn2 = findChildByName(screen, "devDisable_d2")
        verify(btn1 !== null)
        verify(btn2 !== null)
        verify(btn1.visible, "Disable must be shown when disableSupported is unset (default true)")
        verify(!btn2.visible, "Disable must be hidden when disableSupported is false")
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

    function test_keyboardActivatesActionButton() {
        var screen = createScreen(
            "screenState: 'normal'; devices: [{ id: 'd1', name: 'Mouse', type: 'usb', status: 'connected' }]")
        wait(100)
        var spy = Qt.createQmlObject("import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'identifyDevice' }", screen, "kbSpy")
        spy.target = screen
        var btn = findChildByName(screen, "devIdentify_d1")
        verify(btn !== null)
        btn.forceActiveFocus()
        verify(btn.activeFocus)
        keyClick(Qt.Key_Space)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "d1")
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
        var page = Qt.createQmlObject("import org.mission.ui 1.0; MissionPage { pageTitle: 'Devices'; MissionHubDevices { objectName: 'hubDevicesInPage' } }", root, "hubDevicesInPage")
        verify(page !== null)
        verify(page.data.length > 0)
        page.destroy()
    }

    function test_missionWindowIntegration() {
        var screen = Qt.createQmlObject("import org.mission.ui 1.0; MissionWindow { width: 1280; height: 720; MissionHubDevices { objectName: 'hubDevicesInWindow' } }", root, "hubDevicesInWindow")
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
        var screen = createScreen("screenState: 'normal'; devices: [{ id: 'd1' }]")
        verify(screen.deviceRepeater.count === 1)
        var d0 = screen.deviceRepeater.itemAt(0)
        verify(d0 !== null)
        verify(d0.visible)
        verify(d0.Accessible.name.length > 0)
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

    function test_noDevices() {
        var screen = createScreen("screenState: 'normal'")
        verify(screen.deviceCount === 0)
        verify(screen.connectedCount === 0)
        verify(screen.disabledCount === 0)
        verify(screen.deviceRepeater.count === 0)
        screen.destroy()
    }

    function cleanup() {
        for (var i = 0; i < _hostWindows.length; ++i) _hostWindows[i].destroy()
        _hostWindows = []
        MissionTheme.darkMode = false
    }
}
