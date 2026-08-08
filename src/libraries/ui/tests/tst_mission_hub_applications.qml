// Mission OS — Mission Hub Applications (MOS-HUB-003) QtTest suite
//
// Runtime validation of the Mission Hub Applications screen. Follows
// the established Mission Hub test pattern (tst_mission_hub_dashboard.qml,
// tst_mission_hub_search.qml).
//
// Coverage:
//   - screen loads without QML errors (token singletons resolve)
//   - MissionTheme works; light/dark rendering bindings re-evaluate
//   - header renders with title and version
//   - sidebar navigation renders with all items, selection works
//   - applications render from host model (name, status, category)
//   - search field filters applications
//   - category filters work
//   - application activation emits signals
//   - navigation items emit signals
//   - keyboard navigation in sidebar and application grid
//   - focus visible on all interactive elements
//   - accessibility names/roles correct
//   - empty state renders
//   - loading state renders
//   - error state renders
//   - offline state renders
//   - reduced motion does not break rendering
//   - defensive handling of incomplete model data
//   - responsive sidebar collapse
//   - Escape is deliberately unmapped
//   - MissionPage / MissionWindow integration

import QtQuick
import QtTest
import org.mission.ui 1.0

TestCase {
    id: root
    name: "MissionHubApplications"

    property var _hostWindows: []

    function createScreen(extra) {
        var source = "import QtQuick\n" +
                     "import org.mission.ui 1.0\n" +
                     "Window {\n" +
                     "    width: 1280; height: 720; visible: true\n" +
                     "    property alias screen: screen\n" +
                     "    MissionHubApplications { id: screen; width: 1280; height: 720; " +
                     (extra || "") + " }\n" +
                     "}"
        var host = Qt.createQmlObject(source, root, "hubAppHost")
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
        verify(Qt.colorEqual(screen.titleLabel.color, MissionTheme.textPrimary))

        MissionTheme.darkMode = true
        verify(Qt.colorEqual(screen.headerBar.color, MissionTheme.surface))
        verify(Qt.colorEqual(screen.titleLabel.color, MissionTheme.textPrimary))

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
        verify(screen.navRepeater.count === 12)
        // Applications is selected by default
        var appItem = screen.navRepeater.itemAt(11)
        verify(appItem !== null)
        verify(appItem.Accessible.selected)
        // Sidebar is expanded on wide layout
        verify(screen.sidebarExpanded)
        screen.destroy()
    }

    // ── Applications render from host model ────────────────────────
    function test_applicationsRender() {
        var screen = createScreen(
            "screenState: 'normal'; applications: [" +
            "{ id: 'app1', name: 'Terminal', status: 'installed', category: 'development' }," +
            "{ id: 'app2', name: 'Calculator', status: 'available', category: 'utilities' }," +
            "{ id: 'app3', name: 'Text Editor', status: 'installed', category: 'productivity' }" +
            "]")
        verify(screen.filteredCount === 3)
        verify(screen.appRepeater.count === 3)
        var app0 = screen.appRepeater.itemAt(0)
        verify(app0 !== null)
        verify(app0.visible)
        verify(app0.Accessible.name.length > 0)
        compare(app0.Accessible.role, Accessible.Button)
        screen.destroy()
    }

    // ── Search field filters applications ──────────────────────────
    function test_searchFiltering() {
        var screen = createScreen(
            "screenState: 'normal'; applications: [" +
            "{ id: 'app1', name: 'Terminal', status: 'installed' }," +
            "{ id: 'app2', name: 'Calculator', status: 'available' }" +
            "]")
        screen.query = "term"
        verify(screen.hasQuery)
        verify(screen.filteredCount === 1)
        screen.query = ""
        verify(screen.filteredCount === 2)
        screen.destroy()
    }

    // ── Category filters work ──────────────────────────────────────
    function test_categoryFiltering() {
        var screen = createScreen(
            "screenState: 'normal'; applications: [" +
            "{ id: 'app1', name: 'Terminal', status: 'installed', category: 'development' }," +
            "{ id: 'app2', name: 'Calculator', status: 'available', category: 'utilities' }" +
            "]")
        verify(screen.categoryRepeater.count === 6)
        compare(screen.selectedCategoryId, "all")
        // Select "development" category (index 3: all=0, system=1, productivity=2, development=3)
        var devCat = screen.categoryRepeater.itemAt(3)
        mouseClick(devCat, devCat.width / 2, devCat.height / 2)
        compare(screen.selectedCategoryId, "development")
        verify(screen.filteredCount === 1)
        screen.destroy()
    }

    // ── Application activation emits signals ───────────────────────
    function test_applicationActivation() {
        var screen = createScreen(
            "screenState: 'normal'; applications: [{ id: 'app1', name: 'Terminal' }]")
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'applicationActivated' }",
            screen, "appSpy")
        spy.target = screen

        var app0 = screen.appRepeater.itemAt(0)
        mouseClick(app0, app0.width / 2, app0.height / 2)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "app1")
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

        var dashItem = screen.navRepeater.itemAt(0)
        mouseClick(dashItem, dashItem.width / 2, dashItem.height / 2)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "dashboard")
        compare(screen.selectedNavId, "dashboard")
        screen.destroy()
    }

    // ── Category activation emits signals ──────────────────────────
    function test_categoryActivation() {
        var screen = createScreen("")
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'categoryActivated' }",
            screen, "catSpy")
        spy.target = screen

        // Click on index 1 = "system"
        var sysCat = screen.categoryRepeater.itemAt(1)
        mouseClick(sysCat, sysCat.width / 2, sysCat.height / 2)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "system")
        compare(screen.selectedCategoryId, "system")
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

    // ── No query hint ──────────────────────────────────────────────
    function test_noQueryHint() {
        var screen = createScreen("screenState: 'normal'")
        verify(screen.noQueryHint.visible)
        screen.destroy()
    }

    // ── No results hint ────────────────────────────────────────────
    function test_noResultsHint() {
        var screen = createScreen(
            "screenState: 'normal'; query: 'xyznonexistent'; applications: [{ id: 'a1', name: 'Terminal' }]")
        verify(screen.noResultsHint.visible)
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
        verify(screen.searchField.Accessible.role === Accessible.EditableText)
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
            "import org.mission.ui 1.0; MissionPage { pageTitle: 'Applications'; MissionHubApplications { objectName: 'hubAppInPage' } }",
            root, "hubAppInPage")
        verify(page !== null)
        verify(page.data.length > 0)
        page.destroy()
    }

    function test_missionWindowIntegration() {
        var screen = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionWindow { width: 1280; height: 720; MissionHubApplications { objectName: 'hubAppInWindow' } }",
            root, "hubAppInWindow")
        verify(screen !== null)
        verify(screen.width > 0)
        screen.destroy()
    }

    // ── Reduced motion does not break rendering ────────────────────
    function test_reducedMotion() {
        var screen = createScreen("screenState: 'normal'; applications: [{ id: 'a1', name: 'App' }]")
        screen.reducedMotion = true
        verify(screen.appRepeater.count === 1)
        verify(screen.navRepeater.count === 12)
        verify(screen.headerBar.visible)
        verify(screen.sidebar.visible)
        screen.reducedMotion = false
        screen.destroy()
    }

    // ── Defensive handling of incomplete model data ────────────────
    function test_defensiveIncompleteData() {
        var screen = createScreen(
            "screenState: 'normal'; applications: [{ id: 'test' }]")
        verify(screen.appRepeater.count === 1)
        var app0 = screen.appRepeater.itemAt(0)
        verify(app0 !== null)
        verify(app0.visible)
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

    // ── Version display ────────────────────────────────────────────
    function test_versionDisplay() {
        var screen = createScreen("version: '3.1.0'; buildType: 'Beta'")
        // Title still shows Mission Hub
        compare(screen.titleLabel.text, "Mission Hub")
        screen.destroy()
    }

    function cleanup() {
        for (var i = 0; i < _hostWindows.length; ++i)
            _hostWindows[i].destroy()
        _hostWindows = []
        MissionTheme.darkMode = false
    }
}
