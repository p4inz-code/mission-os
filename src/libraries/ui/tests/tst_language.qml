// Mission OS — Installer Language Selection (MOS-INS-002) QtTest suite
//
// Runtime validation of the Language Selection screen. Follows the
// foundation smoke-test pattern (tests/tst_smoke.qml) and the
// MOS-INS-001 InstallerWelcome suite (tests/tst_installer_welcome.qml)
// per docs/engineering/TESTING_STRATEGY.md (QML → Qt Test / qmltestrunner).
//
// Coverage:
//   - screen loads without QML errors (token singletons resolve)
//   - MissionTheme works; light/dark rendering bindings re-evaluate
//   - full language list is exposed and populated
//   - search/filter narrows the list; empty state appears with no matches
//   - region/variant picker appears for multi-region languages and emits
//     the correct locale code
//   - languageChangeRequested is wired from list + region selection
//   - primary actions exist (Continue/Back/Retry)
//   - required state transitions (empty/loading/error/success/offline)
//   - Continue never advances while loading/error
//   - keyboard focus reaches actionable controls in logical order;
//     arrows move the list, Enter/Space activate
//   - MissionPage / MissionWindow integration introduces no runtime errors
//
// Run via qmltestrunner (see CMakeLists.txt CTest registration):
//   qmltestrunner -import <build>/src/libraries/ui/qml \
//                 -input src/libraries/ui/tests/tst_language.qml
//
// Exit code: 0 = all checks passed; non-zero = failure (CI gate).

import QtQuick
import QtTest
import org.mission.ui 1.0

