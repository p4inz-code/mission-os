// Mission OS — Installer Encryption (MOS-INS-009)
//
// Ninth screen of the Mission OS installer.
// Implements the source-defined Encryption structure (docs/wireframes/
// 01_INSTALLER.md + docs/design/03_SCREEN_REGISTRY.md MOS-INS-009
// "Encryption" + docs/reference/01_INSTALLER.md § "Encryption"):
//
//   Hosting: place inside MissionWindow (or MissionPage) content and
//   anchor to fill, e.g.  MissionWindow { Encryption { anchors.fill: parent } }
//   The component itself sizes to its implicit 1024x768 like MissionPage.
//
//   Header → Stepper Navigation → Main Content → Help Panel → Bottom actions
//
// Displayed items (per reference § "Encryption"):
//   - Supported options: No encryption, Full Disk Encryption, Separate
//     encrypted data partition, TPM-assisted unlock (supported
//     hardware), Recovery key generation — a single-select list exactly
//     matching the reference's five listed options (the established
//     NetworkSelection/Keyboard list pattern; no option is invented or
//     omitted).
//   - Every option gives clear explanations of benefits, performance
//     impact, and recovery implications (reference § "Encryption").
//     The copy is grounded in docs/engineering/SECURITY_ARCHITECTURE.md
//     §5.1 (LUKS2 / Argon2 for root + home, encrypted swap by default,
//     key slots: passphrase + recovery key + optional TPM) and
//     §4 (TPM-assisted unlock via LUKS2 + tpm2-cryptenroll).
//   - "No encryption" is preselected on load (non-emitting) — the
//     reference lists it first, encryption is opt-in, and the
//     TPM/PIN-vs-passphrase unlock policy is an UNRESOLVED_DECISIONS
//     item, so no encryption mode is silently forced.
//   - Live feedback of the current selection
//   - Back / Continue (wireframe UX rules: linear workflow, back always
//     available, validation before continuing).
//
// Recovery key semantics (per security requirements the installer
// "shall generate cryptographically secure recovery keys"): options
// that enable encryption state that a printable recovery key is
// generated during installation (also covered by the "Recovery"
// explanation on each option). The reference lists "Recovery key
// generation" as one of the five supported options; it is therefore a
// list entry like the others. Selecting it means the installer will
// generate a cryptographically secure recovery key (the host applies
// the real policy when encryptionChangeRequested fires).
//
// States (per wireframe): empty · loading · error · success · offline
// The screen exposes *Requested signals; the host application decides
// what each action does (e.g. configuring LUKS2 via cryptsetup).
//
// Design-system compliance:
//   - Tokens only (Colors, Typography, Spacing, Radii, Motion, MissionTheme)
//   - Light + dark themes via MissionTheme (driven by host)
//   - Keyboard navigation with visible focus states
//   - WCAG AA-oriented contrast, reduced-motion aware
//   - Responsive reflow per docs/design/14_RESPONSIVE_RULES.md

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.mission.ui 1.0

