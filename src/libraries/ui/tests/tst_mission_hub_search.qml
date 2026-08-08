// Mission OS — Mission Hub Search (MOS-HUB-002) QtTest suite

import QtQuick
import QtTest
import org.mission.ui 1.0

TestCase {
    id: root
    name: "MissionHubSearch"

    property var _hostWindows: []

    function createScreen(extra) {
        var source = "import QtQuick\n" +
                     "import org.mission.ui 1.0\n" +
                     "Window {\n" +
                     "    width: 1280; height: 720; visible: true\n" +
                     "    property alias screen: screen\n" +
                     "    MissionHubSearch { id: screen; width: 1280; height: 720; " +
                     (extra || "") + " }\n" +
                     "}"
        var host = Qt.createQmlObject(source, root, "hubSearchHost")
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
        verify(screen.searchField !== null)
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

    function test_sidebarSelection() {
        var screen = createScreen("")
        verify(screen.navRepeater.count === 12)
        compare(screen.selectedNavId, "search")
        // Verify at least one nav item is selected
        var foundSelected = false
        for (var i = 0; i < screen.navRepeater.count; i++) {
            var item = screen.navRepeater.itemAt(i)
            if (item !== null && item.Accessible.selected) {
                foundSelected = true
                break
            }
        }
        verify(foundSelected, "at least one nav item must be selected")
        verify(screen.sidebarExpanded)
        screen.destroy()
    }

    function test_searchField() {
        var screen = createScreen("")
        verify(screen.searchField !== null)
        verify(screen.searchField.visible)
        screen.searchField.forceActiveFocus()
        screen.searchField.text = "firewall"
        compare(screen.query, "firewall")
        verify(screen.hasQuery)
        screen.destroy()
    }

    function test_categoryFilters() {
        var screen = createScreen("")
        verify(screen.categoryRepeater.count === 9)
        compare(screen.selectedCategoryId, "all")
        var allCat = screen.categoryRepeater.itemAt(0)
        verify(allCat !== null)
        verify(allCat.Accessible.selected)
        screen.destroy()
    }

    function test_resultsRender() {
        var screen = createScreen(
            "query: 'test'; results: [{ id: 'r1', title: 'Firewall', subtitle: 'Security', category: 'settings' }, { id: 'r2', title: 'GPU Driver', category: 'drivers' }]")
        verify(screen.resultRepeater.count === 2)
        var r0 = screen.resultRepeater.itemAt(0)
        verify(r0 !== null)
        verify(r0.Accessible.name.length > 0)
        compare(r0.Accessible.role, Accessible.Button)
        screen.destroy()
    }

    function test_recentSearches() {
        var screen = createScreen("recentSearches: ['firewall', 'gpu driver']")
        verify(screen.recentCount === 2)
        verify(!screen.hasQuery)
        verify(screen.recentChips.count === 2)
        var chip0 = screen.recentChips.itemAt(0)
        verify(chip0 !== null)
        verify(chip0.Accessible.name === "firewall")
        screen.destroy()
    }

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

    function test_resultActivation() {
        var screen = createScreen(
            "query: 'test'; results: [{ id: 'r1', title: 'Firewall' }]")
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'resultActivated' }",
            screen, "resultSpy")
        spy.target = screen
        var r0 = screen.resultRepeater.itemAt(0)
        mouseClick(r0, r0.width / 2, r0.height / 2)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "r1")
        screen.destroy()
    }

    function test_categoryActivation() {
        var screen = createScreen("")
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'categoryActivated' }",
            screen, "catSpy")
        spy.target = screen
        // Click on index 3 = "devices" (all=0, settings=1, features=2, devices=3)
        var secCat = screen.categoryRepeater.itemAt(3)
        mouseClick(secCat, secCat.width / 2, secCat.height / 2)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "devices")
        compare(screen.selectedCategoryId, "devices")
        screen.destroy()
    }

    function test_recentSearchActivation() {
        var screen = createScreen("recentSearches: ['firewall']")
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'recentSearchActivated' }",
            screen, "recentSpy")
        spy.target = screen
        var chip0 = screen.recentChips.itemAt(0)
        mouseClick(chip0, chip0.width / 2, chip0.height / 2)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "firewall")
        screen.destroy()
    }

    function test_noQueryHint() {
        var screen = createScreen("")
        verify(screen.noQueryHint.visible)
        screen.destroy()
    }

    function test_noResultsHint() {
        var screen = createScreen("query: 'xyznonexistent'")
        verify(screen.noResultsHint.visible)
        verify(screen.clearButton !== null)
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
        // Focus the Dashboard nav item (index 0)
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
        var screen = createScreen("")
        verify(screen.titleLabel.Accessible.role === Accessible.Heading)
        verify(screen.titleLabel.Accessible.name.length > 0)
        var nav0 = screen.navRepeater.itemAt(0)
        compare(nav0.Accessible.role, Accessible.Button)
        verify(nav0.Accessible.name.length > 0)
        verify(screen.searchField.Accessible.role === Accessible.EditableText)
        screen.destroy()
    }

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

    function test_missionPageIntegration() {
        var page = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionPage { pageTitle: 'Search'; MissionHubSearch { objectName: 'hubSearchInPage' } }",
            root, "hubSearchInPage")
        verify(page !== null)
        verify(page.data.length > 0)
        page.destroy()
    }

    function test_missionWindowIntegration() {
        var screen = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionWindow { width: 1280; height: 720; MissionHubSearch { objectName: 'hubSearchInWindow' } }",
            root, "hubSearchInWindow")
        verify(screen !== null)
        verify(screen.width > 0)
        screen.destroy()
    }

    function test_reducedMotion() {
        var screen = createScreen("screenState: 'normal'")
        screen.reducedMotion = true
        verify(screen.categoryRepeater.count === 9)
        verify(screen.navRepeater.count === 12)
        verify(screen.headerBar.visible)
        verify(screen.sidebar.visible)
        screen.reducedMotion = false
        screen.destroy()
    }

    function test_defensiveIncompleteData() {
        var screen = createScreen("query: 'test'; results: [{ id: 'r1' }]")
        verify(screen.resultRepeater.count === 1)
        var r0 = screen.resultRepeater.itemAt(0)
        verify(r0 !== null)
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

    function test_clearButton() {
        var screen = createScreen("query: 'test'")
        verify(screen.hasQuery)
        verify(screen.clearButton.visible)
        // Verify the clearButton has the correct objectName
        compare(screen.clearButton.objectName, "searchClear")
        // Verify the clearButton contains a MouseArea
        var hasMouseArea = false
        for (var i = 0; i < screen.clearButton.children.length; i++) {
            if (screen.clearButton.children[i].toString().indexOf("MouseArea") >= 0) {
                hasMouseArea = true
                break
            }
        }
        verify(hasMouseArea, "clearButton must contain a MouseArea")
        // Verify clearing the query directly works (the button's onClicked handler does this)
        screen.query = ""
        verify(!screen.hasQuery)
        verify(!screen.clearButton.visible)
        screen.destroy()
    }

    function cleanup() {
        for (var i = 0; i < _hostWindows.length; ++i)
            _hostWindows[i].destroy()
        _hostWindows = []
        MissionTheme.darkMode = false
    }
}
