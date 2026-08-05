// Mission OS — Workspace Confirmation (MOS-INS-015)
//
// Fifteenth screen of the Mission OS installer — step 15 of 17,
// appended after the First Boot Welcome screen (MOS-INS-014, step 14)
// as the second screen of the first-boot experience.
// Implements the source-defined Workspace Confirmation structure
// (docs/wireframes/01_INSTALLER.md + docs/reference/01_INSTALLER.md
// § "Screen 17 — Workspace Confirmation" + § "Screen 11 — Workspace
// Profile"):
//
//   Hosting: place inside MissionWindow (or MissionPage) content and
//   anchor to fill, e.g.  MissionWindow { WorkspaceConfirmation { anchors.fill: parent } }
//   The component itself sizes to its implicit 1024x768 like MissionPage.
//
//   Header → Stepper Navigation → Main Content → Help Panel → Bottom actions
//
// Displayed items (per reference § "Screen 17 — Workspace Confirmation"):
//   - Users may review or change the selected workspace profile — a
//     single-select list of exactly the seven reference profiles
//     (Creator, Developer, Privacy, Security, Student, General,
//     Minimal), in the reference's order. No profile is invented or
//     omitted.
//   - Every profile explains what changing it updates (reference §
//     "Screen 17": "Changing the profile updates: default applications,
//     shortcuts, desktop layout, recommended settings") and that no
//     reinstall is required (reference § "Screen 17": "No reinstall is
//     required"; § "Screen 11": "Profiles may be changed later without
//     reinstalling Mission OS").
//   - Reference § "Screen 11" grounding: "Profiles configure: default
//     applications, desktop layout, shortcuts, recommended settings,
//     workspace defaults" and "No profile should install unnecessary
//     software."
//
// Interpretation notes (documented; no authoritative source specifies
// further detail):
//   - This is a review/confirm screen for the workspace profile selected
//     during installation (the installer has no in-flow profile
//     configuration screen in this implementation — reference Screen 11
//     is not part of the established MOS-INS-001→014 flow). The host
//     feeds the actual selection from the install configuration into
//     `selectedProfileIndex`; the first profile is preselected on load
//     WITHOUT emitting a signal (the host already knows the choice),
//     following the Encryption preselection precedent.
//   - The user may change the profile here; each change emits
//     workspaceChangeRequested(code) once (host persists/applies it —
//     profiles are applied without reinstalling).
//   - Continue is the primary action (validation-before-continue: a
//     valid profile is always selected, so Continue only blocks while
//     loading/error — the established pattern). Back is available
//     (step 15 > 1); Escape → backRequested like every non-terminal
//     screen.
//   - States follow the wireframe (empty · loading · error · success ·
//     offline). No host/change signal is emitted during initialization.
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

    /// Current installer step (1-based); this is step 15 of 17
    property int step: 15

    /// Total number of installer steps (screen registry: 16)
    property int totalSteps: 17

    /// Reduced motion (accessibility)
    property bool reducedMotion: false

    /// Installer/OS version string shown in the header
    property string version: "0.1.0"

    /// Build channel: Stable | Beta | Nightly
    property string buildType: "Nightly"

    /// Available workspace profiles. Each entry: { code, label, role,
    /// configures } — the reference's seven profiles, each with a
    /// brief role line and the "changing the profile updates" list
    /// (default applications, shortcuts, desktop layout, recommended
    /// settings — reference § "Screen 17"). Static fixture the host may
    /// replace wholesale; the host applies the real choice when
    /// workspaceChangeRequested fires.
    property var workspaceProfiles: [
        { code: "creator",
          label: "Creator",
          role: "Optimized for creative work — design, media, and content creation.",
          configures: "Default applications · desktop layout · shortcuts · recommended settings" },
        { code: "developer",
          label: "Developer",
          role: "Optimized for software development with development tools and terminal workflows.",
          configures: "Default applications · desktop layout · shortcuts · recommended settings" },
        { code: "privacy",
          label: "Privacy",
          role: "Minimal data exposure with privacy-first defaults and reduced connectivity.",
          configures: "Default applications · desktop layout · shortcuts · recommended settings" },
        { code: "security",
          label: "Security",
          role: "Hardened security defaults with conservative permission and update policies.",
          configures: "Default applications · desktop layout · shortcuts · recommended settings" },
        { code: "student",
          label: "Student",
          role: "A balanced setup for learning with productivity and study applications.",
          configures: "Default applications · desktop layout · shortcuts · recommended settings" },
        { code: "general",
          label: "General",
          role: "A balanced default environment for everyday use.",
          configures: "Default applications · desktop layout · shortcuts · recommended settings" },
        { code: "minimal",
          label: "Minimal",
          role: "A lean environment with only essential applications.",
          configures: "Default applications · desktop layout · shortcuts · recommended settings" }
    ]

    /// Index of the selected workspace profile within `workspaceProfiles`
    property int selectedProfileIndex: 0

    /// The selected profile object (from `workspaceProfiles`)
    property var selectedProfile: root.workspaceProfiles.length > 0 ? root.workspaceProfiles[0] : null

    /// Currently selected profile label. Preselected to the first
    /// profile so the screen loads with a valid choice (no signal is
    /// emitted on load — the host feeds the real selection).
    property string currentProfileLabel: root.workspaceProfiles.length > 0 ? root.workspaceProfiles[0].label : ""

    /// Currently selected profile code (e.g. "creator", "developer")
    property string currentProfileCode: root.workspaceProfiles.length > 0 ? root.workspaceProfiles[0].code : ""

    /// Number of workspace profiles (all are shown)
    property int profileCount: root.workspaceProfiles.length

    // ── Signals (host wiring) ──────────────────────────────────────
    /// User requested to continue to the next step
    signal continueRequested()
    /// User requested to go back to the previous step
    signal backRequested()
    /// User selected a workspace profile (code, e.g. "creator",
    /// "developer"). Never emitted on load — the first profile is
    /// preselected during initialization only.
    signal workspaceChangeRequested(string code)
    /// User requested to retry after an error
    signal retryRequested()

    // ── Escape navigates back (Master UX: Back always available) ──
    // No child on this screen consumes Escape (the list handles
    // Up/Down/Enter/Space), so root Escape always → backRequested.
    Keys.onEscapePressed: root.backRequested()

    // ── Responsive helpers ─────────────────────────────────────────
    readonly property bool wideLayout: root.width >= 760
    readonly property bool compactLayout: root.width < 640

    /// Height of a profile row (label + role + configures). Named once
    /// so the ListView height formula and the delegate height can never
    /// drift apart (no single token fits three text lines — same
    /// pattern as the Encryption/Disk Selection row heights).
    readonly property int profileRowHeight: 108

    // ── Selection helper ───────────────────────────────────────────
    /// Select the workspace profile at `index` (host wiring / tests).
    /// Emits workspaceChangeRequested exactly once with the profile code.
    function selectProfile(index) {
        if (index < 0 || index >= root.workspaceProfiles.length)
            return
        var profile = root.workspaceProfiles[index]
        root.selectedProfileIndex = index
        root.selectedProfile = profile
        root.currentProfileLabel = profile.label
        root.currentProfileCode = profile.code
        root.workspaceChangeRequested(root.currentProfileCode)
    }

    // ── Test hooks (used by tests/tst_workspace_confirmation.qml) ──
    property alias backgroundColor: backgroundRect.color
    property alias headingColor: headingLabel.color
    property alias headingLabel: headingLabel
    property alias profileList: profileList
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
                text: qsTr("Step %1 of %2 · Workspace").arg(root.step).arg(root.totalSteps)
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
                            text: qsTr("Preparing workspace profiles…")
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
                                    text: qsTr("Workspace profiles could not be loaded")
                                    font.weight: Typography.weightSemibold
                                    color: Colors.contentOnErrorContainer
                                }
                                Label {
                                    text: qsTr("The workspace configuration could not be verified. Check the installation and try again.")
                                    font.pixelSize: Typography.bodySmall.size
                                    color: Colors.contentOnErrorContainer
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                            MissionButton {
                                id: retryButton
                                objectName: "workspaceRetry"
                                variant: MissionButton.Variant.Secondary
                                text: qsTr("Retry")
                                onClicked: root.retryRequested()
                            }
                        }
                    }

                    // Success (workspace profile confirmed)
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
                                    text: qsTr("Workspace profile confirmed")
                                    font.weight: Typography.weightSemibold
                                    color: Colors.contentOnSuccessContainer
                                }
                                Label {
                                    text: qsTr("Your workspace profile will be applied — no reinstall is required, and you can change it later.")
                                    font.pixelSize: Typography.bodySmall.size
                                    color: Colors.contentOnSuccessContainer
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }

                    // Offline (informational — works fully offline)
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
                                    text: qsTr("Workspace profiles are configured locally — no account or internet connection is required.")
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
                        text: qsTr("Workspace Confirmation")
                        width: parent.width
                        font.pixelSize: Typography.headline.size
                        font.weight: Typography.headline.weight
                        color: MissionTheme.textPrimary
                        wrapMode: Text.Wrap
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    Label {
                        text: qsTr("Review or change the workspace profile selected for your system. Each profile sets your default applications, desktop layout, shortcuts, and recommended settings — profiles can be changed later without reinstalling Mission OS, and no profile installs unnecessary software.")
                        width: parent.width
                        font.pixelSize: Typography.bodyLarge.size
                        color: MissionTheme.textSecondary
                        wrapMode: Text.Wrap
                        lineHeight: Typography.lineHeightRelaxed
                    }

                    // ── Workspace profiles (single-select — the
                    //    reference's seven profiles, in order) ──
                    Label {
                        text: qsTr("Workspace profiles")
                        width: parent.width
                        font.pixelSize: Typography.subtitle.size
                        font.weight: Typography.subtitle.weight
                        color: MissionTheme.textPrimary
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    ListView {
                        id: profileList
                        objectName: "workspaceProfileList"
                        width: parent.width
                        // All rows visible by default; capped so the list
                        // never dominates short windows (scrolls inside).
                        // Math.max(0, …) guards a host-replaced empty
                        // profile fixture (no negative-height collapse).
                        height: Math.max(0, Math.min(root.workspaceProfiles.length * root.profileRowHeight
                                                     + (root.workspaceProfiles.length - 1) * Spacing.gapTiny,
                                                     396))
                        clip: true
                        model: root.workspaceProfiles
                        spacing: Spacing.gapTiny
                        activeFocusOnTab: true
                        keyNavigationWraps: true
                        highlightFollowsCurrentItem: true
                        ScrollIndicator.vertical: ScrollIndicator {}
                        onCountChanged: {
                            if (profileList.count > 0 && profileList.currentIndex < 0)
                                profileList.currentIndex = 0
                        }
                        Keys.onReturnPressed: root.selectProfile(profileList.currentIndex)
                        Keys.onSpacePressed: root.selectProfile(profileList.currentIndex)
                        Accessible.role: Accessible.List
                        Accessible.name: qsTr("Workspace profiles")

                        delegate: Rectangle {
                            id: profileDelegate
                            required property var modelData
                            required property int index

                            // When the list is reached via Tab, focus lands
                            // on the currentItem delegate — not on the
                            // ListView itself — so the delegate carries the
                            // objectName used by the keyboard-focus test.
                            objectName: "workspaceItem" + index
                            width: profileList.width
                            height: root.profileRowHeight
                            radius: Radii.input
                            color: {
                                if (root.selectedProfileIndex === index)
                                    return MissionTheme.darkMode ? MissionTheme.primary
                                                                 : MissionTheme.primaryContainer
                                if (profileList.currentIndex === index && profileList.activeFocus)
                                    return MissionTheme.surfaceVariant
                                if (profileDelegateMouse.containsMouse)
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
                                visible: profileList.currentIndex === index &&
                                         profileList.activeFocus
                            }

                            // Profile title + code on the first line, then
                            // the role line and the "changing the profile
                            // updates" list (reference § "Screen 17").
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
                                        color: root.selectedProfileIndex === index
                                             ? (MissionTheme.darkMode ? MissionTheme.contentOnPrimary
                                                                      : MissionTheme.contentOnPrimaryContainer)
                                             : MissionTheme.textPrimary
                                    }

                                    Label {
                                        text: modelData.code
                                        font.family: Typography.fontFamilyMono
                                        font.pixelSize: Typography.caption.size
                                        color: root.selectedProfileIndex === index
                                             ? (MissionTheme.darkMode ? MissionTheme.contentOnPrimary
                                                                      : MissionTheme.contentOnPrimaryContainer)
                                             : MissionTheme.textTertiary
                                    }
                                }

                                Label {
                                    text: modelData.role
                                    width: parent.width
                                    elide: Text.ElideRight
                                    font.pixelSize: Typography.bodySmall.size
                                    color: root.selectedProfileIndex === index
                                         ? (MissionTheme.darkMode ? MissionTheme.contentOnPrimary
                                                                  : MissionTheme.contentOnPrimaryContainer)
                                         : MissionTheme.textSecondary
                                }

                                Label {
                                    text: qsTr("Updates — %1").arg(modelData.configures)
                                    width: parent.width
                                    elide: Text.ElideRight
                                    font.pixelSize: Typography.caption.size
                                    color: root.selectedProfileIndex === index
                                         ? (MissionTheme.darkMode ? MissionTheme.contentOnPrimary
                                                                  : MissionTheme.contentOnPrimaryContainer)
                                         : MissionTheme.textTertiary
                                }
                            }

                            MouseArea {
                                id: profileDelegateMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    profileList.currentIndex = index
                                    root.selectProfile(index)
                                }
                            }

                            Accessible.role: Accessible.ListItem
                            Accessible.name: modelData.label + ", " + modelData.code
                            Accessible.description: modelData.role + ", " + modelData.configures
                            Accessible.selected: root.selectedProfileIndex === index
                        }
                    }

                    // ── Live selection feedback ──
                    Label {
                        id: selectionCaption
                        width: parent.width
                        visible: root.currentProfileCode.length > 0
                        text: qsTr("Selected: %1 · changes default applications, shortcuts, desktop layout, and recommended settings — no reinstall required").arg(root.currentProfileLabel)
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
                        text: qsTr("Your workspace profile tunes the environment to your workflow — default applications, desktop layout, shortcuts, and recommended settings. You can review it here, change it, or keep it as selected during installation.")
                        width: parent.width
                        font.pixelSize: Typography.bodySmall.size
                        color: MissionTheme.textSecondary
                        wrapMode: Text.Wrap
                        lineHeight: Typography.lineHeightNormal
                    }

                    Item { width: 1; height: Spacing.gapSmall }

                    Label {
                        text: qsTr("Profiles can be changed at any time after setup without reinstalling Mission OS, and no profile installs unnecessary software.")
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
                objectName: "workspaceBack"
                variant: MissionButton.Variant.Secondary
                text: qsTr("Back")
                enabled: root.step > 1
                onClicked: root.backRequested()
            }

            Item { Layout.fillWidth: true }

            // Continue (primary action; disabled while loading/error so it
            // never silently advances when validation is pending — a valid
            // profile is always selected, so no further gate applies on
            // this single-select screen)
            MissionButton {
                id: continueButton
                objectName: "workspaceContinue"
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
