// Mission OS — Installer Security Options (MOS-INS-013)
//
// Thirteenth screen in the screen registry (MOS-INS-013). Placed in
// the install flow between Encryption (MOS-INS-009, step 9) and
// Summary (MOS-INS-010, step 11) — this is step 10 of 17.
// Implements the source-defined Security Options structure (docs/wireframes/
// 01_INSTALLER.md + docs/design/03_SCREEN_REGISTRY.md + docs/reference/
// 01_INSTALLER.md § "Screen 13 — Security Options"):
//
//   Hosting: place inside MissionWindow (or MissionPage) content and
//   anchor to fill, e.g.  MissionWindow { SecurityOptions { anchors.fill: parent } }
//   The component itself sizes to its implicit 1024x768 like MissionPage.
//
//   Header → Stepper Navigation → Main Content → Help Panel → Bottom actions
//
// Displayed items (per reference § "Screen 13 — Security Options"):
//   - Full Disk Encryption        (read-back from the previous Encryption screen;
//     the host supplies the value selected on MOS-INS-009)
//   - Secure Boot integration     (toggle, host-driven — available where supported)
//   - TPM integration             (toggle, host-driven — available where supported)
//   - Automatic security updates  (toggle, ON by default per security-by-default
//     principles)
//   - Recovery key generation     (read-back; the Encryption screen already
//     covers this as a choice, so the host reports the state)
//   - Emergency recovery media creation (toggle, OFF by default — user opts in)
//
// Every option includes:
//   - explanation
//   - benefits
//   - limitations
//   - compatibility notes
//
// The screen is host-fed for the encryption and TPM/Secure Boot availability
// (the host reports what the hardware supports). The user-facing toggles for
// Secure Boot integration, TPM integration, automatic updates, and emergency
// recovery media are interactive; the encryption and recovery key items are
// read-only summaries of what was already chosen on MOS-INS-009.
//
// Users should understand the trade-offs before enabling advanced security
// features (reference § "Screen 13").
//
// States (per wireframe): empty · loading · error · success · offline
// The screen exposes *Requested signals; the host application decides
// what each action does (e.g. configuring Secure Boot via sbctl, enabling
// automatic updates via the update service, creating recovery media).
//
// Design-system compliance:
//   - Tokens only (Colors, Typography, Spacing, Radii, Motion, MissionTheme)
//   - Light + dark themes via MissionTheme (driven by host)
//   - Keyboard navigation with visible focus states
//   - WCAG AA-oriented contrast, reduced-motion aware
//   - Responsive reflow per docs/design/14_RESPONSIVE_RULES.md
//   - 44px minimum touch targets
//   - 1024×768 minimum supported installer resolution

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

    /// Current installer step (1-based); this is step 10 of 17
    property int step: 10

    /// Total number of installer steps (screen registry: 16)
    property int totalSteps: 17

    /// Reduced motion (accessibility)
    property bool reducedMotion: false

    /// Installer/OS version string shown in the header
    property string version: "0.1.0"

    /// Build channel: Stable | Beta | Nightly
    property string buildType: "Nightly"

    /// Encryption choice from the previous screen (MOS-INS-009).
    /// Host-fed; the label is shown as a read-back summary.
    property string encryptionLabel: "No encryption"

    /// Whether the detected hardware supports Secure Boot integration
    /// (host-fed; null = unknown — the Secure Boot toggle stays
    /// disabled until the host reports support)
    property var secureBootSupported: null

    /// Whether the detected hardware has a TPM (host-fed; null =
    /// unknown — the TPM toggle stays disabled until the host reports)
    property var tpmSupported: null

    /// Whether Secure Boot integration is enabled (interactive toggle)
    property bool secureBootEnabled: false

    /// Whether TPM integration is enabled (interactive toggle)
    property bool tpmEnabled: false

    /// Whether automatic security updates are enabled (interactive
    /// toggle; ON by default per security-by-default)
    property bool autoUpdatesEnabled: true

    /// Whether emergency recovery media creation is requested
    /// (interactive toggle; OFF by default — explicit opt-in)
    property bool recoveryMediaEnabled: false

    /// Whether recovery key generation was selected on the Encryption
    /// screen. Host-fed; shown as a read-back summary.
    property bool recoveryKeySelected: false

    // ── Signals (host wiring) ──────────────────────────────────────
    /// User requested to continue to the next step
    signal continueRequested()
    /// User requested to go back to the previous step
    signal backRequested()
    /// User toggled Secure Boot integration (enabled)
    signal secureBootChangeRequested(bool enabled)
    /// User toggled TPM integration (enabled)
    signal tpmChangeRequested(bool enabled)
    /// User toggled automatic security updates (enabled)
    signal autoUpdatesChangeRequested(bool enabled)
    /// User toggled emergency recovery media creation (enabled)
    signal recoveryMediaChangeRequested(bool enabled)
    /// User requested to retry after an error
    signal retryRequested()

    // ── Escape navigates back (Master UX: Back always available) ──
    // No child on this screen consumes Escape (the toggle rows handle
    // Space/Return to flip), so root Escape always → backRequested.
    Keys.onEscapePressed: root.backRequested()

    // ── Responsive helpers ─────────────────────────────────────────
    readonly property bool wideLayout: root.width >= 760
    readonly property bool compactLayout: root.width < 640

    // ── Test hooks ─────────────────────────────────────────────────
    property alias backgroundColor: backgroundRect.color
    property alias headingColor: headingLabel.color
    property alias headingLabel: headingLabel
    property alias securityRows: securityRows
    property alias selectionCaption: selectionCaption
    property alias helpPanel: helpPanel
    property alias backButton: backButton
    property alias continueButton: continueButton
    property alias retryButton: retryButton
    property alias errorBanner: errorBanner
    property alias successBanner: successBanner
    property alias offlineBanner: offlineBanner
    property alias loadingIndicator: loadingIndicator
    property alias contentFlickable: contentFlickable
    property alias contentColumn: contentColumn

    /// Number of enabled security features (for the summary caption)
    readonly property int enabledCount: {
        var n = 0
        if (root.secureBootEnabled) n++
        if (root.tpmEnabled) n++
        if (root.autoUpdatesEnabled) n++
        if (root.recoveryMediaEnabled) n++
        return n
    }

    /// Formatted summary of enabled security features
    readonly property string enabledSummary: {
        var parts = []
        if (root.encryptionLabel !== "No encryption")
            parts.push("encryption")
        if (root.secureBootEnabled)
            parts.push("Secure Boot")
        if (root.tpmEnabled)
            parts.push("TPM")
        if (root.autoUpdatesEnabled)
            parts.push("auto updates")
        if (root.recoveryKeySelected)
            parts.push("recovery key")
        if (root.recoveryMediaEnabled)
            parts.push("recovery media")
        if (parts.length === 0)
            return qsTr("No additional security features enabled")
        return qsTr("Enabled: %1").arg(parts.join(", "))
    }

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
                text: qsTr("Step %1 of %2 · Security Options").arg(root.step).arg(root.totalSteps)
                font.pixelSize: Typography.bodySmall.size
                font.weight: Typography.weightSemibold
                color: MissionTheme.textSecondary
                elide: Text.ElideRight
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }

            Item { Layout.fillWidth: true }

            // Step segments — responsive dot sizing: compact or
            // non-wide layouts use 8px dots to avoid imbalance
            // when the help panel is hidden (sizing audit fix for
            // the 640–759px responsive gap).
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
                            text: qsTr("Checking security features…")
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
                                    text: qsTr("Security options could not be loaded")
                                    font.weight: Typography.weightSemibold
                                    color: Colors.contentOnErrorContainer
                                }
                                Label {
                                    text: qsTr("The security feature information could not be verified. Check the installation media and try again.")
                                    font.pixelSize: Typography.bodySmall.size
                                    color: Colors.contentOnErrorContainer
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                            MissionButton {
                                id: retryButton
                                objectName: "securityRetry"
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
                                    text: qsTr("Security preferences saved")
                                    font.weight: Typography.weightSemibold
                                    color: Colors.contentOnSuccessContainer
                                }
                                Label {
                                    text: qsTr("Your security choices will be applied during installation.")
                                    font.pixelSize: Typography.bodySmall.size
                                    color: Colors.contentOnSuccessContainer
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }

                    // Offline (informational — installation works offline)
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
                                    text: qsTr("This step works without an internet connection. Security features are configured locally on this device.")
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
                        text: qsTr("Security Options")
                        width: parent.width
                        font.pixelSize: Typography.headline.size
                        font.weight: Typography.headline.weight
                        color: MissionTheme.textPrimary
                        wrapMode: Text.Wrap
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    Label {
                        text: qsTr("Configure advanced security features for your Mission OS installation. Every option explains its benefits, limitations, and compatibility notes — review the trade-offs before enabling advanced features. The encryption method chosen earlier is shown for reference.")
                        width: parent.width
                        font.pixelSize: Typography.bodyLarge.size
                        color: MissionTheme.textSecondary
                        wrapMode: Text.Wrap
                        lineHeight: Typography.lineHeightRelaxed
                    }

                    // ── Security feature cards ──
                    // Each card provides: explanation, benefits,
                    // limitations, compatibility notes (reference
                    // § "Screen 13"). Encryption and recovery key
                    // are read-only summaries; the rest are toggles.
                    Repeater {
                        id: securityRows
                        model: [
                            // 0: Encryption (read-back; host-fed)
                            { code: "encryption", label: qsTr("Full Disk Encryption"),
                              explanation: qsTr("Protects all data at rest with encryption."),
                              benefits: qsTr("Data is unreadable without the passphrase or recovery key."),
                              limitations: qsTr("Requires a passphrase at boot; minor performance overhead."),
                              compatibility: qsTr("Supported on all storage hardware with LUKS2."),
                              interactive: false },
                            // 1: Secure Boot integration
                            { code: "secureboot", label: qsTr("Secure Boot Integration"),
                              explanation: qsTr("Verifies that only trusted software runs during boot."),
                              benefits: qsTr("Prevents unauthorized bootloaders and kernel tampering."),
                              limitations: qsTr("Requires UEFI with Secure Boot support; may need manual enrollment on some hardware."),
                              compatibility: qsTr("Supported on UEFI systems with Secure Boot enabled."),
                              interactive: true },
                            // 2: TPM integration
                            { code: "tpm", label: qsTr("TPM Integration"),
                              explanation: qsTr("Uses the Trusted Platform Module for hardware-backed security."),
                              benefits: qsTr("Enables TPM-assisted unlock, measured boot, and attestation."),
                              limitations: qsTr("Requires TPM 2.0 hardware; some features need firmware support."),
                              compatibility: qsTr("Supported on systems with TPM 2.0 (most modern laptops and desktops)."),
                              interactive: true },
                            // 3: Automatic security updates
                            { code: "autoupdates", label: qsTr("Automatic Security Updates"),
                              explanation: qsTr("Downloads and installs critical security updates automatically."),
                              benefits: qsTr("Keeps the system protected against known vulnerabilities without manual intervention."),
                              limitations: qsTr("Requires internet access; may restart services; no reboot required for most updates."),
                              compatibility: qsTr("Works on all supported hardware with internet connectivity."),
                              interactive: true },
                            // 4: Recovery key generation (read-back)
                            { code: "recoverykey", label: qsTr("Recovery Key Generation"),
                              explanation: qsTr("Generates a cryptographically secure, printable recovery key."),
                              benefits: qsTr("Provides a fallback access method if the passphrase is lost."),
                              limitations: qsTr("The recovery key must be stored securely; without it, encrypted data cannot be recovered."),
                              compatibility: qsTr("Available when encryption is enabled."),
                              interactive: false },
                            // 5: Emergency recovery media
                            { code: "recoverymedia", label: qsTr("Emergency Recovery Media"),
                              explanation: qsTr("Creates bootable recovery media for system repair."),
                              benefits: qsTr("Allows recovery of the system even if the bootloader or operating system is damaged."),
                              limitations: qsTr("Requires a USB drive or other removable media with sufficient capacity."),
                              compatibility: qsTr("Works on all supported hardware with a USB port."),
                              interactive: true }
                        ]

                        delegate: Rectangle {
                            id: securityDelegate
                            required property var modelData
                            required property int index

                            property alias toggleControl: toggleControl
                            property bool isInteractive: modelData.interactive
                            property bool isEnabled: {
                                if (!isInteractive) return false
                                if (modelData.code === "secureboot") return root.secureBootEnabled
                                if (modelData.code === "tpm") return root.tpmEnabled
                                if (modelData.code === "autoupdates") return root.autoUpdatesEnabled
                                if (modelData.code === "recoverymedia") return root.recoveryMediaEnabled
                                return false
                            }
                            // var (not bool) so null (capability unknown) is
                            // preserved and distinguishable from false
                            // (capability explicitly unsupported)
                            property var isAvailable: {
                                if (modelData.code === "secureboot") return root.secureBootSupported
                                if (modelData.code === "tpm") return root.tpmSupported
                                return true
                            }

                            objectName: "securityItem" + index
                            width: parent.width
                            radius: Radii.card
                            color: MissionTheme.surface
                            border.color: MissionTheme.outlineVariant
                            border.width: 1
                            height: optionColumn.height + Spacing.paddingMedium * 2

                            Column {
                                id: optionColumn
                                x: Spacing.paddingMedium
                                y: Spacing.paddingMedium
                                width: parent.width - Spacing.paddingMedium * 2
                                spacing: Spacing.gapSmall

                                // Title row + toggle/read-only indicator (44px touch target)
                                RowLayout {
                                    width: parent.width
                                    spacing: Spacing.gapMedium

                                    Label {
                                        text: modelData.label
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 120
                                        elide: Text.ElideRight
                                        font.pixelSize: Typography.subtitle.size
                                        font.weight: Typography.subtitle.weight
                                        color: isInteractive
                                             ? (isAvailable ? MissionTheme.textPrimary : MissionTheme.textTertiary)
                                             : MissionTheme.textPrimary
                                        verticalAlignment: Text.AlignVCenter
                                    }

                                    // Interactive toggle (Switch) or read-only status indicator
                                    Item {
                                        Layout.preferredWidth: 64
                                        Layout.preferredHeight: Spacing.minimumTouchTarget
                                        Layout.alignment: Qt.AlignVCenter

                                        // Interactive toggle
                                        Switch {
                                            id: toggleControl
                                            visible: isInteractive
                                            enabled: isAvailable
                                            checked: isEnabled
                                            // Single Accessible.description: composes the row
                                            // explanation with the capability status so an
                                            // unknown capability is never announced as supported
                                            // (FABRICATION-9)
                                            Accessible.description: {
                                                var suffix = ""
                                                if (modelData.code === "secureboot" || modelData.code === "tpm") {
                                                    if (isAvailable === false)
                                                        suffix = qsTr("Not supported on this system")
                                                    else if (isAvailable !== true)
                                                        suffix = qsTr("Support status unknown")
                                                }
                                                return suffix.length > 0
                                                    ? modelData.explanation + " " + suffix
                                                    : modelData.explanation
                                            }
                                            anchors.centerIn: parent
                                            Layout.preferredHeight: Spacing.minimumTouchTarget
                                            Layout.preferredWidth: 64

                                            onCheckedChanged: {
                                                if (modelData.code === "secureboot") {
                                                    root.secureBootEnabled = checked
                                                    root.secureBootChangeRequested(checked)
                                                } else if (modelData.code === "tpm") {
                                                    root.tpmEnabled = checked
                                                    root.tpmChangeRequested(checked)
                                                } else if (modelData.code === "autoupdates") {
                                                    root.autoUpdatesEnabled = checked
                                                    root.autoUpdatesChangeRequested(checked)
                                                } else if (modelData.code === "recoverymedia") {
                                                    root.recoveryMediaEnabled = checked
                                                    root.recoveryMediaChangeRequested(checked)
                                                }
                                            }

                                            indicator: Rectangle {
                                                id: switchTrack
                                                anchors.verticalCenter: parent.verticalCenter
                                                x: toggleControl.width - width - 4
                                                width: 44
                                                height: 24
                                                radius: 12
                                                color: toggleControl.checked
                                                     ? (toggleControl.enabled ? MissionTheme.primary : MissionTheme.surfaceDim)
                                                     : (toggleControl.hovered && toggleControl.enabled
                                                        ? MissionTheme.outline
                                                        : MissionTheme.surfaceDim)
                                                border.width: toggleControl.checked ? 0 : 1
                                                border.color: MissionTheme.outline

                                                Behavior on color {
                                                    enabled: !root.reducedMotion
                                                    animation: ColorAnimation { duration: Motion.colorChange }
                                                }

                                                Rectangle {
                                                    anchors.fill: parent
                                                    anchors.margins: -3
                                                    radius: 15
                                                    color: "transparent"
                                                    border.color: MissionTheme.focusRing
                                                    border.width: 2
                                                    visible: toggleControl.activeFocus
                                                }

                                                Rectangle {
                                                    x: toggleControl.checked
                                                       ? parent.width - width - 3
                                                       : 3
                                                    width: 18
                                                    height: 18
                                                    radius: 9
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    color: toggleControl.checked
                                                         ? MissionTheme.contentOnPrimary
                                                         : MissionTheme.textSecondary

                                                    Behavior on x {
                                                        enabled: !root.reducedMotion
                                                        NumberAnimation { duration: Motion.durationFast }
                                                    }
                                                }
                                            }

                                            Accessible.role: Accessible.CheckBox
                                            Accessible.name: modelData.label
                                            Accessible.checked: toggleControl.checked
                                        }

                                        // Read-only indicator: shows the value for encryption/recovery key
                                        Label {
                                            visible: !isInteractive
                                            anchors.centerIn: parent
                                            font.pixelSize: Typography.body.size
                                            font.weight: Typography.weightSemibold
                                            color: MissionTheme.textPrimary
                                            text: {
                                                if (modelData.code === "encryption")
                                                    return root.encryptionLabel
                                                if (modelData.code === "recoverykey")
                                                    return root.recoveryKeySelected ? qsTr("Selected") : qsTr("Not selected")
                                                return ""
                                            }
                                        }
                                    }
                                }

                                // Explanation
                                Label {
                                    text: modelData.explanation
                                    width: parent.width
                                    font.pixelSize: Typography.bodySmall.size
                                    color: MissionTheme.textSecondary
                                    wrapMode: Text.Wrap
                                    lineHeight: Typography.lineHeightNormal
                                }

                                // Benefits
                                Label {
                                    text: qsTr("Benefits — %1").arg(modelData.benefits)
                                    width: parent.width
                                    font.pixelSize: Typography.bodySmall.size
                                    color: MissionTheme.textSecondary
                                    wrapMode: Text.Wrap
                                    lineHeight: Typography.lineHeightNormal
                                }

                                // Limitations
                                Label {
                                    text: qsTr("Limitations — %1").arg(modelData.limitations)
                                    width: parent.width
                                    font.pixelSize: Typography.bodySmall.size
                                    color: MissionTheme.textSecondary
                                    wrapMode: Text.Wrap
                                    lineHeight: Typography.lineHeightNormal
                                }

                                // Compatibility notes
                                Label {
                                    text: qsTr("Compatibility — %1").arg(modelData.compatibility)
                                    width: parent.width
                                    font.pixelSize: Typography.caption.size
                                    color: MissionTheme.textTertiary
                                    wrapMode: Text.Wrap
                                    lineHeight: Typography.lineHeightNormal
                                }
                            }

                            Accessible.role: Accessible.Grouping
                            Accessible.name: modelData.label
                            Accessible.description: modelData.explanation
                        }
                    }

                    // ── Live selection feedback ──
                    Label {
                        id: selectionCaption
                        width: parent.width
                        text: root.enabledSummary
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
                        text: qsTr("Security options protect your system against tampering, unauthorized access, and data loss. Every option explains its benefits and limitations — read the trade-offs before enabling advanced features.")
                        width: parent.width
                        font.pixelSize: Typography.bodySmall.size
                        color: MissionTheme.textSecondary
                        wrapMode: Text.Wrap
                        lineHeight: Typography.lineHeightNormal
                    }

                    Item { width: 1; height: Spacing.gapSmall }

                    Label {
                        text: qsTr("Secure Boot integration works with UEFI systems. TPM integration requires TPM 2.0 hardware. Both are opt-in — the system works without them.")
                        width: parent.width
                        font.pixelSize: Typography.bodySmall.size
                        color: MissionTheme.textSecondary
                        wrapMode: Text.Wrap
                        lineHeight: Typography.lineHeightNormal
                    }

                    Item { width: 1; height: Spacing.gapSmall }

                    Label {
                        text: qsTr("Automatic security updates are enabled by default — this is the recommended setting. Emergency recovery media creation is optional and requires a USB drive.")
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
                objectName: "securityBack"
                variant: MissionButton.Variant.Secondary
                text: qsTr("Back")
                enabled: root.step > 1
                onClicked: root.backRequested()
            }

            Item { Layout.fillWidth: true }

            // Continue (primary action; disabled while loading/error so it
            // never silently advances when validation is pending)
            MissionButton {
                id: continueButton
                objectName: "securityContinue"
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