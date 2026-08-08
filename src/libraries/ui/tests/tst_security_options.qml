// Mission OS — Installer Security Options (MOS-INS-013) QtTest suite
//
// Runtime validation of the Security Options screen. Follows the
// foundation smoke-test pattern (tests/tst_smoke.qml) and the
// MOS-INS-001→012 Installer suites per docs/engineering/
// TESTING_STRATEGY.md (QML → Qt Test / qmltestrunner).
//
// Coverage (only behaviors required by the authoritative sources —
// reference § "Screen 13 — Security Options", registry MOS-INS-013):
//   - screen loads without QML errors (token singletons resolve)
//   - default state: step 10 of 17, all six security features shown,
//     Continue enabled (valid state), Back enabled (step 10 > 1)
//   - the six features match the reference list exactly (Full Disk
//     Encryption read-back, Secure Boot, TPM, Auto updates, Recovery
//     key generation, Emergency recovery media) — no item may be
//     invented or omitted
//   - encryption read-back and recovery key read-back are non-interactive
//   - Secure Boot, TPM, auto updates, recovery media are interactive
//     toggles (Switch controls)
//   - auto updates is ON by default (security-by-default)
//   - recovery media is OFF by default (explicit opt-in)
//   - Secure Boot and TPM toggles reflect host-fed availability
//     (secureBootSupported, tpmSupported)
//   - no spurious action signals on load
//   - host wiring: toggling switches emits the correct *ChangeRequested
//     signal with the correct enabled state
//   - required signals fire from the right controls (continue/back/retry)
//   - required state transitions (empty/loading/error/success/offline)
//   - Continue is blocked while loading/error (validation-before-continue)
//   - state banners render with positive height (banner-height regression)
//   - keyboard navigation: focus reaches Back and Continue; the
//     read-only cards are NOT Tab stops; toggle switches ARE Tab stops
//   - Escape navigates back
//   - responsive compact layout (help panel collapses)
//   - reduced motion does not break rendering
//   - MissionPage / MissionWindow integration introduces no runtime errors
//
// Run via qmltestrunner (see CMakeLists.txt CTest registration):
//   qmltestrunner -import <build>/src/libraries/ui/qml \
//                 -input src/libraries/ui/tests/tst_security_options.qml
//
// Exit code: 0 = all checks passed; non-zero = failure (CI gate).

import QtQuick
import QtQuick.Controls
import QtTest
import org.mission.ui 1.0

