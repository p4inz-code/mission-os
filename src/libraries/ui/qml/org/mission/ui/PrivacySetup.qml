// Mission OS — Installer Privacy Setup (MOS-INS-005)
//
// Fifth screen of the Mission OS installer.
// Implements the source-defined Privacy structure (docs/wireframes/
// 01_INSTALLER.md + docs/reference/01_INSTALLER.md Screen 12
// "Privacy Preferences"):
//
//   Hosting: place inside MissionWindow (or MissionPage) content and
//   anchor to fill, e.g.  MissionWindow { PrivacySetup { anchors.fill: parent } }
//   The component itself sizes to its implicit 1024x768 like MissionPage.
//
//   Header → Stepper Navigation → Main Content → Help Panel → Bottom actions
//
// Displayed items (per reference Screen 12 "Privacy Preferences"):
//   - Six optional privacy options: crash reporting, anonymous
//     diagnostics, update checking, location access, search providers,
//     application permissions. Each option is a toggle (Switch) that is
//     OFF by default — Mission OS is privacy-by-default and every option
//     is opt-in (Privacy Center §2: telemetry disabled by default,
//     optional diagnostics require explicit opt-in, web search disabled
//     by default, location is requested per application).
//   - Every option clearly explains:
//       · what data/access is involved
//       · why it is used
//       · whether it is optional
//       · how to change it later
//   - Live feedback of how many options are enabled
//   - Back / Continue (wireframe UX rules: linear workflow, back always
//     available, validation before continuing)
//
// No option uses misleading wording or dark patterns (reference Screen 12).
//
// States (per wireframe): empty · loading · error · success · offline
// The screen exposes *Requested signals; the host application decides
// what each action does (e.g. persisting privacy preferences).
//
// Design-system compliance:
//   - Tokens only (Colors, Typography, Spacing, Radii, Motion, MissionTheme)
//   - Light + dark themes via MissionTheme (driven by host)
//   - Keyboard navigation with visible focus states
//   - WCAG AA-oriented contrast, reduced-motion aware
//   - Responsive reflow per docs/design/14_RESPONSIVE_RULES.md
//
// Note: Toggle Switch is specified in docs/design/05_COMPONENT_LIBRARY.md
// but not yet shipped as a library component. Per the established inline
// pattern (keyboard test area used stock TextField, presets reused inline
// chips), this screen uses the stock QtQuick.Controls.Switch styled with
// tokens inline — no new registered component.

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
    property int step: 5

    /// Total number of installer steps (screen registry: 16)
    property int totalSteps: 17

    /// Reduced motion (accessibility)
    property bool reducedMotion: false

    /// Installer/OS version string shown in the header
    property string version: "0.1.0"

    /// Build channel: Stable | Beta | Nightly
    property string buildType: "Nightly"

    /// Available privacy options. Each entry: { code, label, what, why,
    /// optional, change } — every option communicates what data/access is
    /// involved, why it is used, whether it is optional, and how to change
    /// it later (reference Screen 12). Static fixture; the host service
    /// persists the real preference when privacyChangeRequested fires.
    property var privacyOptions: [
        { code: "crash",
          label: "Crash reporting",
          what: "Sends details about what went wrong if the installer or an application stops unexpectedly.",
          why: "Used to diagnose and fix reliability problems.",
          optional: "Optional — disabled by default. Nothing is sent until you enable it.",
          change: "You can change this later in Settings → Privacy → Crash Reports." },
        { code: "diagnostics",
          label: "Anonymous diagnostics",
          what: "Shares non-identifying information about system health and performance.",
          why: "Used to improve stability and compatibility.",
          optional: "Optional — requires explicit opt-in.",
          change: "You can change this later in Settings → Privacy → Diagnostics." },
        { code: "updates",
          label: "Update checking",
          what: "Contacts the update service to check for new versions and security fixes.",
          why: "Used to let you know when updates are available.",
          optional: "Optional — disabled by default.",
          change: "You can change this later in Settings → Updates." },
        { code: "location",
          label: "Location access",
          what: "Allows applications to request your device's location.",
          why: "Used only by applications you choose, for location-aware features.",
          optional: "Optional — each application asks for permission individually.",
          change: "You can change this later in Settings → Privacy → Location." },
        { code: "search",
          label: "Search providers",
          what: "Sends search queries to optional web search providers when you search online.",
          why: "Used for web search — local and documentation search work without it.",
          optional: "Optional — web search is disabled by default.",
          change: "You can change this later in Settings → Privacy → Search." },
        { code: "permissions",
          label: "Application permissions",
          what: "Controls which applications can access camera, microphone, location, and other resources.",
          why: "Used to keep application access under your control.",
          optional: "Optional — managed per application.",
          change: "You can change this later in the Privacy Center → Permission Manager." }
    ]

    /// Number of options currently enabled (privacy by default: 0)
    property int enabledCount: 0

    // ── Signals (host wiring) ──────────────────────────────────────
    /// User requested to continue to the next step
    signal continueRequested()
    /// User requested to go back to the previous step
    signal backRequested()
    /// User toggled a privacy option (option code, e.g. "crash", and
    /// the new enabled state). Never emitted on load — all options are
    /// OFF by default and no toggle happens during initialization.
    signal privacyChangeRequested(string code, bool enabled)
    /// User requested to retry after an error
    signal retryRequested()

    // ── Escape navigates back (Master UX: Back always available) ──
    // No child on this screen consumes Escape (the toggles handle
    // Space/Return to flip), so root Escape always → backRequested.
    Keys.onEscapePressed: root.backRequested()

    // ── Responsive helpers ─────────────────────────────────────────
    readonly property bool wideLayout: root.width >= 760
    readonly property bool compactLayout: root.width < 640

    // ── Toggle helpers ─────────────────────────────────────────────
    /// Programmatically set an option's enabled state (host wiring).
    /// Flipping the Switch emits privacyChangeRequested exactly once.
    function setOptionEnabled(index, enabled) {
        if (index < 0 || index >= root.privacyOptions.length)
            return
        var item = root.privacyRows.itemAt(index)
        if (!item)
            return
        if (item.switchControl.checked !== enabled)
            item.switchControl.checked = enabled
    }

    /// Read an option's current enabled state (host wiring / tests).
    function isOptionEnabled(index) {
        if (index < 0 || index >= root.privacyOptions.length)
            return false
        var item = root.privacyRows.itemAt(index)
        return item ? item.switchControl.checked : false
    }

    // ── Test hooks (used by tests/tst_privacy_setup.qml) ───────────
    property alias backgroundColor: backgroundRect.color
    property alias headingColor: headingLabel.color
    property alias headingLabel: headingLabel
    property alias privacyRows: privacyRows
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
                text: qsTr("Step %1 of %2 · Privacy").arg(root.step).arg(root.totalSteps)
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
                            text: qsTr("Loading privacy options…")
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
                        // latent bug class as 001–004; proven fix).
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
                                    text: qsTr("Privacy options could not be loaded")
                                    font.weight: Typography.weightSemibold
                                    color: Colors.contentOnErrorContainer
                                }
                                Label {
                                    text: qsTr("The privacy settings could not be verified. Check the installation media and try again.")
                                    font.pixelSize: Typography.bodySmall.size
                                    color: Colors.contentOnErrorContainer
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                            MissionButton {
                                id: retryButton
                                objectName: "privacyRetry"
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
                                    text: qsTr("Privacy preferences saved")
                                    font.weight: Typography.weightSemibold
                                    color: Colors.contentOnSuccessContainer
                                }
                                Label {
                                    text: qsTr("Your privacy choices will be applied to the installed system.")
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
                                    text: qsTr("This step works without an internet connection. Privacy settings are stored locally and can be changed at any time.")
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
                        text: qsTr("Privacy preferences")
                        width: parent.width
                        font.pixelSize: Typography.headline.size
                        font.weight: Typography.headline.weight
                        color: MissionTheme.textPrimary
                        wrapMode: Text.Wrap
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    Label {
                        text: qsTr("Mission OS is privacy by default. Every option below is off until you turn it on — no account or internet connection is required.")
                        width: parent.width
                        font.pixelSize: Typography.bodyLarge.size
                        color: MissionTheme.textSecondary
                        wrapMode: Text.Wrap
                        lineHeight: Typography.lineHeightRelaxed
                    }

                    // ── Privacy option toggles ──
                    // One card per option. Each card states what data/
                    // access is involved, why it is used, whether it is
                    // optional, and how to change it later (reference
                    // Screen 12 — no misleading wording or dark patterns).
                    Repeater {
                        id: privacyRows
                        model: root.privacyOptions

                        delegate: Rectangle {
                            id: privacyDelegate
                            required property var modelData
                            required property int index

                            // Public access to the switch from the host /
                            // test suite. QML ids inside a Repeater delegate
                            // are scoped to the delegate component and are NOT
                            // reachable as properties on the delegate instance
                            // from outside — an explicit alias makes the switch
                            // addressable (same pattern as the root aliases).
                            property alias switchControl: switchControl

                            objectName: "privacyItem" + index
                            width: parent.width
                            radius: Radii.card
                            color: MissionTheme.surface
                            border.color: MissionTheme.outlineVariant
                            border.width: 1
                            // Explicit height from content (the proven
                            // pattern — a plain Column would otherwise
                            // collapse the card to 0 height).
                            height: optionColumn.height + Spacing.paddingMedium * 2

                            Column {
                                id: optionColumn
                                x: Spacing.paddingMedium
                                y: Spacing.paddingMedium
                                width: parent.width - Spacing.paddingMedium * 2
                                spacing: Spacing.gapSmall

                                // Title row + toggle (44px touch target)
                                RowLayout {
                                    width: parent.width
                                    spacing: Spacing.gapMedium

                                    Label {
                                        text: modelData.label
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        font.pixelSize: Typography.subtitle.size
                                        font.weight: Typography.subtitle.weight
                                        color: MissionTheme.textPrimary
                                        verticalAlignment: Text.AlignVCenter
                                    }

                                    // Stock Switch styled with tokens
                                    // (Toggle Switch component not yet
                                    // shipped — inline pattern).
                                    Switch {
                                        id: switchControl
                                        objectName: "privacyToggle" + index
                                        // Switch.checked defaults to false
                                        // (privacy-by-default); no binding is
                                        // declared so setOptionEnabled() can
                                        // assign it without breaking one.
                                        Layout.preferredHeight: Spacing.minimumTouchTarget
                                        Layout.preferredWidth: 64
                                        Layout.alignment: Qt.AlignVCenter

                                        // Fires whenever `checked` changes, regardless of the
                                        // source: user interaction (click / Space / Return) AND
                                        // programmatic assignment by the host API. `onToggled`
                                        // alone is NOT sufficient — Switch.toggled is not emitted
                                        // for programmatic `checked` assignment on this toolchain
                                        // (verified empirically), which would leave the host
                                        // wiring silent for setOptionEnabled().
                                        onCheckedChanged: {
                                            root.enabledCount += checked ? 1 : -1
                                            root.privacyChangeRequested(modelData.code, checked)
                                        }

                                        indicator: Rectangle {
                                            id: switchTrack
                                            anchors.verticalCenter: parent.verticalCenter
                                            x: switchControl.width - width - 4
                                            width: 44
                                            height: 24
                                            radius: 12
                                            color: switchControl.checked
                                                 ? MissionTheme.primary
                                                 : (switchControl.hovered
                                                    ? MissionTheme.outline
                                                    : MissionTheme.surfaceDim)
                                            // Unchecked state: 1px outline so the
                                            // track stays visible on the card
                                            // (WCAG 1.4.11 non-text contrast).
                                            border.width: switchControl.checked ? 0 : 1
                                            border.color: MissionTheme.outline

                                            Behavior on color {
                                                enabled: !root.reducedMotion
                                                animation: ColorAnimation { duration: Motion.colorChange }
                                            }

                                            // Visible focus ring (keyboard)
                                            // Declared inside the indicator
                                            // (Control's default property is
                                            // contentItem, so a direct child
                                            // of the Switch would replace its
                                            // content item — follow the
                                            // MissionButton pattern instead).
                                            Rectangle {
                                                anchors.fill: parent
                                                anchors.margins: -3
                                                radius: 15
                                                color: "transparent"
                                                border.color: MissionTheme.focusRing
                                                border.width: 2
                                                visible: switchControl.activeFocus
                                            }

                                            // Knob. Dark on the light track (and
                                            // light on the dark track) so the
                                            // unchecked state stays visible in
                                            // both themes (WCAG 1.4.11).
                                            Rectangle {
                                                x: switchControl.checked
                                                   ? parent.width - width - 3
                                                   : 3
                                                width: 18
                                                height: 18
                                                radius: 9
                                                anchors.verticalCenter: parent.verticalCenter
                                                color: switchControl.checked
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
                                        Accessible.description: modelData.what
                                        Accessible.checked: switchControl.checked
                                    }
                                }

                                // What data/access is involved
                                Label {
                                    text: modelData.what
                                    width: parent.width
                                    font.pixelSize: Typography.bodySmall.size
                                    color: MissionTheme.textSecondary
                                    wrapMode: Text.Wrap
                                    lineHeight: Typography.lineHeightNormal
                                }

                                // Why it is used
                                Label {
                                    text: modelData.why
                                    width: parent.width
                                    font.pixelSize: Typography.bodySmall.size
                                    color: MissionTheme.textSecondary
                                    wrapMode: Text.Wrap
                                    lineHeight: Typography.lineHeightNormal
                                }

                                // Whether it is optional + how to change later
                                Label {
                                    text: qsTr("%1 %2").arg(modelData.optional).arg(modelData.change)
                                    width: parent.width
                                    font.pixelSize: Typography.caption.size
                                    color: MissionTheme.textTertiary
                                    wrapMode: Text.Wrap
                                    lineHeight: Typography.lineHeightNormal
                                }
                            }

                            Accessible.role: Accessible.Grouping
                            Accessible.name: modelData.label
                            Accessible.description: modelData.what
                        }
                    }

                    // ── Live selection feedback ──
                    Label {
                        id: selectionCaption
                        width: parent.width
                        text: qsTr("Enabled: %1 of %2 optional services").arg(root.enabledCount)
                                                                        .arg(root.privacyOptions.length)
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
                        text: qsTr("Every option here is disabled by default — nothing leaves your device until you turn it on. You can change any of these later in Settings → Privacy or the Privacy Center.")
                        width: parent.width
                        font.pixelSize: Typography.bodySmall.size
                        color: MissionTheme.textSecondary
                        wrapMode: Text.Wrap
                        lineHeight: Typography.lineHeightNormal
                    }

                    Item { width: 1; height: Spacing.gapSmall }

                    Label {
                        text: qsTr("All options are optional, reversible, and can be changed at any time after installation.")
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
                objectName: "privacyBack"
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
                objectName: "privacyContinue"
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