TestCase {
    id: root
    name: "LanguageSelection"

    // ── Helpers ────────────────────────────────────────────────────
    // Same hosted-window pattern as tst_installer_welcome.qml: items
    // hosted directly under the TestCase report visible=false on this
    // Qt build, so every screen under test lives in an explicit visible
    // Window; cleanup() destroys the host windows afterwards.
    property var _hostWindows: []

    function createScreen(extra) {
        return createScreenAt(1024, 768, extra)
    }

    function createScreenAt(width, height, extra) {
        var source = "import QtQuick\n" +
                     "import org.mission.ui 1.0\n" +
                     "Window {\n" +
                     "    width: " + width + "; height: " + height + "; visible: true\n" +
                     "    property alias screen: screen\n" +
                     "    LanguageSelection { id: screen; width: " + width + "; height: " + height + "; " +
                     (extra || "") + " }\n" +
                     "}"
        var host = Qt.createQmlObject(source, root, "langHost")
        _hostWindows.push(host)
        return host.screen
    }

    // ── Screen loads; tokens resolve; no QML errors ────────────────
    function test_screenLoads() {
        var screen = createScreen()
        verify(screen !== null)
        verify(screen.height > 0)
        // Token singletons must resolve through the screen's bindings
        verify(Qt.colorEqual(screen.backgroundColor, Colors.background))
        verify(Qt.colorEqual(screen.headingColor, Colors.textPrimary))
        verify(screen.headingLabel.text.length > 0)
        verify(screen.searchField !== null)
        verify(screen.continueButton.text.length > 0)
        // The full language list must be populated
        verify(screen.languages.length >= 25)
        // English is the default selection on load
        compare(screen.currentLanguage, "English")
        compare(screen.currentLocale, "en_US")
        screen.destroy()
    }

    // ── Loading must not emit a spurious language change ───────────
    function test_noLanguageSignalOnLoad() {
        // Spy is created together with the screen so a signal emitted
        // during construction would be caught (regression guard: the
        // preselect-on-load must stay non-emitting).
        var source = "import QtQuick\n" +
                     "import QtTest\n" +
                     "import org.mission.ui 1.0\n" +
                     "Window {\n" +
                     "    width: 1024; height: 768; visible: true\n" +
                     "    property alias screen: screen\n" +
                     "    property alias spy: spy\n" +
                     "    LanguageSelection { id: screen; width: 1024; height: 768\n" +
                     "        SignalSpy { id: spy; signalName: 'languageChangeRequested'; target: screen }\n" +
                     "    }\n" +
                     "}"
        var host = Qt.createQmlObject(source, root, "langLoadHost")
        _hostWindows.push(host)
        compare(host.spy.count, 0)
        host.destroy()
    }

    // ── MissionTheme light/dark rendering bindings ─────────────────
    function test_themeLightAndDark() {
        var screen = createScreen()
        MissionTheme.darkMode = false
        verify(Qt.colorEqual(screen.backgroundColor, Colors.background))
        verify(Qt.colorEqual(screen.backgroundColor, MissionTheme.background))
        verify(Qt.colorEqual(screen.headingColor, MissionTheme.textPrimary))

        MissionTheme.darkMode = true
        verify(Qt.colorEqual(screen.backgroundColor, Colors.darkBackground))
        verify(Qt.colorEqual(screen.backgroundColor, MissionTheme.background))
        verify(Qt.colorEqual(screen.headingColor, MissionTheme.textPrimary))

        MissionTheme.darkMode = false
        verify(Qt.colorEqual(screen.backgroundColor, Colors.background))
        screen.destroy()
    }

    // ── Primary actions exist ──────────────────────────────────────
    function test_primaryActionsExist() {
        var screen = createScreen()
        verify(screen.continueButton !== null)
        verify(screen.backButton !== null)
        verify(screen.searchField !== null)
        verify(screen.continueButton.visible)
        verify(screen.continueButton.enabled)
        // Back is enabled on step 2 (Language is the second installer step)
        verify(screen.backButton.enabled)
        // Continue is primary variant; Back is secondary
        compare(screen.continueButton.variant, MissionButton.Variant.Primary)
        compare(screen.backButton.variant, MissionButton.Variant.Secondary)
        screen.destroy()
    }

    // ── Language selection emits the locale code ───────────────────
    function test_languageSelection() {
        var screen = createScreen()
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'languageChangeRequested' }",
            screen, "langSpy")
        spy.target = screen

        // Selecting Deutsch (index 1 in the full list) emits de_DE
        screen.selectLanguage(1)
        compare(screen.currentLanguage, "Deutsch")
        compare(screen.currentLocale, "de_DE")
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "de_DE")

        // Out of range is ignored
        screen.selectLanguage(999)
        compare(spy.count, 1)

        screen.destroy()
    }

    // ── Search / filter ────────────────────────────────────────────
    function test_searchFilter() {
        var screen = createScreen()
        var fullCount = screen.languages.length

        // Filtering by code narrows the list
        screen.searchText = "de_DE"
        compare(screen.languageList.count, 1)
        // Filtering by label narrows the list
        screen.searchText = "Español"
        compare(screen.languageList.count, 1)
        // Region label is searchable too (Screen 08: "Search by city or country")
        screen.searchText = "Brasil"
        verify(screen.languageList.count >= 1)
        // Unmatched query → empty state with a clear action
        screen.searchText = "zzzz-not-a-language"
        compare(screen.languageList.count, 0)
        verify(screen.emptyState.visible)
        // A11y: the list drops out of the Tab chain behind the overlay
        verify(!screen.languageList.activeFocusOnTab)
        screen.clearSearchButton.clicked()
        compare(screen.searchText, "")
        compare(screen.languageList.count, fullCount)
        verify(!screen.emptyState.visible)
        verify(screen.languageList.activeFocusOnTab)

        screen.destroy()
    }

    // ── Region / variant picker ────────────────────────────────────
    function test_regionVariants() {
        var screen = createScreen()
        // English (default) has 4 regional variants → picker is visible
        verify(screen.selectedLanguage !== null)
        compare(screen.regionRows.count, 4)
        verify(screen.regionSection.visible)
        compare(screen.currentLocale, "en_US")

        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'languageChangeRequested' }",
            screen, "regionSpy")
        spy.target = screen

        // Selecting the UK variant updates the locale + emits the code
        screen.selectRegion(1)
        compare(screen.currentRegion, "United Kingdom")
        compare(screen.currentLocale, "en_GB")
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "en_GB")

        // Out-of-range region is ignored
        screen.selectRegion(99)
        compare(spy.count, 1)

        // A single-region language shows no region picker (Polski)
        screen.selectLanguage(7)
        compare(screen.currentLocale, "pl_PL")
        verify(!screen.regionSection.visible)

        screen.destroy()
    }

    // ── Action signals fire from the right controls ────────────────
    function test_actionSignals() {
        var screen = createScreen()
        var spies = []
        var spyNames = ["continueRequested", "backRequested", "retryRequested"]
        for (var i = 0; i < spyNames.length; ++i) {
            var spy = Qt.createQmlObject(
                "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: '" +
                spyNames[i] + "' }", screen, "spy" + i)
            spy.target = screen
            spies.push(spy)
        }

        screen.continueButton.clicked()
        compare(spies[0].count, 1)

        screen.backButton.clicked()
        compare(spies[1].count, 1)

        screen.screenState = "error"
        screen.retryButton.clicked()
        compare(spies[2].count, 1)

        screen.destroy()
    }

    // ── Required state transitions ─────────────────────────────────
    function test_stateTransitions() {
        var screen = createScreen()
        // empty (default): no banner, Continue enabled
        verify(!screen.loadingIndicator.visible)
        verify(!screen.errorBanner.visible)
        verify(!screen.successBanner.visible)
        verify(!screen.offlineBanner.visible)
        verify(screen.continueButton.enabled)

        // loading: progress shown, Continue disabled
        screen.screenState = "loading"
        verify(screen.loadingIndicator.visible)
        verify(!screen.errorBanner.visible)
        verify(!screen.continueButton.enabled)

        // error: error banner + Retry, Continue disabled
        screen.screenState = "error"
        verify(screen.errorBanner.visible)
        verify(!screen.loadingIndicator.visible)
        verify(!screen.continueButton.enabled)

        // success: success banner, Continue enabled
        screen.screenState = "success"
        verify(screen.successBanner.visible)
        verify(!screen.errorBanner.visible)
        verify(screen.continueButton.enabled)

        // offline: informational banner, Continue enabled
        screen.screenState = "offline"
        verify(screen.offlineBanner.visible)
        verify(screen.continueButton.enabled)

        // back to empty clears all banners
        screen.screenState = "empty"
        verify(!screen.loadingIndicator.visible)
        verify(!screen.errorBanner.visible)
        verify(!screen.successBanner.visible)
        verify(!screen.offlineBanner.visible)

        screen.destroy()
    }

    // ── State banners must render (not collapse to 0 height) ───────
    // Regression guard for the MOS-INS-003 banner-height bug: the
    // error/success/offline banners must have positive rendered height
    // whenever their state is active (this screen carried the same
    // latent bug — fixed with the proven implicitHeight + padding
    // pattern from KeyboardSelection).
    function test_stateBannersRender() {
        var screen = createScreen()

        screen.screenState = "error"
        verify(screen.errorBanner.visible)
        verify(screen.errorBanner.height > 0,
               "error banner must render with positive height (banner-height bug regression)")

        screen.screenState = "success"
        verify(screen.successBanner.visible)
        verify(screen.successBanner.height > 0,
               "success banner must render with positive height (banner-height bug regression)")

        screen.screenState = "offline"
        verify(screen.offlineBanner.visible)
        verify(screen.offlineBanner.height > 0,
               "offline banner must render with positive height (banner-height bug regression)")

        screen.screenState = "empty"
        screen.destroy()
    }

    // ── Continue must not silently advance while loading/error ─────
    function test_continueBlockedWhileLoading() {
        var screen = createScreen()
        wait(100) // let the hosted window activate so key events reach it
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'continueRequested' }",
            screen, "contSpy")
        spy.target = screen

        // Loading: Continue disabled → no signal from keyboard input
        screen.screenState = "loading"
        verify(!screen.continueButton.enabled)
        screen.continueButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spy.count, 0)

        // Error: Continue disabled → no signal
        screen.screenState = "error"
        verify(!screen.continueButton.enabled)
        screen.continueButton.forceActiveFocus()
        keyClick(Qt.Key_Return)
        compare(spy.count, 0)

        // Empty: Continue enabled → keyboard input advances
        screen.screenState = "empty"
        verify(screen.continueButton.enabled)
        screen.continueButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spy.count, 1)

        screen.destroy()
    }

    // ── Keyboard focus reaches actionable controls ─────────────────
    function test_keyboardFocus() {
        var screen = createScreen()
        wait(100) // let the hosted window activate so Tab reaches the controls
        var hostWindow = _hostWindows[_hostWindows.length - 1]
        // The ListView itself has no Tab stop: Tab lands on its
        // currentItem delegate (objectName "languageItem<index>"),
        // which is the visible focus indicator for the list.
        var controls = ["languageSearch", "languageItem0", "regionItem0",
                        "languageBack", "languageContinue"]
        var found = {}
        for (var i = 0; i < controls.length; ++i)
            found[controls[i]] = false

        // Walk the whole focus chain with Tab (the chain wraps, so 80
        // presses cover every control).
        for (var tab = 0; tab < 80; ++tab) {
            keyClick(Qt.Key_Tab)
            var focusItem = hostWindow.activeFocusItem
            if (focusItem && focusItem.objectName)
                found[focusItem.objectName] = true
        }

        for (var c = 0; c < controls.length; ++c)
            verify(found[controls[c]], "focus must reach " + controls[c])

        screen.destroy()
    }

    // ── Arrow keys move the list; Enter/Space select ───────────────
    function test_listKeyboardSelection() {
        var screen = createScreen()
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'languageChangeRequested' }",
            screen, "listSpy")
        spy.target = screen

        screen.languageList.forceActiveFocus()
        verify(screen.languageList.activeFocus)
        // Move from English (0) to Deutsch (1) with Down, then select
        keyClick(Qt.Key_Down)
        compare(screen.languageList.currentIndex, 1)
        keyClick(Qt.Key_Return)
        compare(screen.currentLanguage, "Deutsch")
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "de_DE")

        // Space also selects
        keyClick(Qt.Key_Down)
        keyClick(Qt.Key_Space)
        compare(screen.currentLanguage, "Français")

        screen.destroy()
    }

    // ── Responsive reflow (docs/design/14_RESPONSIVE_RULES.md) ────
    function test_responsiveLayout() {
        // Wide (≥760): help panel visible, wide layout active
        var wide = createScreenAt(1024, 768)
        verify(wide.wideLayout)
        verify(!wide.compactLayout)
        verify(wide.helpPanel.visible)
        wide.destroy()

        // Compact (<640): help panel collapses, compact layout active
        var compact = createScreenAt(480, 768)
        verify(!compact.wideLayout)
        verify(compact.compactLayout)
        verify(!compact.helpPanel.visible)
        compact.destroy()
    }

    // ── Escape clears the search field ─────────────────────────────
    function test_escapeClearsSearch() {
        var screen = createScreen()
        wait(100)
        screen.searchField.forceActiveFocus()
        screen.searchText = "Deutsch"
        compare(screen.searchText, "Deutsch")
        keyClick(Qt.Key_Escape)
        compare(screen.searchText, "")
        screen.destroy()
    }

    // ── MissionPage / MissionWindow integration ────────────────────
    function test_missionPageIntegration() {
        var page = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionPage { pageTitle: 'Installer'; LanguageSelection { objectName: 'langInPage' } }",
            root, "langInPage")
        verify(page !== null)
        verify(page.data.length > 0)
        page.destroy()
    }

    function test_missionWindowIntegration() {
        var screen = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionWindow { width: 1024; height: 768; LanguageSelection { objectName: 'langInWindow' } }",
            root, "langInWindow")
        verify(screen !== null)
        verify(screen.width > 0)
        screen.destroy()
    }

    // ── Reduced motion does not break rendering ────────────────────
    function test_reducedMotion() {
        var screen = createScreen()
        screen.reducedMotion = true
        screen.screenState = "loading"
        verify(screen.loadingIndicator.visible)
        verify(!screen.continueButton.enabled)
        screen.screenState = "empty"
        verify(screen.continueButton.enabled)
        screen.reducedMotion = false
        screen.destroy()
    }

    // Reset theme mode and destroy hosted test windows after each test
    // so tests never leak state or stray windows.
    function cleanup() {
        for (var i = 0; i < _hostWindows.length; ++i)
            _hostWindows[i].destroy()
        _hostWindows = []
        MissionTheme.darkMode = false
    }
}
