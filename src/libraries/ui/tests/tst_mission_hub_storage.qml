// Mission OS — Mission Hub Storage (MOS-HUB-010) QtTest suite
import QtQuick
import QtTest
import org.mission.ui 1.0

TestCase {
    id: root
    name: "MissionHubStorage"

    property var _hostWindows: []

    function createScreen(extra) {
        var source = "import QtQuick\nimport org.mission.ui 1.0\nWindow {\nwidth: 1280; height: 720; visible: true\nproperty alias screen: screen\nMissionHubStorage { id: screen; width: 1280; height: 720; " + (extra || "") + " }\n}"
        var host = Qt.createQmlObject(source, root, "hubStorageHost")
        _hostWindows.push(host)
        return host.screen
    }

    // Recursive objectName lookup for nested volume labels
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
        var storageItem = screen.navRepeater.itemAt(7)
        verify(storageItem !== null)
        verify(storageItem.Accessible.selected)
        verify(screen.sidebarExpanded)
        screen.destroy()
    }

    function test_overviewRender() {
        var screen = createScreen(
            "screenState: 'normal'; storageOverview: ({ totalCapacity: '512 GB', used: '120 GB', free: '392 GB', usagePercent: 24 })")
        verify(screen.storageOverview.totalCapacity === "512 GB")
        verify(screen.storageOverview.used === "120 GB")
        verify(screen.storageOverview.free === "392 GB")
        verify(screen.overviewCard !== null)
        verify(screen.overviewCard.visible)
        verify(screen.overviewUsageBar.visible, "Overview usage bar must render when usagePercent is a number")
        screen.destroy()
    }

    function test_overviewNoUsageBar() {
        var screen = createScreen("screenState: 'normal'; storageOverview: ({ totalCapacity: '512 GB' })")
        verify(screen.overviewUsageBar.visible === false, "Overview usage bar must be hidden when usagePercent is missing")
        screen.destroy()
    }

    function test_volumesRender() {
        var screen = createScreen(
            "screenState: 'normal'; volumes: [" +
            "{ id: 'v1', name: 'System', mountPoint: '/', filesystem: 'ext4', capacity: '512 GB', used: '120 GB', free: '392 GB', encryption: 'LUKS2', health: 'ok' }," +
            "{ id: 'v2', name: 'Home', mountPoint: '/home', filesystem: 'ext4', health: 'warning' }" +
            "]")
        verify(screen.volumeCount === 2)
        verify(screen.volumeRepeater.count === 2)
        var v0 = screen.volumeRepeater.itemAt(0)
        verify(v0 !== null)
        verify(v0.visible)
        verify(v0.Accessible.name.length > 0)
        compare(v0.Accessible.role, Accessible.StaticText)
        screen.destroy()
    }

    function test_healthCounts() {
        var screen = createScreen(
            "screenState: 'normal'; volumes: [" +
            "{ id: 'v1', name: 'A', health: 'ok' }," +
            "{ id: 'v2', name: 'B', health: 'ok' }," +
            "{ id: 'v3', name: 'C', health: 'warning' }," +
            "{ id: 'v4', name: 'D', health: 'critical' }," +
            "{ id: 'v5', name: 'E' }" +
            "]")
        verify(screen.okCount === 2)
        verify(screen.warningCount === 1)
        verify(screen.criticalCount === 1)
        screen.destroy()
    }

    function test_healthLabels() {
        var screen = createScreen("")
        verify(screen.healthLabel("ok") === "OK")
        verify(screen.healthLabel("warning") === "Warning")
        verify(screen.healthLabel("critical") === "Critical")
        verify(screen.healthLabel(undefined) === "Unknown")
        verify(Qt.colorEqual(screen.healthColor("ok"), MissionTheme.success))
        verify(Qt.colorEqual(screen.healthColor("warning"), MissionTheme.warning))
        verify(Qt.colorEqual(screen.healthColor("critical"), MissionTheme.error))
        verify(Qt.colorEqual(screen.healthColor(undefined), MissionTheme.textSecondary))
        screen.destroy()
    }

    function test_validPercent() {
        var screen = createScreen("")
        verify(screen.validPercent(50) === 50)
        verify(screen.validPercent(120) === 100)
        verify(screen.validPercent(-5) === 0)
        verify(screen.validPercent("50") === -1)
        verify(screen.validPercent(undefined) === -1)
        verify(screen.validPercent(NaN) === -1)
        screen.destroy()
    }

    function test_usageBarVisibility() {
        var screen = createScreen(
            "screenState: 'normal'; volumes: [" +
            "{ id: 'v1', name: 'System', health: 'ok', usagePercent: 24 }," +
            "{ id: 'v2', name: 'Home', health: 'ok' }" +
            "]")
        wait(100)
        var bar1 = findChildByName(screen, "usageBar_v1")
        var bar2 = findChildByName(screen, "usageBar_v2")
        verify(bar1 !== null)
        verify(bar2 !== null)
        verify(bar1.visible, "Volume usage bar must render when usagePercent is a number")
        verify(!bar2.visible, "Volume usage bar must be hidden when usagePercent is missing")
        screen.destroy()
    }

    function test_volumeUsageAndCapacityDisplay() {
        var screen = createScreen(
            "screenState: 'normal'; volumes: [" +
            "{ id: 'v1', name: 'System', health: 'ok', usagePercent: 72, capacity: '512 GB', free: '392 GB' }" +
            "]")
        wait(100)
        var row = screen.volumeRepeater.itemAt(0)
        var usage = findChildByName(row, "volUsage_v1")
        var cap = findChildByName(row, "volCapacity_v1")
        verify(usage !== null)
        verify(cap !== null)
        compare(usage.text, "72% used")
        compare(cap.text, "512 GB · 392 GB free")
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
        var page = Qt.createQmlObject("import org.mission.ui 1.0; MissionPage { pageTitle: 'Storage'; MissionHubStorage { objectName: 'hubStorageInPage' } }", root, "hubStorageInPage")
        verify(page !== null)
        verify(page.data.length > 0)
        page.destroy()
    }

    function test_missionWindowIntegration() {
        var screen = Qt.createQmlObject("import org.mission.ui 1.0; MissionWindow { width: 1280; height: 720; MissionHubStorage { objectName: 'hubStorageInWindow' } }", root, "hubStorageInWindow")
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
        var screen = createScreen("screenState: 'normal'; volumes: [{ id: 'v1' }]")
        verify(screen.volumeRepeater.count === 1)
        var v0 = screen.volumeRepeater.itemAt(0)
        verify(v0 !== null)
        verify(v0.visible)
        verify(v0.Accessible.name.length > 0)
        wait(100)
        var usage = findChildByName(v0, "volUsage_v1")
        verify(usage !== null)
        compare(usage.text, "—")
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

    function test_noVolumes() {
        var screen = createScreen("screenState: 'normal'")
        verify(screen.volumeCount === 0)
        verify(screen.okCount === 0)
        verify(screen.warningCount === 0)
        verify(screen.criticalCount === 0)
        verify(screen.volumeRepeater.count === 0)
        screen.destroy()
    }

    function cleanup() {
        for (var i = 0; i < _hostWindows.length; ++i) _hostWindows[i].destroy()
        _hostWindows = []
        MissionTheme.darkMode = false
    }
}