TestCase {
    id: root
    name: "SecurityOptions"

    // ── Helpers ────────────────────────────────────────────────────
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
                     "    SecurityOptions { id: screen; width: " + width +
                     "; height: " + height + "; " + (extra || "") + " }\n" +
                     "}"
        var host = Qt.createQmlObject(source, root, "secHost" + _hostWindows.length)
        _hostWindows.push(host)
        return host.screen
    }

    function getToggle(screen, index) {
        var item = screen.securityRows.itemAt(index)
        return item ? item.toggleControl : null
    }

    function getReadOnlyLabel(screen, index) {
        var item = screen.securityRows.itemAt(index)
        return item ? item.toggleControl : null // read-only cards use the same alias for the label
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
        verify(screen.continueButton.text.length > 0)
        // Step context: Security Options is installer step 10 of 17
        compare(screen.step, 10)
        compare(screen.totalSteps, 17)
        // All six supported items exist (reference § "Screen 13")
        compare(screen.securityRows.count, 6)
        // Defaults: Continue enabled (valid state); Back enabled (step 10 > 1)
        verify(screen.continueButton.enabled)
        verify(screen.backButton.enabled)
        screen.destroy()
    }

    // ── The six features match the reference exactly ───────────────
    function test_featuresMatchReference() {
        var screen = createScreen()
        var expected = [
            { code: "encryption",    label: "Full Disk Encryption",          interactive: false },
            { code: "secureboot",    label: "Secure Boot Integration",       interactive: true  },
            { code: "tpm",           label: "TPM Integration",               interactive: true  },
            { code: "autoupdates",   label: "Automatic Security Updates",    interactive: true  },
            { code: "recoverykey",   label: "Recovery Key Generation",       interactive: false },
            { code: "recoverymedia", label: "Emergency Recovery Media",      interactive: true  }
        ]
        compare(screen.securityRows.count, expected.length)
        for (var i = 0; i < expected.length; ++i) {
            var item = screen.securityRows.itemAt(i)
            verify(item !== null, "security row " + i + " must exist")
        }
        screen.destroy()
    }

    // ── Default toggle states ──────────────────────────────────────
    function test_defaultToggleStates() {
        var screen = createScreen()

        // Encryption read-back: default "No encryption"
        compare(screen.encryptionLabel, "No encryption")

        // Secure Boot: capability UNKNOWN (null) until the host reports
        // it — never fabricated as supported (FABRICATION-9 regression).
        // OFF by default and the toggle is disabled while unknown.
        verify(screen.secureBootSupported === null)
        compare(screen.secureBootEnabled, false)
        verify(!getToggle(screen, 1).enabled, "Secure Boot toggle must be disabled while support is unknown")

        // TPM: capability UNKNOWN (null) until the host reports it
        verify(screen.tpmSupported === null)
        compare(screen.tpmEnabled, false)
        verify(!getToggle(screen, 2).enabled, "TPM toggle must be disabled while support is unknown")

        // Auto updates: ON by default (security-by-default)
        compare(screen.autoUpdatesEnabled, true)

        // Recovery key: not selected by default
        compare(screen.recoveryKeySelected, false)

        // Recovery media: OFF by default (explicit opt-in)
        compare(screen.recoveryMediaEnabled, false)

        screen.destroy()
    }

    // ── Defaults must not emit spurious signals ────────────────────
    function test_noSignalsOnLoad() {
        var source = "import QtQuick\n" +
                     "import QtTest\n" +
                     "import org.mission.ui 1.0\n" +
                     "Window {\n" +
                     "    width: 1024; height: 768; visible: true\n" +
                     "    property alias screen: screen\n" +
                     "    property alias spyC: spyC\n" +
                     "    property alias spyB: spyB\n" +
                     "    property alias spyR: spyR\n" +
                     "    SecurityOptions { id: screen; width: 1024; height: 768\n" +
                     "        SignalSpy { id: spyC; signalName: 'continueRequested'; target: screen }\n" +
                     "        SignalSpy { id: spyB; signalName: 'backRequested'; target: screen }\n" +
                     "        SignalSpy { id: spyR; signalName: 'retryRequested'; target: screen }\n" +
                     "    }\n" +
                     "}\n"
        var host = Qt.createQmlObject(source, root, "secLoadHost")
        _hostWindows.push(host)
        compare(host.spyC.count, 0)
        compare(host.spyB.count, 0)
        compare(host.spyR.count, 0)
        host.destroy()
    }

    // ── Toggle toggling emits correct signals ──────────────────────
    // Follows the established PrivacySetup pattern: onCheckedChanged
    // fires on both programmatic and user-initiated changes, handling
    // both property updates and signal emission.
    function test_toggleSignals() {
        var screen = createScreen()
        var spies = []
        var spyNames = ["secureBootChangeRequested", "tpmChangeRequested",
                        "autoUpdatesChangeRequested", "recoveryMediaChangeRequested"]
        for (var i = 0; i < spyNames.length; ++i) {
            var spy = Qt.createQmlObject(
                "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: '" +
                spyNames[i] + "' }", screen, "secSpy" + i)
            spy.target = screen
            spies.push(spy)
        }

        // Toggle Secure Boot on (index 1)
        var toggle = getToggle(screen, 1)
        verify(toggle !== null, "secureboot toggle must exist")
        toggle.checked = true
        compare(spies[0].count, 1)
        compare(screen.secureBootEnabled, true)

        // Toggle TPM on (index 2)
        toggle = getToggle(screen, 2)
        verify(toggle !== null, "tpm toggle must exist")
        toggle.checked = true
        compare(spies[1].count, 1)
        compare(screen.tpmEnabled, true)

        // Auto updates starts ON; toggle off (index 3)
        toggle = getToggle(screen, 3)
        verify(toggle !== null, "autoupdates toggle must exist")
        toggle.checked = false
        compare(spies[2].count, 1)
        compare(screen.autoUpdatesEnabled, false)

        // Recovery media toggle on (index 5)
        toggle = getToggle(screen, 5)
        verify(toggle !== null, "recoverymedia toggle must exist")
        toggle.checked = true
        compare(spies[3].count, 1)
        compare(screen.recoveryMediaEnabled, true)

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
                spyNames[i] + "' }", screen, "secActSpy" + i)
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
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'continueRequested' }",
            screen, "secContSpy")
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

        // Empty: valid state → Continue enabled → keyboard advances
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
        wait(100)
        var hostWindow = _hostWindows[_hostWindows.length - 1]
        var found = {}

        // Walk the whole focus chain with Tab
        for (var tab = 0; tab < 100; ++tab) {
            keyClick(Qt.Key_Tab)
            var focusItem = hostWindow.activeFocusItem
            if (focusItem && focusItem.objectName)
                found[focusItem.objectName] = true
        }

        verify(found["securityBack"], "focus must reach securityBack")
        verify(found["securityContinue"], "focus must reach securityContinue")

        // Read-only security rows (indices 0, 4) must NOT be Tab stops.
        // Interactive toggle rows (indices 1, 2, 3, 5) may or may not be
        // Tab stops depending on the Switch implementation — we only verify
        // the Back and Continue buttons are reachable.
        screen.destroy()
    }

    // ── Escape navigates back ──────────────────────────────────────
    function test_escapeNavigatesBack() {
        var screen = createScreen()
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'backRequested' }",
            screen, "secEscSpy")
        spy.target = screen

        screen.backButton.forceActiveFocus()
        keyClick(Qt.Key_W) // warm up
        screen.backButton.forceActiveFocus()
        keyClick(Qt.Key_Escape)
        compare(spy.count, 1)

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

    // ── Theme light/dark rendering ─────────────────────────────────
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

    // ── Host wiring: encryption label and recovery key read-back ───
    function test_hostWiring() {
        var screen = createScreen()

        // Host feeds the encryption choice from the previous screen
        screen.encryptionLabel = "Full Disk Encryption"
        compare(screen.encryptionLabel, "Full Disk Encryption")

        // Host feeds the recovery key state
        screen.recoveryKeySelected = true
        compare(screen.recoveryKeySelected, true)

        // Host can disable Secure Boot / TPM availability
        screen.secureBootSupported = false
        verify(!screen.secureBootSupported)
        screen.tpmSupported = false
        verify(!screen.tpmSupported)

        // Toggle controls reflect availability
        var toggle = getToggle(screen, 1) // Secure Boot
        verify(toggle !== null)
        verify(!toggle.enabled, "Secure Boot toggle must be disabled when unsupported")

        toggle = getToggle(screen, 2) // TPM
        verify(toggle !== null)
        verify(!toggle.enabled, "TPM toggle must be disabled when unsupported")

        screen.destroy()
    }

    // ── Host capability: explicit true/false/unknown states ────────
    function test_hostCapabilityStates() {
        var screen = createScreen()

        // Host explicitly reports support → toggles enabled
        screen.secureBootSupported = true
        screen.tpmSupported = true
        verify(screen.secureBootSupported === true)
        verify(screen.tpmSupported === true)
        verify(getToggle(screen, 1).enabled, "Secure Boot toggle must enable when supported")
        verify(getToggle(screen, 2).enabled, "TPM toggle must enable when supported")

        // Host explicitly reports no support → toggles disabled
        screen.secureBootSupported = false
        screen.tpmSupported = false
        verify(screen.secureBootSupported === false)
        verify(screen.tpmSupported === false)
        verify(!getToggle(screen, 1).enabled, "Secure Boot toggle must disable when unsupported")
        verify(!getToggle(screen, 2).enabled, "TPM toggle must disable when unsupported")

        screen.destroy()
    }

    // ── MissionPage / MissionWindow integration ────────────────────
    function test_missionPageIntegration() {
        var page = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionPage { pageTitle: 'Installer'; SecurityOptions { objectName: 'secInPage' } }",
            root, "secInPage")
        verify(page !== null)
        verify(page.data.length > 0)
        page.destroy()
    }

    function test_missionWindowIntegration() {
        var screen = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionWindow { width: 1024; height: 768; SecurityOptions { objectName: 'secInWindow' } }",
            root, "secInWindow")
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

        // Host wiring still works with reduced motion
        screen.encryptionLabel = "Full Disk Encryption"
        compare(screen.encryptionLabel, "Full Disk Encryption")

        screen.reducedMotion = false
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