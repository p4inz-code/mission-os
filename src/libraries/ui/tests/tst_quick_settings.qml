// Mission OS — Quick Settings (MOS-DES-004) QtTest suite
//
// Runtime validation of the Quick Settings screen. Follows the
// foundation smoke-test pattern (tests/tst_smoke.qml), the Desktop and
// Workspace Switcher suites (tests/tst_desktop.qml,
// tests/tst_workspace_switcher.qml), the Notifications suite
// (tests/tst_notifications.qml) and docs/engineering/TESTING_STRATEGY.md
// (QML → Qt Test / qmltestrunner).
//
// Coverage:
//   - screen loads without QML errors (token singletons resolve)
//   - MissionTheme works; light/dark rendering bindings re-evaluate
//   - overlay treatment: scrim + top-right panel with a "Quick Settings"
//     heading
//   - toggle tiles render from the host model (label, On/Off state tag)
//     with Accessible names carrying the state (color is never the only
//     indicator)
//   - the tile action step: click, Enter and Space emit tileToggled(id)    //   - Volume / Brightness slider rows render the host levels (value
    //     labels) and user interaction (arrow keys) emits
    //     volumeLevelChanged / brightnessLevelChanged with the new 0-100
    //     level
//   - empty tiles degrade to a neutral hint (defensive)
//   - keyboard navigation: arrows move focus across the 2-column grid
//     (Left/Right ±1, Up/Down ±2, wrapping); the first tile is focused
//     on load (keyboard-first)
//   - accessibility roles (heading; tiles announced as checkable with
//     On/Off in the name; sliders announced with their names)
//   - Escape is deliberately unmapped (no signal fires — the host owns
//     overlay dismissal)
//   - MissionPage / MissionWindow integration introduces no runtime errors
//   - reduced motion does not break rendering
//
// Notes on createScreen(extra): every extra is a single QML property
// assignment (the validated family pattern). Where a test needs several
// properties, they are separated with semicolons — commas are not valid
// between QML property assignments (empirically verified on this
// toolchain).
//
// Run via qmltestrunner (see CMakeLists.txt CTest registration):
//   qmltestrunner -import <build>/src/libraries/ui/qml \
//                 -input src/libraries/ui/tests/tst_quick_settings.qml
//
// Exit code: 0 = all checks passed; non-zero = failure (CI gate).

import QtQuick
import QtTest
import org.mission.ui 1.0

