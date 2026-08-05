// Mission OS — Installer Encryption (MOS-INS-009) QtTest suite
//
// Runtime validation of the Encryption screen. Follows the
// foundation smoke-test pattern (tests/tst_smoke.qml) and the
// MOS-INS-001 InstallerWelcome, MOS-INS-002 Language, MOS-INS-003
// Keyboard, MOS-INS-004 Network, MOS-INS-005 Privacy, MOS-INS-006 Disk,
// MOS-INS-007 Partition and MOS-INS-008 User Account suites
// (tests/tst_installer_welcome.qml … tst_user_account.qml) per
// docs/engineering/TESTING_STRATEGY.md (QML → Qt Test / qmltestrunner).
//
// Coverage (only behaviors required by the authoritative sources —
// reference § "Encryption", registry MOS-INS-009):
//   - screen loads without QML errors (token singletons resolve)
//   - default state: "No encryption" preselected (opt-in), Continue
//     enabled (valid preselected choice), Back enabled (step 9 > 1)
//   - no spurious action or host-change signals on load
//   - the five supported options exactly as listed in the reference
//     (No encryption, Full Disk Encryption, Separate encrypted data
//     partition, TPM-assisted unlock (supported hardware), Recovery
//     key generation); every option carries benefits, performance
//     impact, and recovery implications explanations
//   - selecting an option fires encryptionChangeRequested exactly once
//     per user action, carrying the option code
//   - out-of-range selection requests are ignored (no signal)
//   - required signals fire from the right controls (continue/back/retry)
//   - required state transitions (empty/loading/error/success/offline)
//   - Continue is blocked while loading/error (validation-before-continue)
//   - state banners render with positive height (banner-height regression)
//   - keyboard navigation: list focus, Up/Down, Enter/Space selection
//   - keyboard focus reaches all list rows, Back and Continue
//   - Escape navigates back
//   - responsive compact layout (help panel collapses)
//   - reduced motion does not break rendering
//   - MissionPage / MissionWindow integration introduces no runtime errors
//
// Run via qmltestrunner (see CMakeLists.txt CTest registration):
//   qmltestrunner -import <build>/src/libraries/ui/qml \
//                 -input src/libraries/ui/tests/tst_encryption.qml
//
// Exit code: 0 = all checks passed; non-zero = failure (CI gate).

import QtQuick
import QtTest
import org.mission.ui 1.0

