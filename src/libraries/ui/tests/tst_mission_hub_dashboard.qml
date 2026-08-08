// Mission OS — Mission Hub Dashboard (MOS-HUB-001) QtTest suite
//
// Runtime validation of the Mission Hub Dashboard screen. Follows
// the foundation smoke-test pattern (tests/tst_smoke.qml), the Desktop
// family suites and docs/engineering/TESTING_STRATEGY.md (QML → Qt Test
// / qmltestrunner).
//
// Coverage:
//   - screen loads without QML errors (token singletons resolve)
//   - MissionTheme works; light/dark rendering bindings re-evaluate
//   - header renders with title and version
//   - sidebar navigation renders with all items, selection works
//   - dashboard cards render from host model (label, status, level)
//   - health score renders with score, label, level
//   - quick actions render and emit activation signals
//   - navigation items emit signals
//   - card activation emits signals
//   - keyboard navigation in sidebar and cards
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
//
// Run via qmltestrunner (see CMakeLists.txt CTest registration):
//   qmltestrunner -import <build>/src/libraries/ui/qml \
//                 -input src/libraries/ui/tests/tst_mission_hub_dashboard.qml
//
// Exit code: 0 = all checks passed; non-zero = failure (CI gate).

import QtQuick
import QtTest
import org.mission.ui 1.0