TestCase {
    id: root
    name: "QuickSettings"

    // ── Helpers ────────────────────────────────────────────────────
    // The qmltestrunner harness does not show its own test window, so
    // items hosted directly under the TestCase report visible=false on
    // this Qt build (verified empirically). To validate real
    // visibility and keyboard-focus behavior, every screen under test
    // is hosted inside an explicit visible Window; cleanup() destroys
    // the host windows afterwards.
    property var _hostWindows: []

    function createScreen(extra) {
        var source = "import QtQuick\n" +
                     "import org.mission.ui 1.0\n" +
                     "Window {\n" +
                     "    width: 1280; height: 720; visible: true\n" +
                     "    property alias screen: screen\n" +
                     "    QuickSettings { id: screen; width: 1280; height: 720; " +
                     (extra || "") + " }\n" +
                     "}"
        var host = Qt.createQmlObject(source, root, "qsHost")
        _hostWindows.push(host)
        return host.screen
    }

    // ── Screen loads; tokens resolve; no QML errors ────────────────
    function test_screenLoads() {
        var screen = createScreen()
        verify(screen !== null)
        verify(screen.height > 0)
        // Overlay treatment: scrim + top-right panel + heading
        verify(screen.backdropScrim !== null)
        verify(screen.quickPanel !== null)
        verify(screen.titleLabel.text.length > 0)
        compare(screen.titleLabel.text, "Quick Settings")
        // Continuous controls present by default
        verify(screen.volumeSlider !== null)
        verify(screen.brightnessSlider !== null)
        screen.destroy()
    }

    // ── MissionTheme light/dark rendering bindings ─────────────────
    function test_themeLightAndDark() {
        var screen = createScreen("tiles: [ { id: 'wifi', label: 'Wi-Fi', active: true }, " +
                                  "{ id: 'bluetooth', label: 'Bluetooth', active: false } ]")
        var tile0 = screen.tileRepeater.itemAt(0)
        var tile1 = screen.tileRepeater.itemAt(1)
        // Disable the tiles' Behavior on color (reduced-motion) so theme
        // flips apply instantly instead of animating over Motion.colorChange
        screen.reducedMotion = true

        MissionTheme.darkMode = false
        verify(Qt.colorEqual(screen.backdropScrim.color, Colors.scrim))
        verify(Qt.colorEqual(screen.quickPanel.color, MissionTheme.surface))
        verify(Qt.colorEqual(screen.titleLabel.color, MissionTheme.textPrimary))
        // Active tile: primaryContainer in light; inactive: surfaceDim
        verify(Qt.colorEqual(tile0.color, MissionTheme.primaryContainer))
        verify(Qt.colorEqual(tile1.color, MissionTheme.surfaceDim))

        MissionTheme.darkMode = true
        // Active tile: primary in dark
        verify(Qt.colorEqual(tile0.color, MissionTheme.primary))
        verify(Qt.colorEqual(tile1.color, MissionTheme.surfaceDim))
        verify(Qt.colorEqual(screen.titleLabel.color, MissionTheme.textPrimary))

        MissionTheme.darkMode = false
        screen.destroy()
    }

    // ── Tiles render labels, state tags and Accessible names ───────
    function test_tilesRender() {
        var screen = createScreen("tiles: [ { id: 'wifi', label: 'Wi-Fi', active: true }, " +
                                  "{ id: 'bluetooth', label: 'Bluetooth', active: false }, " +
                                  "{ id: 'night', label: 'Night Light', active: true }, " +
                                  "{ id: 'vpn', label: 'VPN', active: false } ]")
        verify(screen.tileRepeater.count === 4)
        var tile0 = screen.tileRepeater.itemAt(0)
        var tile1 = screen.tileRepeater.itemAt(1)
        verify(tile0 !== null && tile1 !== null)
        verify(tile0.visible)
        verify(tile1.visible)
        // Accessible names carry label + state (color is never the only
        // indicator)
        compare(tile0.Accessible.name, "Wi-Fi, On")
        compare(tile1.Accessible.name, "Bluetooth, Off")
        compare(screen.tileRepeater.itemAt(2).Accessible.name, "Night Light, On")
        compare(screen.tileRepeater.itemAt(3).Accessible.name, "VPN, Off")
        // State helpers
        compare(screen.stateLabel(tile0.modelData), "On")
        compare(screen.stateLabel(tile1.modelData), "Off")
        verify(screen.isActive(tile0.modelData))
        verify(!screen.isActive(tile1.modelData))
        compare(screen.tileCount, 4)
        screen.destroy()
    }

    // ── Label fallback: an entry without a label uses its id ───────
    function test_labelFallback() {
        var screen = createScreen("tiles: [ { id: 'battery-saver', active: false } ]")
        var tile0 = screen.tileRepeater.itemAt(0)
        compare(screen.labelFor(tile0.modelData), "battery-saver")
        compare(tile0.Accessible.name, "battery-saver, Off")
        screen.destroy()
    }

    // ── Toggle: click, Enter and Space emit the tile id ────────────
    function test_tileToggle() {
        var screen = createScreen("tiles: [ { id: 'wifi', label: 'Wi-Fi', active: true }, " +
                                  "{ id: 'bluetooth', label: 'Bluetooth', active: false }, " +
                                  "{ id: 'night', label: 'Night Light', active: false } ]")
        wait(100) // window activation for key delivery
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'tileToggled' }",
            screen, "toggleSpy")
        spy.target = screen

        // Mouse click on the first tile
        var tile0 = screen.tileRepeater.itemAt(0)
        mouseClick(tile0, tile0.width / 2, tile0.height / 2)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "wifi")

        // Enter on the second tile
        var tile1 = screen.tileRepeater.itemAt(1)
        tile1.forceActiveFocus()
        keyClick(Qt.Key_Return)
        compare(spy.count, 2)
        compare(spy.signalArguments[1][0], "bluetooth")

        // Space on the third tile
        var tile2 = screen.tileRepeater.itemAt(2)
        tile2.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spy.count, 3)
        compare(spy.signalArguments[2][0], "night")

        screen.destroy()
    }

    // ── Volume slider: host level renders; arrows emit the level ───
    function test_volumeSlider() {
        var screen = createScreen()
        wait(100) // let bindings settle

        // Host-driven level renders on the slider + value label
        screen.volume = 60
        wait(50)
        verify(screen.volumeSlider.value === 60)
        compare(screen.volumeValueLabel.text, "60%")

        // User interaction (Right arrow on the focused slider) emits
        // volumeLevelChanged with the new level
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'volumeLevelChanged' }",
            screen, "volSpy")
        spy.target = screen
        screen.volumeSlider.forceActiveFocus()
        keyClick(Qt.Key_Right)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], 61)

        screen.destroy()
    }

    // ── Brightness slider: same host-driven contract ───────────────
    function test_brightnessSlider() {
        var screen = createScreen()
        wait(100)

        screen.brightness = 40
        wait(50)
        verify(screen.brightnessSlider.value === 40)
        compare(screen.brightnessValueLabel.text, "40%")

        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'brightnessLevelChanged' }",
            screen, "brightSpy")
        spy.target = screen
        screen.brightnessSlider.forceActiveFocus()
        keyClick(Qt.Key_Right)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], 41)

        screen.destroy()
    }

    // ── Host-absent: volume/brightness are UNKNOWN, not fake values ─
    function test_hostAbsentLevelsNeutral() {
        var screen = createScreen()
        wait(100)
        compare(screen.volume, -1)
        compare(screen.brightness, -1)
        compare(screen.volumeValueLabel.text, "—")
        compare(screen.brightnessValueLabel.text, "—")
        verify(!screen.volumeSlider.enabled, "volume slider must be disabled while level is unknown")
        verify(!screen.brightnessSlider.enabled, "brightness slider must be disabled while level is unknown")
        screen.destroy()
    }

    // ── Empty tiles degrade gracefully ─────────────────────────────
    function test_emptyTiles() {
        var screen = createScreen()
        wait(100)
        verify(screen.tileRepeater.count === 0)
        verify(screen.emptyHint.visible)
        compare(screen.tileCount, 0)
        // Focusing is impossible but must not crash
        screen.focusTile(0)
        screen.destroy()
    }

    // ── Keyboard navigation: arrows move across the 2-column grid ──
    function test_keyboardNavigation() {
        var screen = createScreen("tiles: [ { id: 'a', label: 'A', active: false }, " +
                                  "{ id: 'b', label: 'B', active: false }, " +
                                  "{ id: 'c', label: 'C', active: false }, " +
                                  "{ id: 'd', label: 'D', active: false } ]")
        wait(100) // window activation for key delivery
        var t0 = screen.tileRepeater.itemAt(0)
        var t1 = screen.tileRepeater.itemAt(1)
        var t2 = screen.tileRepeater.itemAt(2)
        var t3 = screen.tileRepeater.itemAt(3)

        // Right moves to the next column; Down steps a full row (2)
        t0.forceActiveFocus()
        verify(t0.activeFocus)
        keyClick(Qt.Key_Right)
        verify(t1.activeFocus, "Right must move focus to the next tile")
        keyClick(Qt.Key_Down)
        verify(t3.activeFocus, "Down must move focus down a row")
        keyClick(Qt.Key_Up)
        verify(t1.activeFocus, "Up must move focus up a row")

        // Left moves back; Left from the first column wraps to the end
        keyClick(Qt.Key_Left)
        verify(t0.activeFocus, "Left must move focus to the previous tile")
        keyClick(Qt.Key_Left)
        verify(t3.activeFocus, "Left must wrap around to the last tile")
        keyClick(Qt.Key_Right)
        verify(t0.activeFocus, "Right must wrap around to the first tile")

        screen.destroy()
    }

    // ── Accessibility roles ────────────────────────────────────────
    function test_accessibleRoles() {
        var screen = createScreen("tiles: [ { id: 'wifi', label: 'Wi-Fi', active: true }, " +
                                  "{ id: 'bluetooth', label: 'Bluetooth', active: false } ]")
        // Heading announced for the panel title
        verify(screen.titleLabel.Accessible.role === Accessible.Heading)
        verify(screen.titleLabel.Accessible.name.length > 0)
        // Tiles announced as checkable with the state in the name
        var tile0 = screen.tileRepeater.itemAt(0)
        verify(tile0.Accessible.role === Accessible.CheckBox)
        verify(tile0.Accessible.checked === true)
        compare(tile0.Accessible.name, "Wi-Fi, On")
        var tile1 = screen.tileRepeater.itemAt(1)
        verify(tile1.Accessible.checked === false)
        // Sliders announced with their names
        verify(screen.volumeSlider.Accessible.name.length > 0)
        verify(screen.brightnessSlider.Accessible.name.length > 0)
        screen.destroy()
    }

    // ── Keyboard focus reaches the tiles ───────────────────────────
    function test_keyboardFocus() {
        var screen = createScreen("tiles: [ { id: 'a', label: 'A', active: false }, " +
                                  "{ id: 'b', label: 'B', active: false } ]")
        wait(100) // let the hosted window activate so Tab reaches the tiles
        var hostWindow = _hostWindows[_hostWindows.length - 1]
        var found = { "qsTile0": false, "qsTile1": false }

        for (var tab = 0; tab < 20; ++tab) {
            keyClick(Qt.Key_Tab)
            var focusItem = hostWindow.activeFocusItem
            if (focusItem && focusItem.objectName)
                found[focusItem.objectName] = true
        }

        verify(found["qsTile0"], "focus must reach the quick settings tiles")
        verify(found["qsTile1"], "focus must reach all quick settings tiles")

        screen.destroy()
    }

    // ── Escape is deliberately unmapped (no signal fires) ──────────
    function test_noEscapeMapping() {
        var screen = createScreen("tiles: [ { id: 'a', label: 'A', active: false } ]")
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'tileToggled' }",
            screen, "escSpy")
        spy.target = screen

        // Escape with a tile focused must not toggle anything
        screen.tileRepeater.itemAt(0).forceActiveFocus()
        keyClick(Qt.Key_Escape)
        compare(spy.count, 0)

        screen.destroy()
    }

    // ── MissionPage / MissionWindow integration ────────────────────
    function test_missionPageIntegration() {
        var page = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionPage { pageTitle: 'Quick Settings'; QuickSettings { objectName: 'qsInPage' } }",
            root, "qsInPage")
        verify(page !== null)
        verify(page.data.length > 0)
        page.destroy()
    }

    function test_missionWindowIntegration() {
        var screen = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionWindow { width: 1280; height: 720; QuickSettings { objectName: 'qsInWindow' } }",
            root, "qsInWindow")
        verify(screen !== null)
        verify(screen.width > 0)
        screen.destroy()
    }

    // ── Reduced motion does not break rendering ────────────────────
    function test_reducedMotion() {
        var screen = createScreen("tiles: [ { id: 'a', label: 'A', active: true }, " +
                                  "{ id: 'b', label: 'B', active: false } ]")
        screen.reducedMotion = true
        verify(screen.tileRepeater.count === 2)
        verify(screen.quickPanel.visible)
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