TestCase {
    id: root
    name: "Encryption"

    // ── Helpers ────────────────────────────────────────────────────
    // Same hosted-window pattern as the other suites: items hosted
    // directly under the TestCase report visible=false on this Qt build,
    // so every screen under test lives in an explicit visible Window;
    // cleanup() destroys the host windows afterwards.
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
                     "    Encryption { id: screen; width: " + width + "; height: " + height + "; " +
                     (extra || "") + " }\n" +
                     "}"
        var host = Qt.createQmlObject(source, root, "encHost")
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
        verify(screen.continueButton.text.length > 0)
        // Step context: Encryption is installer step 9 of 12
        compare(screen.step, 9)
        compare(screen.totalSteps, 17)
        // All five supported options exist (reference § "Encryption")
        compare(screen.encryptionCount, 5)
        // Defaults: "No encryption" preselected (opt-in, listed first),
        // Continue enabled (valid choice), Back enabled (step > 1).
        compare(screen.selectedEncryptionIndex, 0)
        compare(screen.currentEncryptionCode, "none")
        compare(screen.currentEncryptionLabel, "No encryption")
        verify(screen.selectedEncryption !== null)
        compare(screen.selectedEncryption.code, "none")
        verify(screen.continueButton.enabled)
        verify(screen.backButton.enabled)
        screen.destroy()
    }

    // ── Defaults must not emit spurious signals ────────────────────
    // Regression guard: no action signal and no host-change signal may
    // fire on load (same contract as 002–008; rule: initial/default
    // values never emit host-change signals).
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
                     "    property alias spyE: spyE\n" +
                     "    Encryption { id: screen; width: 1024; height: 768\n" +
                     "        SignalSpy { id: spyC; signalName: 'continueRequested'; target: screen }\n" +
                     "        SignalSpy { id: spyB; signalName: 'backRequested'; target: screen }\n" +
                     "        SignalSpy { id: spyR; signalName: 'retryRequested'; target: screen }\n" +
                     "        SignalSpy { id: spyE; signalName: 'encryptionChangeRequested'; target: screen }\n" +
                     "    }\n" +
                     "}\n"
        var host = Qt.createQmlObject(source, root, "encLoadHost")
        _hostWindows.push(host)
        compare(host.spyC.count, 0)
        compare(host.spyB.count, 0)
        compare(host.spyR.count, 0)
        compare(host.spyE.count, 0)
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

    // ── The five supported options match the reference exactly ─────
    // Reference § "Encryption": "Supported options include: No
    // encryption, Full Disk Encryption, Separate encrypted data
    // partition, TPM-assisted unlock (supported hardware), Recovery key
    // generation." No option may be invented or omitted.
    function test_encryptionOptionsMatchReference() {
        var screen = createScreen()
        compare(screen.encryptionOptions.length, 5)
        compare(screen.encryptionOptions[0].code, "none")
        compare(screen.encryptionOptions[0].label, "No encryption")
        compare(screen.encryptionOptions[1].code, "fde")
        compare(screen.encryptionOptions[1].label, "Full Disk Encryption")
        compare(screen.encryptionOptions[2].code, "data")
        compare(screen.encryptionOptions[2].label, "Separate encrypted data partition")
        compare(screen.encryptionOptions[3].code, "tpm")
        compare(screen.encryptionOptions[3].label, "TPM-assisted unlock (supported hardware)")
        compare(screen.encryptionOptions[4].code, "recovery")
        compare(screen.encryptionOptions[4].label, "Recovery key generation")
        screen.destroy()
    }

    // ── Every option explains benefits, performance, recovery ──────
    // Reference § "Encryption": "Users receive clear explanations of:
    // benefits, performance impact, recovery implications."
    function test_optionExplanationsPresent() {
        var screen = createScreen()
        for (var i = 0; i < screen.encryptionOptions.length; ++i) {
            var option = screen.encryptionOptions[i]
            verify(option.benefits.length > 0,
                   "option " + option.code + " must explain benefits")
            verify(option.performance.length > 0,
                   "option " + option.code + " must explain performance impact")
            verify(option.recovery.length > 0,
                   "option " + option.code + " must explain recovery implications")
            // Explanations must be substantive, not placeholder copy
            verify(option.benefits !== option.performance,
                   "benefits and performance copy must differ")
            verify(option.performance !== option.recovery,
                   "performance and recovery copy must differ")
        }
        // All five rows are present in the list model
        verify(screen.encryptionList.count === 5)
        screen.destroy()
    }

    // ── Selecting an option fires the host-change signal exactly ───
    // User action → encryptionChangeRequested(code) exactly once per
    // action, carrying the option code ("none" | "fde" | "data" |
    // "tpm" | "recovery").
    function test_selectionEmitsChange() {
        var screen = createScreen()
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'encryptionChangeRequested' }",
            screen, "encSelectSpy")
        spy.target = screen

        // Select "Separate encrypted data partition" (index 2)
        screen.selectEncryption(2)
        compare(screen.selectedEncryptionIndex, 2)
        compare(screen.currentEncryptionCode, "data")
        compare(screen.currentEncryptionLabel, "Separate encrypted data partition")
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "data")

        // Select "Full Disk Encryption" (index 1)
        screen.selectEncryption(1)
        compare(screen.selectedEncryptionIndex, 1)
        compare(screen.currentEncryptionCode, "fde")
        compare(spy.count, 2)
        compare(spy.signalArguments[1][0], "fde")

        // Live selection caption reflects the current choice
        verify(screen.selectionCaption.visible)
        verify(screen.selectionCaption.text.indexOf("Full Disk Encryption") >= 0)
        verify(screen.selectionCaption.text.indexOf("fde") >= 0)

        screen.destroy()
    }

    // ── Out-of-range selection requests are ignored ────────────────
    function test_outOfRangeSelectionIgnored() {
        var screen = createScreen()
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'encryptionChangeRequested' }",
            screen, "encRangeSpy")
        spy.target = screen

        screen.selectEncryption(-1)
        screen.selectEncryption(99)
        compare(spy.count, 0)
        compare(screen.selectedEncryptionIndex, 0)
        compare(screen.currentEncryptionCode, "none")

        screen.destroy()
    }

    // ── Keyboard: list focus, Up/Down, Enter/Space selection ───────
    function test_keyboardSelection() {
        var screen = createScreen()
        wait(100) // let the hosted window activate so key events reach it
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'encryptionChangeRequested' }",
            screen, "encKbdSpy")
        spy.target = screen

        // Warm up the hosted window (first key event is consumed by
        // window activation on this build — same pattern as 001–008).
        keyClick(Qt.Key_Tab)

        // Give the list focus; Down moves the current row
        screen.encryptionList.forceActiveFocus()
        verify(screen.encryptionList.activeFocus)
        keyClick(Qt.Key_Down)
        compare(screen.encryptionList.currentIndex, 1)

        // Return confirms the focused row (real keyboard interaction)
        keyClick(Qt.Key_Return)
        compare(screen.selectedEncryptionIndex, 1)
        compare(screen.currentEncryptionCode, "fde")
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], "fde")

        // Down again, Space confirms the next row
        keyClick(Qt.Key_Down)
        compare(screen.encryptionList.currentIndex, 2)
        keyClick(Qt.Key_Space)
        compare(screen.selectedEncryptionIndex, 2)
        compare(screen.currentEncryptionCode, "data")
        compare(spy.count, 2)
        compare(spy.signalArguments[1][0], "data")

        // Up moves back and Return re-confirms
        keyClick(Qt.Key_Up)
        compare(screen.encryptionList.currentIndex, 1)
        keyClick(Qt.Key_Return)
        compare(screen.currentEncryptionCode, "fde")
        compare(spy.count, 3)

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
                spyNames[i] + "' }", screen, "encSpy" + i)
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
        // empty (default): no banner, Continue enabled (valid choice)
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
    // Regression guard for the banner-height bug class found in
    // MOS-INS-001/002/003: the error/success/offline banners must have
    // positive rendered height whenever their state is active.
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
            screen, "encContSpy")
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

        // Empty: valid preselected choice → Continue enabled → keyboard advances
        screen.screenState = "empty"
        verify(screen.continueButton.enabled)
        screen.continueButton.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(spy.count, 1)

        screen.destroy()
    }

    // ── Keyboard focus reaches all actionable controls ─────────────
    // The list (activeFocusOnTab) and Back/Continue must be reachable
    // through the Tab focus chain. Within a list, only the current row
    // is a Tab stop at a time; every row is keyboard-reachable because
    // Down/Up navigation moves focus onto that row's delegate (the
    // activeFocusItem then carries the row's objectName — verified by
    // the runtime probe on this Qt build).
    function test_keyboardFocus() {
        var screen = createScreen()
        wait(100) // let the hosted window activate so Tab reaches the controls
        var hostWindow = _hostWindows[_hostWindows.length - 1]
        var found = {}

        // Walk the whole focus chain with Tab (the chain wraps, so 100
        // presses cover every control).
        for (var tab = 0; tab < 100; ++tab) {
            keyClick(Qt.Key_Tab)
            var focusItem = hostWindow.activeFocusItem
            if (focusItem && focusItem.objectName)
                found[focusItem.objectName] = true
        }

        // The list is a single Tab stop: the current row's delegate is
        // the focused item while the list holds focus.
        verify(found["encryptionItem0"], "focus must reach the current encryption row")
        verify(found["encryptionBack"], "focus must reach encryptionBack")
        verify(found["encryptionContinue"], "focus must reach encryptionContinue")

        // Every list row is keyboard-reachable: Down moves focus onto
        // each row's delegate in turn (the activeFocusItem carries the
        // row's objectName).
        screen.encryptionList.forceActiveFocus()
        for (var row = 1; row < 5; ++row) {
            keyClick(Qt.Key_Down)
            compare(screen.encryptionList.currentIndex, row)
            verify(hostWindow.activeFocusItem.objectName === "encryptionItem" + row,
                   "focus must follow the list to row " + row)
        }

        // Up navigates back through the rows
        keyClick(Qt.Key_Up)
        compare(screen.encryptionList.currentIndex, 3)
        verify(hostWindow.activeFocusItem.objectName === "encryptionItem3",
               "focus must follow the list back to row 3")

        screen.destroy()
    }

    // ── Escape navigates back ──────────────────────────────────────
    function test_escapeNavigatesBack() {
        var screen = createScreen()
        wait(100)
        var spy = Qt.createQmlObject(
            "import QtTest; import org.mission.ui 1.0; SignalSpy { signalName: 'backRequested' }",
            screen, "encEscSpy")
        spy.target = screen

        // Warm up the hosted window (first key event is consumed by
        // window activation on this build). Focus lands on a list row;
        // the list does not consume Escape, so it propagates to the
        // root and navigates back.
        screen.backButton.forceActiveFocus()
        keyClick(Qt.Key_W)
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

    // ── MissionPage / MissionWindow integration ────────────────────
    function test_missionPageIntegration() {
        var page = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionPage { pageTitle: 'Installer'; Encryption { objectName: 'encInPage' } }",
            root, "encInPage")
        verify(page !== null)
        verify(page.data.length > 0)
        page.destroy()
    }

    function test_missionWindowIntegration() {
        var screen = Qt.createQmlObject(
            "import org.mission.ui 1.0; MissionWindow { width: 1024; height: 768; Encryption { objectName: 'encInWindow' } }",
            root, "encInWindow")
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
        // Selection still works with reduced motion
        screen.selectEncryption(4)
        compare(screen.selectedEncryptionIndex, 4)
        compare(screen.currentEncryptionCode, "recovery")
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
