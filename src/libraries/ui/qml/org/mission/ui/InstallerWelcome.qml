// Mission OS — Installer Welcome (MOS-INS-001)
//
// First screen of the Mission OS installer.
// Implements the source-defined Welcome structure (docs/wireframes/
// 01_INSTALLER.md + docs/reference/01_INSTALLER.md Screen 01):
//
//   Hosting: place inside MissionWindow (or MissionPage) content and
//   anchor to fill, e.g.  MissionWindow { InstallerWelcome { anchors.fill: parent } }
//   The component itself sizes to its implicit 1024x768 like MissionPage.
//
//   Header → Stepper Navigation → Main Content → Help Panel → Bottom actions
//
// Displayed items (per reference Screen 01):
//   - Mission OS identity (logo mark + wordmark)
//   - Version + build type (Stable / Beta / Nightly)
//   - Language selector
//   - Accessibility button
//   - Documentation button
//   - Release notes
//   - Continue / Shutdown / Restart / Exit installer
//
// States (per wireframe): empty · loading · error · success · offline
// The screen exposes *Requested signals; the host application decides
// what each action does (e.g. wiring Shutdown to logind/systemctl).
//
// Design-system compliance:
//   - Tokens only (Colors, Typography, Spacing, Radii, Motion, MissionTheme)
//   - Light + dark themes via MissionTheme (driven by host)
//   - Keyboard navigation with visible focus states (MissionButton)
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
    property int step: 1

    /// Total number of installer steps (screen registry: 16)
    property int totalSteps: 17

    /// Reduced motion (accessibility)
    property bool reducedMotion: false

    /// Installer/OS version string shown in the header
    property string version: "0.1.0"

    /// Build channel: Stable | Beta | Nightly
    property string buildType: "Nightly"

    /// Currently selected display language
    property string currentLanguage: "English"

    /// Available languages (label + locale code)
    property var languages: [
        { label: "English",  code: "en_US" },
        { label: "Deutsch",  code: "de_DE" },
        { label: "Français", code: "fr_FR" },
        { label: "Español",  code: "es_ES" },
        { label: "日本語",    code: "ja_JP" }
    ]

    // ── Signals (host wiring) ──────────────────────────────────────
    /// User requested to continue to the next step
    signal continueRequested()
    /// User requested to go back to the previous step
    signal backRequested()
    /// User selected a language (locale code)
    signal languageChangeRequested(string code)
    /// User requested accessibility configuration
    signal accessibilityRequested()
    /// User requested documentation
    signal documentationRequested()
    /// User requested release notes
    signal releaseNotesRequested()
    /// User requested system shutdown
    signal shutdownRequested()
    /// User requested system restart
    signal restartRequested()
    /// User requested to exit the installer (leave to live environment)
    signal exitRequested()
    /// User requested to retry after an error
    signal retryRequested()

    // ── Escape leaves the installer (Master UX: Escape supported) ──
    Keys.onEscapePressed: root.exitRequested()

    // ── Responsive helpers ─────────────────────────────────────────
    readonly property bool wideLayout: root.width >= 760
    readonly property bool compactLayout: root.width < 640

    // ── Language selection helper ──────────────────────────────────
    function selectLanguage(index) {
        if (index < 0 || index >= root.languages.length)
            return
        root.currentLanguage = root.languages[index].label
        root.languageChangeRequested(root.languages[index].code)
    }

    // ── Test hooks (used by tests/tst_installer_welcome.qml) ───────
    property alias backgroundColor: backgroundRect.color
    property alias headingColor: headingLabel.color
    property alias headingLabel: headingLabel
    property alias modeCards: modeCards
    property alias continueButton: continueButton
    property alias backButton: backButton
    property alias languageButton: languageButton
    property alias accessibilityButton: accessibilityButton
    property alias powerButton: powerButton
    property alias powerMenu: powerMenu
    property alias shutdownItem: shutdownItem
    property alias restartItem: restartItem
    property alias exitItem: exitItem
    property alias languageMenu: languageMenu
    property alias documentationButton: documentationButton
    property alias releaseNotesButton: releaseNotesButton
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

            // Language selector
            MissionButton {
                id: languageButton
                objectName: "welcomeLanguage"
                variant: MissionButton.Variant.Secondary
                compact: root.compactLayout
                text: root.currentLanguage
                onClicked: languageMenu.popup(languageButton, 0, languageButton.height)
                Accessible.description: qsTr("Change language")
            }

            // Accessibility button
            MissionButton {
                id: accessibilityButton
                objectName: "welcomeAccessibility"
                variant: MissionButton.Variant.Tertiary
                compact: root.compactLayout
                text: qsTr("Accessibility")
                onClicked: root.accessibilityRequested()
            }

            // Power menu (Shutdown / Restart / Exit installer)
            MissionButton {
                id: powerButton
                objectName: "welcomePower"
                variant: MissionButton.Variant.Tertiary
                compact: true
                text: qsTr("Power")
                onClicked: powerMenu.popup(powerButton, 0, powerButton.height)
                Accessible.description: qsTr("Shutdown, restart, or exit installer")
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
                text: qsTr("Step %1 of %2 · Welcome").arg(root.step).arg(root.totalSteps)
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
                    spacing: Spacing.gapLarge

                    // ── State area (per installer wireframe states) ──
                    // Loading (non-blocking progress)
                    RowLayout {
                        id: loadingIndicator
                        visible: root.screenState === "loading"
                        width: parent.width
                        spacing: Spacing.gapMedium
                        Label {
                            text: qsTr("Preparing installation…")
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
                        // invisible even when `visible` is true (same
                        // latent bug class as 002/003 — fixed here with
                        // the proven pattern).
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
                                    text: qsTr("Installation cannot continue")
                                    font.weight: Typography.weightSemibold
                                    color: Colors.contentOnErrorContainer
                                }
                                Label {
                                    text: qsTr("The installation media could not be verified. Check the media and try again.")
                                    font.pixelSize: Typography.bodySmall.size
                                    color: Colors.contentOnErrorContainer
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                            MissionButton {
                                id: retryButton
                                objectName: "welcomeRetry"
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
                        // Explicit height from content (see errorBanner note).
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
                                    text: qsTr("Installation is ready")
                                    font.weight: Typography.weightSemibold
                                    color: Colors.contentOnSuccessContainer
                                }
                                Label {
                                    text: qsTr("Your system meets the requirements. You can begin installation.")
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
                        // Explicit height from content (see errorBanner note).
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
                                    text: qsTr("Mission OS installs fully without an internet connection. No account or telemetry is required.")
                                    font.pixelSize: Typography.bodySmall.size
                                    color: MissionTheme.textSecondary
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }

                    // ── Welcome copy ──
                    Label {
                        id: headingLabel
                        text: qsTr("Welcome to Mission OS")
                        width: parent.width
                        font.pixelSize: Typography.headline.size
                        font.weight: Typography.headline.weight
                        color: MissionTheme.textPrimary
                        wrapMode: Text.Wrap
                        // Heading landmark for screen readers — consistent
                        // with every other installer screen (audit fix:
                        // this screen's heading previously lacked the role).
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    Label {
                        text: qsTr("Mission OS is a portable, privacy-first operating system. This installer guides you through a safe, transparent setup — your data stays on your device, and no account or internet connection is required.")
                        width: parent.width
                        font.pixelSize: Typography.bodyLarge.size
                        color: MissionTheme.textSecondary
                        wrapMode: Text.Wrap
                        lineHeight: Typography.lineHeightRelaxed
                    }

                    // ── Installation mode cards (informational) ──
                    GridLayout {
                        width: parent.width
                        columns: root.wideLayout ? 2 : 1
                        columnSpacing: Spacing.gapLarge
                        rowSpacing: Spacing.gapLarge

                        Repeater {
                            id: modeCards
                            model: [
                                { title: qsTr("Portable Mode"),
                                  body: qsTr("Runs directly from removable media. Your current system stays untouched — ideal for travel, emergency recovery and privacy-sensitive environments.") },
                                { title: qsTr("Install Mission OS"),
                                  body: qsTr("Installs permanently onto internal storage with full performance, automatic updates and recovery support.") }
                            ]
                            delegate: Rectangle {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 240
                                radius: Radii.card
                                color: MissionTheme.surface
                                border.color: MissionTheme.outlineVariant
                                border.width: 1
                                implicitHeight: cardColumn.height + Spacing.paddingLarge * 2

                                // Announce each card as a named group
                                // (screen-reader semantics — consistent with
                                // the PrivacySetup option-card pattern;
                                // audit fix).
                                Accessible.role: Accessible.Grouping
                                Accessible.name: modelData.title
                                Accessible.description: modelData.body

                                Column {
                                    id: cardColumn
                                    x: Spacing.paddingLarge
                                    y: Spacing.paddingLarge
                                    width: parent.width - Spacing.paddingLarge * 2
                                    spacing: Spacing.gapSmall
                                    Label {
                                        text: modelData.title
                                        width: parent.width
                                        font.pixelSize: Typography.subtitle.size
                                        font.weight: Typography.subtitle.weight
                                        color: MissionTheme.textPrimary
                                        wrapMode: Text.Wrap
                                    }
                                    Label {
                                        text: modelData.body
                                        width: parent.width
                                        font.pixelSize: Typography.bodySmall.size
                                        color: MissionTheme.textSecondary
                                        wrapMode: Text.Wrap
                                        lineHeight: Typography.lineHeightNormal
                                    }
                                }
                            }
                        }
                    }

                    // ── Documentation / Release notes (always reachable) ──
                    Row {
                        spacing: Spacing.gapMedium
                        MissionButton {
                            id: documentationButton
                            objectName: "welcomeDocumentation"
                            variant: MissionButton.Variant.Tertiary
                            text: qsTr("Documentation")
                            onClicked: root.documentationRequested()
                        }
                        MissionButton {
                            id: releaseNotesButton
                            objectName: "welcomeReleaseNotes"
                            variant: MissionButton.Variant.Tertiary
                            text: qsTr("Release notes")
                            onClicked: root.releaseNotesRequested()
                        }
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
                        text: qsTr("You can change the language and accessibility options at any time. Documentation and release notes are always available.")
                        width: parent.width
                        font.pixelSize: Typography.bodySmall.size
                        color: MissionTheme.textSecondary
                        wrapMode: Text.Wrap
                        lineHeight: Typography.lineHeightNormal
                    }

                    Item { width: 1; height: Spacing.gapSmall }

                    Label {
                        text: qsTr("Privacy by default — no telemetry, no account, no cloud required.")
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
                objectName: "welcomeBack"
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
                objectName: "welcomeContinue"
                variant: MissionButton.Variant.Primary
                text: qsTr("Continue")
                loading: root.screenState === "loading"
                enabled: root.screenState !== "loading" && root.screenState !== "error"
                onClicked: root.continueRequested()
                focus: true
            }
        }
    }

    // ══════════════════════════════════════════════════════════════
    // Menus
    // ══════════════════════════════════════════════════════════════
    Menu {
        id: languageMenu
        title: qsTr("Language")
        background: Rectangle {
            radius: Radii.dialog
            color: MissionTheme.surface
            border.color: MissionTheme.outline
            border.width: 1
        }
        // Qt-documented pattern for dynamic menu items: Instantiator +
        // insertItem/removeItem (Repeater inside Menu is not reliable).
        Instantiator {
            model: root.languages
            delegate: MissionMenuItem {
                required property var modelData
                required property int index
                text: modelData.label
                highlighted: modelData.label === root.currentLanguage
                onTriggered: root.selectLanguage(index)
            }
            onObjectAdded: function(index, object) {
                languageMenu.insertItem(index, object)
            }
            onObjectRemoved: function(index, object) {
                languageMenu.removeItem(object)
            }
        }
    }

    Menu {
        id: powerMenu
        title: qsTr("Power")
        background: Rectangle {
            radius: Radii.dialog
            color: MissionTheme.surface
            border.color: MissionTheme.outline
            border.width: 1
        }
        MissionMenuItem {
            id: shutdownItem
            objectName: "welcomeShutdown"
            text: qsTr("Shutdown")
            onTriggered: root.shutdownRequested()
        }
        MissionMenuItem {
            id: restartItem
            objectName: "welcomeRestart"
            text: qsTr("Restart")
            onTriggered: root.restartRequested()
        }
        MissionMenuItem {
            id: exitItem
            objectName: "welcomeExit"
            text: qsTr("Exit installer")
            onTriggered: root.exitRequested()
        }
    }
}