FocusScope {
    id: root

    implicitWidth: 1024
    implicitHeight: 768

    // ── Public API ─────────────────────────────────────────────────
    /// Screen state: "empty" | "loading" | "error" | "success" | "offline"
    property string screenState: "empty"

    /// Current installer step (1-based); Back is only enabled past step 1
    property int step: 9

    /// Total number of installer steps (screen registry: 16)
    property int totalSteps: 17

    /// Reduced motion (accessibility)
    property bool reducedMotion: false

    /// Installer/OS version string shown in the header
    property string version: "0.1.0"

    /// Build channel: Stable | Beta | Nightly
    property string buildType: "Nightly"

    /// Available encryption options. Each entry: { code, label,
    /// benefits, performance, recovery } — the reference's five
    /// supported options, each with a clear explanation of benefits,
    /// performance impact, and recovery implications (reference §
    /// "Encryption"). Static fixture; the host service (cryptsetup /
    /// LUKS2) applies the real choice when encryptionChangeRequested
    /// fires. No encryption is first and the default (opt-in).
    property var encryptionOptions: [
        { code: "none",
          label: "No encryption",
          benefits: "Data is stored unencrypted — no passphrase or recovery key needed.",
          performance: "No encryption overhead.",
          recovery: "Data can be read directly if the device is lost or stolen." },
        { code: "fde",
          label: "Full Disk Encryption",
          benefits: "All data at rest is encrypted with LUKS2 against loss or theft.",
          performance: "Small read/write overhead, usually imperceptible.",
          recovery: "A passphrase and a printable recovery key are generated — keep them safe." },
        { code: "data",
          label: "Separate encrypted data partition",
          benefits: "User data on /home is encrypted; system partitions are not.",
          performance: "Overhead applies only to the encrypted data partition.",
          recovery: "Protected by a passphrase and a printable recovery key." },
        { code: "tpm",
          label: "TPM-assisted unlock (supported hardware)",
          benefits: "Encryption that unlocks automatically on TPM hardware (tpm2-cryptenroll).",
          performance: "Fast automatic unlock; requires supported hardware.",
          recovery: "A recovery key remains as a fallback if the TPM cannot unlock." },
        { code: "recovery",
          label: "Recovery key generation",
          benefits: "Generates a cryptographically secure, printable recovery key.",
          performance: "No day-to-day impact; the key lives in a dedicated slot.",
          recovery: "Without the recovery key or passphrase, encrypted data cannot be recovered." }
    ]

    /// Index of the selected encryption option within `encryptionOptions`
    property int selectedEncryptionIndex: 0

    /// The selected option object (from `encryptionOptions`)
    property var selectedEncryption: root.encryptionOptions.length > 0 ? root.encryptionOptions[0] : null

    /// Currently selected option label. Preselected to "No encryption"
    /// so the screen loads with a valid choice (no signal is emitted on
    /// load — the host already knows the default).
    property string currentEncryptionLabel: root.encryptionOptions.length > 0 ? root.encryptionOptions[0].label : ""

    /// Currently selected option code (e.g. "none", "fde", "tpm")
    property string currentEncryptionCode: root.encryptionOptions.length > 0 ? root.encryptionOptions[0].code : ""

    /// Number of encryption options (all are shown)
    property int encryptionCount: root.encryptionOptions.length

    // ── Signals (host wiring) ──────────────────────────────────────
    /// User requested to continue to the next step
    signal continueRequested()
    /// User requested to go back to the previous step
    signal backRequested()
    /// User selected an encryption option (code, e.g. "none", "fde",
    /// "data", "tpm", "recovery"). Never emitted on load — "No
    /// encryption" is preselected during initialization only.
    signal encryptionChangeRequested(string code)
    /// User requested to retry after an error
    signal retryRequested()

    // ── Escape navigates back (Master UX: Back always available) ──
    // No child on this screen consumes Escape (the list handles
    // Up/Down/Enter/Space), so root Escape always → backRequested.
    Keys.onEscapePressed: root.backRequested()

    // ── Responsive helpers ─────────────────────────────────────────
    readonly property bool wideLayout: root.width >= 760
    readonly property bool compactLayout: root.width < 640

    /// Height of a four-line encryption row (label + benefits +
    /// performance + recovery). Named once so the ListView height
    /// formula and the delegate height can never drift apart (no
    /// single token fits four text lines — same pattern as the Disk
    /// Selection row height).
    readonly property int encryptionRowHeight: 124

    // ── Selection helper ───────────────────────────────────────────
    /// Select the encryption option at `index` (host wiring / tests).
    /// Emits encryptionChangeRequested exactly once with the option code.
    function selectEncryption(index) {
        if (index < 0 || index >= root.encryptionOptions.length)
            return
        var option = root.encryptionOptions[index]
        root.selectedEncryptionIndex = index
        root.selectedEncryption = option
        root.currentEncryptionLabel = option.label
        root.currentEncryptionCode = option.code
        root.encryptionChangeRequested(root.currentEncryptionCode)
    }

    // ── Test hooks (used by tests/tst_encryption.qml) ──────────────
    property alias backgroundColor: backgroundRect.color
    property alias headingColor: headingLabel.color
    property alias headingLabel: headingLabel
    property alias encryptionList: encryptionList
    property alias selectionCaption: selectionCaption
    property alias helpPanel: helpPanel
    property alias backButton: backButton
    property alias continueButton: continueButton
    property alias retryButton: retryButton
    property alias errorBanner: errorBanner
    property alias successBanner: successBanner
    property alias offlineBanner: offlineBanner
    property alias loadingIndicator: loadingIndicator

    // ── Background ─────────────────────────────────────────────────
    Rectangle {
        id: backgroundRect
        anchors.fill: parent
        color: MissionTheme.background
    }

    // ══════════════════════════════════════════════════════════════
    // Header
    // ══════════════════════════════════════════════════════════════
    Rectangle {
        id: header
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        height: Spacing.headerHeight
        color: MissionTheme.surface
        z: 2

        // Bottom hairline
        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }
            height: 1
            color: MissionTheme.outline
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Spacing.paddingPage
            anchors.rightMargin: Spacing.paddingPage
            spacing: Spacing.gapMedium

            // Logo mark (simple geometric mark; icon set not yet shipped)
            Rectangle {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                Layout.alignment: Qt.AlignVCenter
                radius: Radii.radiusMd
                color: MissionTheme.primary
                Rectangle {
                    anchors.centerIn: parent
                    width: 14
                    height: 14
                    radius: 7
                    color: "transparent"
                    border.width: 2
                    border.color: MissionTheme.contentOnPrimary
                }
                Accessible.role: Accessible.Graphic
                Accessible.name: qsTr("Mission OS logo")
            }

            // Wordmark + version/build type
            Column {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 0
                Label {
                    text: "Mission OS"
                    font.pixelSize: Typography.title.size
                    font.weight: Typography.title.weight
                    color: MissionTheme.textPrimary
                    elide: Text.ElideRight
                }
                Label {
                    text: qsTr("Version %1 · %2").arg(root.version).arg(root.buildType)
                    font.pixelSize: Typography.caption.size
                    color: MissionTheme.textSecondary
                    visible: !root.compactLayout
                }
            }
        }
    }

    // ══════════════════════════════════════════════════════════════
    // Stepper / navigation context
    // ══════════════════════════════════════════════════════════════
    Item {
        id: stepperBar
        anchors {
            left: parent.left
            right: parent.right
            top: header.bottom
        }
        height: Spacing.toolbarHeight

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Spacing.paddingPage
            anchors.rightMargin: Spacing.paddingPage
            spacing: Spacing.gapMedium

            Label {
                text: qsTr("Step %1 of %2 · Encryption").arg(root.step).arg(root.totalSteps)
                font.pixelSize: Typography.bodySmall.size
                font.weight: Typography.weightSemibold
                color: MissionTheme.textSecondary
                elide: Text.ElideRight
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }

            Item { Layout.fillWidth: true }

            // Step segments
            Row {
                spacing: Spacing.gapTiny
                Accessible.role: Accessible.Grouping
                Accessible.name: qsTr("Installation steps: %1 of %2").arg(root.step).arg(root.totalSteps)
                Repeater {
                    model: root.totalSteps
                    delegate: Rectangle {
                        property bool isCurrent: index === root.step - 1
                        property bool isDone: index < root.step - 1
                        width: (root.compactLayout || !root.wideLayout) ? 8 : 20
                        height: 4
                        radius: 2
                        color: isDone ? MissionTheme.success
                             : isCurrent ? MissionTheme.primary
                             : MissionTheme.outlineVariant
                    }
                }
            }
        }
    }

    // ══════════════════════════════════════════════════════════════
    // Main content + help panel
    // ══════════════════════════════════════════════════════════════
    Item {
        anchors {
            left: parent.left
            right: parent.right
            top: stepperBar.bottom
            bottom: actionBar.top
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Spacing.paddingPage
            anchors.rightMargin: Spacing.paddingPage
            anchors.topMargin: Spacing.gapLarge
            anchors.bottomMargin: Spacing.gapLarge
            spacing: Spacing.gapLarge

            // ── Main content (scrollable) ──
            Flickable {
                id: contentFlickable
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentHeight: contentColumn.height
                ScrollIndicator.vertical: ScrollIndicator {}

                Column {
                    id: contentColumn
                    width: contentFlickable.width
                    spacing: Spacing.gapMedium

                    // ── State area (per installer wireframe states) ──
                    // Loading (non-blocking progress)
                    RowLayout {
                        id: loadingIndicator
                        visible: root.screenState === "loading"
                        width: parent.width
                        spacing: Spacing.gapMedium
                        Label {
                            text: qsTr("Preparing encryption options…")
                            font.pixelSize: Typography.bodySmall.size
                            color: MissionTheme.textSecondary
                        }
                        Rectangle {
                            id: loadingTrack
                            Layout.fillWidth: true
                            Layout.preferredHeight: 4
                            radius: 2
                            color: MissionTheme.surfaceDim
                            Rectangle {
                                id: loadingFill
                                width: 96
                                height: 4
                                radius: 2
                                color: MissionTheme.primary
                                x: -96
                                NumberAnimation on x {
                                    running: root.screenState === "loading" && !root.reducedMotion
                                    from: -96
                                    to: loadingTrack.width
                                    duration: Motion.durationSlow
                                    loops: Animation.Infinite
                                }
                            }
                        }
                    }

                    // Error (title + explanation + recovery action)
                    Rectangle {
                        id: errorBanner
                        visible: root.screenState === "error"
                        width: parent.width
                        // The inner RowLayout uses anchors (not layout
                        // sizing), so give the banner an explicit height
                        // from its content — otherwise the Rectangle has
                        // implicit height 0 and the state banner is
                        // invisible even when `visible` is true (the
                        // proven fix from MOS-INS-001 onward).
                        height: errorLayout.implicitHeight + Spacing.paddingMedium * 2
                        radius: Radii.card
                        color: Colors.errorContainer

                        RowLayout {
                            id: errorLayout
                            anchors.fill: parent
                            anchors.margins: Spacing.paddingMedium
                            spacing: Spacing.gapMedium

                            Rectangle {
                                Layout.preferredWidth: 12
                                Layout.preferredHeight: 12
                                radius: 6
                                color: MissionTheme.error
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Spacing.gapTiny
                                Label {
                                    text: qsTr("Encryption options could not be loaded")
                                    font.weight: Typography.weightSemibold
                                    color: Colors.contentOnErrorContainer
                                }
                                Label {
                                    text: qsTr("The encryption settings could not be verified. Check the installation media and try again.")
                                    font.pixelSize: Typography.bodySmall.size
                                    color: Colors.contentOnErrorContainer
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                            MissionButton {
                                id: retryButton
                                objectName: "encryptionRetry"
                                variant: MissionButton.Variant.Secondary
                                text: qsTr("Retry")
                                onClicked: root.retryRequested()
                            }
                        }
                    }

                    // Success
                    Rectangle {
                        id: successBanner
                        visible: root.screenState === "success"
                        width: parent.width
                        height: successLayout.implicitHeight + Spacing.paddingMedium * 2
                        radius: Radii.card
                        color: Colors.successContainer

                        RowLayout {
                            id: successLayout
                            anchors.fill: parent
                            anchors.margins: Spacing.paddingMedium
                            spacing: Spacing.gapMedium
                            Rectangle {
                                Layout.preferredWidth: 12
                                Layout.preferredHeight: 12
                                radius: 6
                                color: MissionTheme.success
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Spacing.gapTiny
                                Label {
                                    text: qsTr("Encryption setting saved")
                                    font.weight: Typography.weightSemibold
                                    color: Colors.contentOnSuccessContainer
                                }
                                Label {
                                    text: qsTr("Your encryption choice will be applied during installation.")
                                    font.pixelSize: Typography.bodySmall.size
                                    color: Colors.contentOnSuccessContainer
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }

                    // Offline (informational — no online service required for this step)
                    Rectangle {
                        id: offlineBanner
                        visible: root.screenState === "offline"
                        width: parent.width
                        height: offlineLayout.implicitHeight + Spacing.paddingMedium * 2
                        radius: Radii.card
                        color: MissionTheme.surfaceVariant

                        RowLayout {
                            id: offlineLayout
                            anchors.fill: parent
                            anchors.margins: Spacing.paddingMedium
                            spacing: Spacing.gapMedium
                            Rectangle {
                                Layout.preferredWidth: 12
                                Layout.preferredHeight: 12
                                radius: 6
                                color: MissionTheme.textSecondary
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Spacing.gapTiny
                                Label {
                                    text: qsTr("You're offline")
                                    font.weight: Typography.weightSemibold
                                    color: MissionTheme.textPrimary
                                }
                                Label {
                                    text: qsTr("This step works without an internet connection. Encryption is configured locally on this device.")
                                    font.pixelSize: Typography.bodySmall.size
                                    color: MissionTheme.textSecondary
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }

                    // ── Heading ──
                    Label {
                        id: headingLabel
                        text: qsTr("Encryption")
                        width: parent.width
                        font.pixelSize: Typography.headline.size
                        font.weight: Typography.headline.weight
                        color: MissionTheme.textPrimary
                        wrapMode: Text.Wrap
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    Label {
                        text: qsTr("Encryption protects your data if your device is lost or stolen. No encryption is selected by default — choose how Mission OS protects storage at rest. Every option explains its benefits, performance impact, and recovery implications.")
                        width: parent.width
                        font.pixelSize: Typography.bodyLarge.size
                        color: MissionTheme.textSecondary
                        wrapMode: Text.Wrap
                        lineHeight: Typography.lineHeightRelaxed
                    }

                    // ── Encryption options (no search — not specified
                    //    for this screen) ──
                    Label {
                        text: qsTr("Encryption options")
                        width: parent.width
                        font.pixelSize: Typography.subtitle.size
                        font.weight: Typography.subtitle.weight
                        color: MissionTheme.textPrimary
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    ListView {
                        id: encryptionList
                        objectName: "encryptionList"
                        width: parent.width
                        // All rows visible by default; capped so the list
                        // never dominates short windows (scrolls inside).
                        height: Math.min(root.encryptionOptions.length * root.encryptionRowHeight
                                         + (root.encryptionOptions.length - 1) * Spacing.gapTiny,
                                         396)
                        clip: true
                        model: root.encryptionOptions
                        spacing: Spacing.gapTiny
                        activeFocusOnTab: true
                        keyNavigationWraps: true
                        highlightFollowsCurrentItem: true
                        ScrollIndicator.vertical: ScrollIndicator {}
                        onCountChanged: {
                            if (encryptionList.count > 0 && encryptionList.currentIndex < 0)
                                encryptionList.currentIndex = 0
                        }
                        Keys.onReturnPressed: root.selectEncryption(encryptionList.currentIndex)
                        Keys.onSpacePressed: root.selectEncryption(encryptionList.currentIndex)
                        Accessible.role: Accessible.List
                        Accessible.name: qsTr("Encryption options")

                        delegate: Rectangle {
                            id: encryptionDelegate
                            required property var modelData
                            required property int index

                            // When the list is reached via Tab, focus lands on
                            // the currentItem delegate — not on the ListView
                            // itself — so the delegate carries the objectName
                            // used by the keyboard-focus test.
                            objectName: "encryptionItem" + index
                            width: encryptionList.width
                            height: root.encryptionRowHeight
                            radius: Radii.input
                            color: {
                                if (root.selectedEncryptionIndex === index)
                                    return MissionTheme.darkMode ? MissionTheme.primary
                                                                 : MissionTheme.primaryContainer
                                if (encryptionList.currentIndex === index && encryptionList.activeFocus)
                                    return MissionTheme.surfaceVariant
                                if (encryptionDelegateMouse.containsMouse)
                                    return MissionTheme.surfaceVariant
                                return "transparent"
                            }

                            Behavior on color {
                                enabled: !root.reducedMotion
                                // Ubuntu Qt 6.10 toolchain: Behavior `duration`
                                // convenience property is rejected; use the
                                // equivalent `animation:` group property.
                                animation: ColorAnimation { duration: Motion.colorChange }
                            }

                            // Visible focus ring (keyboard navigation)
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: -2
                                radius: Radii.input + 2
                                color: "transparent"
                                border.color: MissionTheme.focusRing
                                border.width: 2
                                visible: encryptionList.currentIndex === index &&
                                         encryptionList.activeFocus
                            }

                            // Option title + code on the first line, then
                            // the required benefits / performance /
                            // recovery explanations (reference §
                            // "Encryption": clear explanations of
                            // benefits, performance impact, and recovery
                            // implications).
                            Column {
                                x: Spacing.paddingMedium
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - Spacing.paddingMedium * 2
                                spacing: Spacing.gapTiny

                                RowLayout {
                                    width: parent.width
                                    spacing: Spacing.gapMedium

                                    Label {
                                        text: modelData.label
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        font.pixelSize: Typography.body.size
                                        font.weight: Typography.weightSemibold
                                        color: root.selectedEncryptionIndex === index
                                             ? (MissionTheme.darkMode ? MissionTheme.contentOnPrimary
                                                                      : MissionTheme.contentOnPrimaryContainer)
                                             : MissionTheme.textPrimary
                                    }

                                    Label {
                                        text: modelData.code
                                        font.family: Typography.fontFamilyMono
                                        font.pixelSize: Typography.caption.size
                                        color: root.selectedEncryptionIndex === index
                                             ? (MissionTheme.darkMode ? MissionTheme.contentOnPrimary
                                                                      : MissionTheme.contentOnPrimaryContainer)
                                             : MissionTheme.textTertiary
                                    }
                                }

                                Label {
                                    text: qsTr("Benefits — %1").arg(modelData.benefits)
                                    width: parent.width
                                    elide: Text.ElideRight
                                    font.pixelSize: Typography.bodySmall.size
                                    color: root.selectedEncryptionIndex === index
                                         ? (MissionTheme.darkMode ? MissionTheme.contentOnPrimary
                                                                  : MissionTheme.contentOnPrimaryContainer)
                                         : MissionTheme.textSecondary
                                }

                                Label {
                                    text: qsTr("Performance — %1").arg(modelData.performance)
                                    width: parent.width
                                    elide: Text.ElideRight
                                    font.pixelSize: Typography.bodySmall.size
                                    color: root.selectedEncryptionIndex === index
                                         ? (MissionTheme.darkMode ? MissionTheme.contentOnPrimary
                                                                  : MissionTheme.contentOnPrimaryContainer)
                                         : MissionTheme.textSecondary
                                }

                                Label {
                                    text: qsTr("Recovery — %1").arg(modelData.recovery)
                                    width: parent.width
                                    elide: Text.ElideRight
                                    font.pixelSize: Typography.bodySmall.size
                                    color: root.selectedEncryptionIndex === index
                                         ? (MissionTheme.darkMode ? MissionTheme.contentOnPrimary
                                                                  : MissionTheme.contentOnPrimaryContainer)
                                         : MissionTheme.textSecondary
                                }
                            }

                            MouseArea {
                                id: encryptionDelegateMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    encryptionList.currentIndex = index
                                    root.selectEncryption(index)
                                }
                            }

                            Accessible.role: Accessible.ListItem
                            Accessible.name: modelData.label + ", " + modelData.code
                            Accessible.description: modelData.benefits + ", " +
                                                    modelData.performance + ", " +
                                                    modelData.recovery
                            Accessible.selected: root.selectedEncryptionIndex === index
                        }
                    }

                    // ── Live selection feedback ──
                    Label {
                        id: selectionCaption
                        width: parent.width
                        visible: root.currentEncryptionCode.length > 0
                        text: qsTr("Selected: %1 · %2").arg(root.currentEncryptionLabel)
                                                      .arg(root.currentEncryptionCode)
                        font.pixelSize: Typography.caption.size
                        color: MissionTheme.textTertiary
                        elide: Text.ElideRight
                        Accessible.role: Accessible.StaticText
                        Accessible.name: text
                    }
                }
            }

            // ── Help panel (optional; collapses on narrow widths) ──
            Rectangle {
                id: helpPanel
                visible: root.wideLayout
                Layout.fillHeight: true
                Layout.preferredWidth: Math.min(Spacing.sidebarWidth, root.width * 0.32)
                radius: Radii.card
                color: MissionTheme.surfaceVariant

                Column {
                    anchors.fill: parent
                    anchors.margins: Spacing.paddingLarge
                    spacing: Spacing.gapMedium

                    Label {
                        text: qsTr("Help & tips")
                        font.pixelSize: Typography.subtitle.size
                        font.weight: Typography.subtitle.weight
                        color: MissionTheme.textPrimary
                    }

                    Label {
                        text: qsTr("Encryption protects your data at rest with LUKS2 if the device is lost or stolen. No encryption is the default — every option is a deliberate choice.")
                        width: parent.width
                        font.pixelSize: Typography.bodySmall.size
                        color: MissionTheme.textSecondary
                        wrapMode: Text.Wrap
                        lineHeight: Typography.lineHeightNormal
                    }

                    Item { width: 1; height: Spacing.gapSmall }

                    Label {
                        text: qsTr("Each option explains its benefits, performance impact, and recovery implications. Review them before continuing.")
                        width: parent.width
                        font.pixelSize: Typography.bodySmall.size
                        color: MissionTheme.textSecondary
                        wrapMode: Text.Wrap
                        lineHeight: Typography.lineHeightNormal
                    }

                    Item { width: 1; height: Spacing.gapSmall }

                    Label {
                        text: qsTr("When encryption is enabled, a cryptographically secure recovery key is generated during installation and can be printed. Keep it safe — without it, encrypted data cannot be recovered.")
                        width: parent.width
                        font.pixelSize: Typography.caption.size
                        color: MissionTheme.textTertiary
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }

    // ══════════════════════════════════════════════════════════════
    // Bottom action bar (Back / Continue)
    // ══════════════════════════════════════════════════════════════
    Rectangle {
        id: actionBar
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: Spacing.minimumTouchTarget + Spacing.paddingMedium * 2
        color: MissionTheme.surface
        z: 2

        // Top hairline
        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
            }
            height: 1
            color: MissionTheme.outline
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Spacing.paddingPage
            anchors.rightMargin: Spacing.paddingPage
            spacing: Spacing.gapMedium

            // Back is only available past step 1 (linear workflow)
            MissionButton {
                id: backButton
                objectName: "encryptionBack"
                variant: MissionButton.Variant.Secondary
                text: qsTr("Back")
                enabled: root.step > 1
                onClicked: root.backRequested()
            }

            Item { Layout.fillWidth: true }

            // Continue (primary action; disabled while loading/error so
            // it never silently advances when validation is pending —
            // "No encryption" is a valid preselected choice, so no
            // further gate applies on this single-select screen)
            MissionButton {
                id: continueButton
                objectName: "encryptionContinue"
                variant: MissionButton.Variant.Primary
                text: qsTr("Continue")
                loading: root.screenState === "loading"
                enabled: root.screenState !== "loading" && root.screenState !== "error"
                onClicked: root.continueRequested()
                focus: true
            }
        }
    }
}
