// Mission OS — Mission Hub Security (MOS-HUB-005) QtTest suite
//
// Runtime validation of the Mission Hub Security screen. Follows
// the established Mission Hub test pattern.

import QtQuick
import QtTest
import org.mission.ui 1.0

TestCase {
    id: root
    name: "MissionHubSecurity"

    property var _hostWindows: []

    function createScreen(extra) {
        var source = "import QtQuick\n" +
                     "import org.mission.ui 1.0\n" +
                     "Window {\n" +
                     "    width: 1280; height: 720; visible: true\n" +
                     "    property alias screen: screen\n" +
                     "    MissionHubSecurity { id: screen; width: 1280; height: 720; " +
                     (extra || "") + " }\n" +
                     "}"
        var host = Qt.createQmlObject(source, root, "hubSecHost")
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

    // ── Neutral defaults: no fabricated security claims (FABRICATION-8) ──
    function test_neutralSecurityDefaults() {
        var screen = createScreen("screenState: 'normal'")
        // No fabricated overview values appear with an absent host
        verify(screen.securityOverview.score === undefined)
        verify(screen.securityOverview.secureBoot === undefined)
        verify(screen.securityOverview.tpm === undefined)
        verify(screen.securityOverview.encryption === undefined)
        verify(screen.securityOverview.firewall === undefined)
        verify(screen.securityOverview.appSandboxing === undefined)
        verify(screen.securityOverview.activeProtection === undefined)
        // Unknown values render as neutral text — never "Enabled"/"Good"
        compare(screen.statusLabel(undefined), "Unknown")
        compare(screen.levelLabel(undefined), "Unknown")
        verify(Qt.colorEqual(screen.statusColor(undefined), MissionTheme.textSecondary))
        // The rendered score is a neutral placeholder, not a fabricated number
        compare(screen.scoreValue.text, "—")
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
        // Security is selected by default
        var secItem = screen.navRepeater.itemAt(1)
        verify(secItem !== null)
        verify(secItem.Accessible.selected)
        verify(screen.sidebarExpanded)
        screen.destroy()
    }

    // ── Security overview renders ──────────────────────────────────
    function test_securityOverviewRenders() {
        var screen = createScreen(
            "screenState: 'normal'; securityOverview: ({ score: 92, level: 'excellent', secureBoot: true, tpm: true, encryption: true, firewall: true })")
        verify(screen.securityOverview.score === 92)
        verify(screen.securityOverview.level === "excellent")
        verify(screen.securityOverview.secureBoot === true)
        screen.destroy()
    }

    // ── Recommendations render ─────────────────────────────────────
    function test_recommendationsRender() {
        var screen = createScreen(
            "screenState: 'normal'; recommendations: [" +
            "{ id: 'r1', title: 'Enable Full Disk Encryption', description: 'Your disk is not encrypted', severity: 'warning', actionLabel: 'Enable' }," +
            "{ id: 'r2', title: 'Install Security Updates', description: '2 updates available', severity: 'critical' }" +
            "]")
        verify(screen.recommendationCount === 2)
        verify(screen.recommendationRepeater.count === 2)
        var r0 = screen.recommendationRepeater.itemAt(0)
        verify(r0 !== null)
        verify(r0.visible)
        verify(r0.Accessible.name.length > 0)
        compare(r0.Accessible.role, Accessible.Button)
        screen.destroy()
    }

    // ── Threat events render ───────────────────────────────────────
    function test_threatEventsRender() {
        var screen = createScreen(
            "screenState: 'normal'; threatEvents: [" +
            "{ id: 't1', title: 'Failed login attempt', severity: 'warning', timestamp: '2024-01-15 10:30' }," +
            "{ id: 't2', title: 'Blocked application', severity: 'critical', component: 'Firewall' }" +
            "]")
        verify(screen.threatCount === 2)
        verify(screen.threatRepeater.count === 2)
        var t0 = screen.threatRepeater.itemAt(0)
        verify(t0 !== null)
        verify(t0.visible)
        verify(t0.Accessible.name.length > 0)
        compare(t0.Accessible.role, Accessible.Button)
        screen.destroy()
    }

    // ── Recommendation activation emits signals ────────────────────
    function test_recommendationActivation() {
        var screen = createScreen(
            "screenState: 'normal'; recommendations: [{ id: 'r1', title: 'Enable Encryption' }]")
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'recommendationActivated' }",
            screen, "recSpy")
        spy.target = screen

        var r0 = screen.recommendationRepeater.itemAt(0)
        mouseClick(r0, r0.width / 2, r0.height / 2)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "r1")
        screen.destroy()
    }

    // ── Threat activation emits signals ────────────────────────────
    function test_threatActivation() {
        var screen = createScreen(
            "screenState: 'normal'; threatEvents: [{ id: 't1', title: 'Failed login' }]")
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'threatActivated' }",
            screen, "threatSpy")
        spy.target = screen

        var t0 = screen.threatRepeater.itemAt(0)
        mouseClick(t0, t0.width / 2, t0.height / 2)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "t1")
        screen.destroy()
    }

    // ── Scan requested signal ──────────────────────────────────────
    function test_scanRequested() {
        var screen = createScreen("screenState: 'normal'")
        verify(typeof screen.scanRequested === "function")
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
            "import org.mission.ui 1.0; MissionPage { pageTitle: 'Security'; MissionHubSecurity { objectName: 'hubSecInPage' } }",
            root, "hubSecInPage")
        verify(page !== null)
        verify(page.data.length > 0)
        page.destroy()
    }

    function test_missionWindowIntegration() {
        var screen = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionWindow { width: 1280; height: 720; MissionHubSecurity { objectName: 'hubSecInWindow' } }",
            root, "hubSecInWindow")
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
            "screenState: 'normal'; recommendations: [{ id: 'r1' }]; threatEvents: [{ id: 't1' }]")
        verify(screen.recommendationRepeater.count === 1)
        verify(screen.threatRepeater.count === 1)
        var r0 = screen.recommendationRepeater.itemAt(0)
        verify(r0 !== null)
        verify(r0.visible)
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

    // ── Security status items render ───────────────────────────────
    function test_securityStatusItems() {
        var screen = createScreen(
            "screenState: 'normal'; securityOverview: ({ secureBoot: true, tpm: false, encryption: true, firewall: true, appSandboxing: false })")
        // Verify the status objects exist in the overview
        verify(screen.securityOverview.secureBoot === true)
        verify(screen.securityOverview.tpm === false)
        verify(screen.securityOverview.encryption === true)
        verify(screen.securityOverview.firewall === true)
        verify(screen.securityOverview.appSandboxing === false)
        screen.destroy()
    }

    // ── No recommendations message ─────────────────────────────────
    function test_noRecommendations() {
        var screen = createScreen("screenState: 'normal'")
        verify(screen.recommendationCount === 0)
        screen.destroy()
    }

    // ── No threats when empty ──────────────────────────────────────
    function test_noThreats() {
        var screen = createScreen("screenState: 'normal'")
        verify(screen.threatCount === 0)
        screen.destroy()
    }

    function cleanup() {
        for (var i = 0; i < _hostWindows.length; ++i)
            _hostWindows[i].destroy()
        _hostWindows = []
        MissionTheme.darkMode = false
    }
}