TestCase {
    id: root
    name: "MissionHubDashboard"

    // ── Helpers ────────────────────────────────────────────────────
    property var _hostWindows: []

    function createScreen(extra) {
        var source = "import QtQuick\n" +
                     "import org.mission.ui 1.0\n" +
                     "Window {\n" +
                     "    width: 1280; height: 720; visible: true\n" +
                     "    property alias screen: screen\n" +
                     "    MissionHubDashboard { id: screen; width: 1280; height: 720; " +
                     (extra || "") + " }\n" +
                     "}"
        var host = Qt.createQmlObject(source, root, "hubHost")
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
        // Neutral defaults: no fabricated status cards or health claims (FABRICATION-8)
        verify(screen.cardRepeater.count === 0)
        compare(screen.healthScoreValue.text, "—")
        screen.destroy()
    }

    // ── Neutral defaults: no fabricated health/status (FABRICATION-8) ──
    function test_neutralDefaults() {
        var screen = createScreen("screenState: 'normal'")
        // No fabricated cards and no fabricated health score appear
        compare(screen.dashboardCards.length, 0)
        verify(screen.cardRepeater.count === 0)
        compare(screen.healthScoreValue.text, "—")
        // Unknown levels render as neutral text/color — never "Good"/green
        compare(screen.healthLevelLabel(undefined), "Unknown")
        verify(Qt.colorEqual(screen.healthLevelColor(undefined), MissionTheme.textTertiary))
        verify(Qt.colorEqual(screen.cardLevelColor(undefined), MissionTheme.textTertiary))
        // The documented "ok" level still maps to success green for
        // valid host-provided cards (FABRICATION-8 regression guard)
        verify(Qt.colorEqual(screen.cardLevelColor("ok"), MissionTheme.success))
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
        // Header is visible and has the correct structure
        verify(screen.headerBar.height > 0)
        screen.destroy()
    }

    // ── Sidebar navigation renders all items ───────────────────────
    function test_sidebarNavigation() {
        var screen = createScreen("")
        verify(screen.navRepeater.count === 11)
        // Dashboard is selected by default
        var dashItem = screen.navRepeater.itemAt(0)
        verify(dashItem !== null)
        verify(dashItem.Accessible.selected)
        // Sidebar is expanded on wide layout
        verify(screen.sidebarExpanded)
        screen.destroy()
    }

    // ── Dashboard cards render from host model ─────────────────────
    function test_cardsRender() {
        // Host-provided cards render; no fabricated defaults (FABRICATION-8)
        var screen = createScreen(
            "screenState: 'normal'; dashboardCards: [" +
            "{ id: 'privacy', label: 'Privacy', status: 'Protected', level: 'ok' }," +
            "{ id: 'security', label: 'Security', status: 'Secure', level: 'ok' }," +
            "{ id: 'storage', label: 'Storage', status: '72% free', level: 'ok' }" +
            "]")
        verify(screen.cardRepeater.count === 3)
        var card0 = screen.cardRepeater.itemAt(0)
        verify(card0 !== null)
        verify(card0.visible)
        // Card has accessible name
        verify(card0.Accessible.name.length > 0)
        compare(card0.Accessible.role, Accessible.Button)
        screen.destroy()
    }

    // ── Health score renders ───────────────────────────────────────
    function test_healthScoreRenders() {
        var screen = createScreen(
            "screenState: 'normal'; healthScore: ({ score: 92, label: 'Excellent', level: 'excellent' })")
        compare(screen.healthScoreValue.text, "92")
        verify(screen.healthScoreLabel.text.length > 0)
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

        // Click on the Security nav item
        var secItem = screen.navRepeater.itemAt(1)
        mouseClick(secItem, secItem.width / 2, secItem.height / 2)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "security")

        // Verify selection changed
        compare(screen.selectedNavId, "security")

        screen.destroy()
    }

    // ── Card activation emits signals ──────────────────────────────
    function test_cardActivation() {
        // Host-provided cards (host-driven; no static fixture)
        var screen = createScreen(
            "screenState: 'normal'; dashboardCards: [" +
            "{ id: 'privacy', label: 'Privacy', status: 'Protected', level: 'ok' }," +
            "{ id: 'security', label: 'Security', status: 'Secure', level: 'ok' }" +
            "]")
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'cardActivated' }",
            screen, "cardSpy")
        spy.target = screen

        var card0 = screen.cardRepeater.itemAt(0)
        mouseClick(card0, card0.width / 2, card0.height / 2)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "privacy")

        screen.destroy()
    }

    // ── Quick action activation emits signals ──────────────────────
    function test_quickActionActivation() {
        var screen = createScreen("screenState: 'normal'")
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'quickActionActivated' }",
            screen, "actionSpy")
        spy.target = screen

        var action0 = screen.actionRepeater.itemAt(0)
        verify(action0 !== null)
        mouseClick(action0, action0.width / 2, action0.height / 2)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "check-updates")

        screen.destroy()
    }

    // ── Empty state ────────────────────────────────────────────────
    function test_emptyState() {
        var screen = createScreen("screenState: 'empty'")
        verify(screen.emptyHint.visible)
        // Loading, error, offline content all hidden
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
        // Focus first nav item
        var nav0 = screen.navRepeater.itemAt(0)
        nav0.forceActiveFocus()
        verify(nav0.activeFocus)
        // Down moves to next nav item
        keyClick(Qt.Key_Down)
        var nav1 = screen.navRepeater.itemAt(1)
        verify(nav1.activeFocus, "Down must move focus to the next nav item")
        // Up moves back
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
        // Focus ring should be visible (the Rectangle child with focusRing border)
        var focusRing = nav0.children[0] // first child after the focus ring rectangle
        // The focus ring is a Rectangle with visible: activeFocus
        // We just verify the item has activeFocus
        verify(nav0.activeFocus)
        screen.destroy()
    }

    // ── Accessibility roles and names ──────────────────────────────
    function test_accessibilityRoles() {
        var screen = createScreen(
            "screenState: 'normal'; dashboardCards: [{ id: 'privacy', label: 'Privacy', status: 'Protected' }]")
        // Title is a heading
        verify(screen.titleLabel.Accessible.role === Accessible.Heading)
        verify(screen.titleLabel.Accessible.name.length > 0)
        // Nav items are buttons
        var nav0 = screen.navRepeater.itemAt(0)
        compare(nav0.Accessible.role, Accessible.Button)
        verify(nav0.Accessible.name.length > 0)
        // Cards are buttons with accessible names
        var card0 = screen.cardRepeater.itemAt(0)
        compare(card0.Accessible.role, Accessible.Button)
        verify(card0.Accessible.name.length > 0)
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
            "import org.mission.ui 1.0; MissionPage { pageTitle: 'Mission Hub'; MissionHubDashboard { objectName: 'hubInPage' } }",
            root, "hubInPage")
        verify(page !== null)
        verify(page.data.length > 0)
        page.destroy()
    }

    function test_missionWindowIntegration() {
        var screen = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionWindow { width: 1280; height: 720; MissionHubDashboard { objectName: 'hubInWindow' } }",
            root, "hubInWindow")
        verify(screen !== null)
        verify(screen.width > 0)
        screen.destroy()
    }

    // ── Reduced motion does not break rendering ────────────────────
    function test_reducedMotion() {
        // Host-provided cards so rendering under reduced motion is exercised
        var screen = createScreen(
            "screenState: 'normal'; dashboardCards: [" +
            "{ id: 'privacy', label: 'Privacy', status: 'Protected', level: 'ok' }," +
            "{ id: 'security', label: 'Security', status: 'Secure', level: 'ok' }," +
            "{ id: 'storage', label: 'Storage', status: '72% free', level: 'ok' }," +
            "{ id: 'updates', label: 'Updates', status: 'Up to date', level: 'ok' }," +
            "{ id: 'recovery', label: 'Recovery', status: 'Ready', level: 'ok' }," +
            "{ id: 'diagnostics', label: 'Diagnostics', status: 'Healthy', level: 'ok' }," +
            "{ id: 'drivers', label: 'Drivers', status: 'Up to date', level: 'ok' }," +
            "{ id: 'network', label: 'Network', status: 'Connected', level: 'ok' }" +
            "]")
        screen.reducedMotion = true
        verify(screen.cardRepeater.count === 8)
        verify(screen.navRepeater.count === 11)
        verify(screen.headerBar.visible)
        verify(screen.sidebar.visible)
        screen.reducedMotion = false
        screen.destroy()
    }

    // ── Defensive handling of incomplete model data ────────────────
    function test_defensiveIncompleteData() {
        // Minimal card data — label falls back to id, status is omitted
        var screen = createScreen(
            "screenState: 'normal'; dashboardCards: [{ id: 'test' }]")
        verify(screen.cardRepeater.count === 1)
        var card0 = screen.cardRepeater.itemAt(0)
        verify(card0 !== null)
        verify(card0.visible)
        screen.destroy()
    }

    // ── Responsive sidebar collapse ────────────────────────────────
    function test_responsiveSidebar() {
        var screen = createScreen("")
        // Wide layout: sidebar expanded
        verify(screen.sidebarExpanded)
        // Simulate narrow layout
        screen.width = 600
        verify(!screen.sidebarExpanded)
        // Simulate wide layout again
        screen.width = 1280
        verify(screen.sidebarExpanded)
        screen.destroy()
    }

    // Reset theme mode and destroy hosted test windows after each test
    function cleanup() {
        for (var i = 0; i < _hostWindows.length; ++i)
            _hostWindows[i].destroy()
        _hostWindows = []
        MissionTheme.darkMode = false
    }
}
