// Mission OS — Installer User Account (MOS-INS-008)
//
// Eighth screen of the Mission OS installer.
// Implements the source-defined User Account structure (docs/wireframes/
// 01_INSTALLER.md + docs/design/03_SCREEN_REGISTRY.md MOS-INS-008
// "User Account" + docs/reference/01_INSTALLER.md Screen 10
// "User Account"):
//
//   Hosting: place inside MissionWindow (or MissionPage) content and
//   anchor to fill, e.g.  MissionWindow { UserAccount { anchors.fill: parent } }
//   The component itself sizes to its implicit 1024x768 like MissionPage.
//
//   Header → Stepper Navigation → Main Content → Help Panel → Bottom actions
//
// Displayed items (per reference Screen 10 "User Account"):
//   - Required information: Display name, Username, Computer name,
//     Password, Password confirmation (five labeled text fields).
//   - Optional: Profile picture, Automatic login, Require password
//     after sleep.
//   - The installer evaluates password strength in real time: the
//     strength meter + label update as the user types.
//   - Weak passwords generate warnings: a weak password shows an
//     explicit "Warning:" caption (non-color indicator) on the warning
//     token color. Per the reference, a weak password warns but does
//     not block continuing (validation requires a complete + matching
//     password, not a strong one).
//   - Back / Continue (wireframe UX rules: linear workflow, back always
//     available, validation before continuing).
//
// No online account is required — this is a fully local primary account
// (installer privacy requirements: "require no online account").
//
// Interpretation notes (documented, no authoritative source specifies
// further detail):
//   - "Profile picture": no File Picker component exists in the shipped
//     library, so the optional profile picture is a preset-avatar
//     selector reusing the established inline chip pattern (the same
//     approach the MOS-INS-003 kickoff documents for the unimplemented
//     Segmented Control). "None" is preselected (no avatar), non-emitting.
//   - Password strength heuristic: one point per criterion — length ≥ 8,
//     uppercase, lowercase, digit, symbol → 0-5. Level mapping: 1-2 weak,
//     3 fair, 4 good, 5 strong. This is a UI-only live heuristic; the
//     host enforces any real password policy when the account is created.
//   - Defaults follow the installer's "Security by default" /
//     "Privacy by default" objectives: Automatic login = off,
//     Require password after sleep = on, no avatar preselected change.
//     Neither default emits a host-change signal on load.
//
// States (per wireframe): empty · loading · error · success · offline
// The screen exposes *Requested signals; the host application decides
// what each action does (e.g. creating the account via accountsd).
//
// Design-system compliance:
//   - Tokens only (Colors, Typography, Spacing, Radii, Motion, MissionTheme)
//   - Light + dark themes via MissionTheme (driven by host)
//   - Keyboard navigation with visible focus states
//   - WCAG AA-oriented contrast, reduced-motion aware
//   - Responsive reflow per docs/design/14_RESPONSIVE_RULES.md
//   - Text fields are stock QtQuick.Controls.TextField styled inline
//     (Password Field is listed in docs/design/05_COMPONENT_LIBRARY.md
//     but not yet shipped — same inline pattern as the Keyboard test
//     area and the Privacy Setup Toggle Switch note).

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
    property int step: 8

    /// Total number of installer steps (screen registry: 12)
    property int totalSteps: 17

    /// Reduced motion (accessibility)
    property bool reducedMotion: false

    /// Installer/OS version string shown in the header
    property string version: "0.1.0"

    /// Build channel: Stable | Beta | Nightly
    property string buildType: "Nightly"

    // ── Required fields (reference Screen 10) ─────────────────────
    // Each property is bound to its field's text, so reading the
    // property always reflects the field and programmatic host wiring
    // goes through the field aliases (text fields fire *Requested only
    // on user edits — onTextEdited — never on load or programmatic set).
    /// Display name (e.g. "Alex Johnson")
    property string displayName: displayNameField.text
    /// Username (sign-in name, e.g. "alex")
    property string username: usernameField.text
    /// Computer name (how the computer appears on the network)
    property string computerName: computerNameField.text
    /// Password
    property string password: passwordField.text
    /// Password confirmation
    property string passwordConfirmation: passwordConfirmField.text

    // ── Optional settings (reference Screen 10) ────────────────────
    /// Automatic login (optional; off by default — privacy/security
    /// default, no signal emitted on load)
    property bool automaticLogin: false
    /// Require password after sleep (optional; on by default —
    /// "Security by default", no signal emitted on load)
    property bool requirePasswordAfterSleep: true

    /// Optional profile picture presets. Each entry: { code, label }.
    /// "None" is preselected on load (no avatar) without emitting —
    /// the host already knows the default. No File Picker component is
    /// shipped, so the profile picture is a preset-avatar selector
    /// reusing the established chip pattern (documented in the header).
    property var avatarOptions: [
        { code: "none", label: "None" },
        { code: "primary", label: "Blue" },
        { code: "secondary", label: "Violet" },
        { code: "success", label: "Green" },
        { code: "warning", label: "Amber" },
        { code: "error", label: "Red" }
    ]

    /// Index of the selected avatar within `avatarOptions` (0 = None)
    property int selectedAvatarIndex: 0

    /// The selected avatar code (e.g. "none", "primary", "success")
    property string profilePicture: root.avatarOptions.length > 0 ? root.avatarOptions[0].code : "none"

    /// Number of avatar presets (all are shown)
    property int avatarCount: root.avatarOptions.length

    // ── Validation (wireframe: validation before continuing) ───────
    /// Number of required fields (reference Screen 10: five)
    readonly property int requiredFieldCount: 5

    /// How many required fields currently hold a non-empty value
    readonly property int filledFieldCount: {
        var n = 0
        if (root.displayName.length > 0) n++
        if (root.username.length > 0) n++
        if (root.computerName.length > 0) n++
        if (root.password.length > 0) n++
        if (root.passwordConfirmation.length > 0) n++
        return n
    }

    /// Passwords match and are both non-empty
    readonly property bool passwordsMatch: root.password.length > 0 &&
                                           root.password === root.passwordConfirmation

    /// All five required fields are complete and the passwords match —
    /// the gate that enables Continue (weak passwords warn, they do not
    /// block — reference Screen 10).
    readonly property bool formComplete: root.filledFieldCount === root.requiredFieldCount &&
                                         root.passwordsMatch

    // ── Password strength (real-time evaluation, reference Screen 10) ──
    /// 0-5 heuristic score of the current password (see header note)
    property int passwordScore: root.passwordStrengthScore(root.password)

    /// 0 = no password, 1 = weak, 2 = fair, 3 = good, 4 = strong
    readonly property int passwordStrengthLevel: {
        var s = root.passwordScore
        if (s <= 0) return 0
        if (s <= 2) return 1
        if (s <= 3) return 2
        if (s <= 4) return 3
        return 4
    }

    /// Human-readable strength label ("Weak" | "Fair" | "Good" |
    /// "Strong", "" while the password is empty)
    readonly property string passwordStrengthLabel: {
        switch (root.passwordStrengthLevel) {
        case 1: return qsTr("Weak")
        case 2: return qsTr("Fair")
        case 3: return qsTr("Good")
        case 4: return qsTr("Strong")
        }
        return ""
    }

    /// True while a non-empty password is evaluated as weak — drives
    /// the explicit warning (reference: "Weak passwords should
    /// generate warnings").
    readonly property bool weakPassword: root.password.length > 0 &&
                                         root.passwordStrengthLevel === 1

    // ── Signals (host wiring) ──────────────────────────────────────
    /// User requested to continue to the next step
    signal continueRequested()
    /// User requested to go back to the previous step
    signal backRequested()
    /// The user changed a piece of account data (field name, e.g.
    /// "displayName", "username", "computerName", "password",
    /// "passwordConfirmation", "automaticLogin", "requirePasswordAfterSleep",
    /// "profilePicture", and the new value). Fired only on user
    /// interaction — never on load and never for programmatic field
    /// writes (text fields use onTextEdited).
    signal accountChangeRequested(string field, var value)
    /// User requested to retry after an error
    signal retryRequested()

    // ── Escape navigates back (Master UX: Back always available) ──
    // No child consumes Escape on this screen: the text fields have no
    // Escape handler (Tab leaves them) and the switches/chips handle
    // Space/Return only, so root Escape always → backRequested.
    Keys.onEscapePressed: root.backRequested()

    // ── Responsive helpers ─────────────────────────────────────────
    readonly property bool wideLayout: root.width >= 760
    readonly property bool compactLayout: root.width < 640

    // ── Password strength heuristic ────────────────────────────────
    /// Score a password 0-5 (one point per criterion: length ≥ 8,
    /// uppercase, lowercase, digit, symbol). UI-only live heuristic —
    /// the host enforces the real account password policy.
    function passwordStrengthScore(pwd) {
        if (!pwd || pwd.length === 0)
            return 0
        var score = 0
        if (pwd.length >= 8) score++
        if (pwd.match(/[A-Z]/)) score++
        if (pwd.match(/[a-z]/)) score++
        if (pwd.match(/[0-9]/)) score++
        if (pwd.match(/[^A-Za-z0-9]/)) score++
        return score
    }

    /// Color of one strength-meter segment (0-based index). Filled
    /// segments use the level color (weak/fair = warning, good =
    /// primary, strong = success); unfilled segments use surfaceDim.
    function strengthSegmentColor(index) {
        if (index >= root.passwordStrengthLevel)
            return MissionTheme.surfaceDim
        switch (root.passwordStrengthLevel) {
        case 1:
        case 2: return MissionTheme.warning
        case 3: return MissionTheme.primary
        case 4: return MissionTheme.success
        }
        return MissionTheme.surfaceDim
    }

    /// Color of an avatar preset (existing tokens only; "none" is
    /// transparent — the preview/chip renders an outline instead).
    function avatarColor(code) {
        switch (code) {
        case "primary":   return MissionTheme.primary
        case "secondary": return MissionTheme.secondary
        case "success":   return MissionTheme.success
        case "warning":   return MissionTheme.warning
        case "error":     return MissionTheme.error
        }
        return "transparent"
    }

    // ── Selection helpers ──────────────────────────────────────────
    /// Select the avatar preset at `index` (host wiring / tests).
    /// Emits accountChangeRequested("profilePicture", code) once.
    function selectAvatar(index) {
        if (index < 0 || index >= root.avatarOptions.length)
            return
        var option = root.avatarOptions[index]
        root.selectedAvatarIndex = index
        root.profilePicture = option.code
        root.accountChangeRequested("profilePicture", root.profilePicture)
    }

    /// Set the automatic-login switch (host wiring). Flipping the
    /// switch fires its onCheckedChanged exactly once, which syncs the
    /// property and emits the host-change signal (same contract as
    /// PrivacySetup.setOptionEnabled).
    function setAutomaticLogin(enabled) {
        if (autoLoginSwitch.checked !== enabled)
            autoLoginSwitch.checked = enabled
    }

    /// Set the require-password-after-sleep switch (host wiring).
    function setRequirePasswordAfterSleep(enabled) {
        if (sleepPasswordSwitch.checked !== enabled)
            sleepPasswordSwitch.checked = enabled
    }

    // ── Live feedback text (validation caption) ────────────────────
    readonly property string formCaptionText: {
        if (root.formComplete)
            return qsTr("All required fields are complete.")
        if (root.password.length > 0 && root.passwordConfirmation.length > 0 &&
                !root.passwordsMatch)
            return qsTr("Passwords do not match.")
        return qsTr("Required fields: %1 of %2 complete.").arg(root.filledFieldCount)
                                                          .arg(root.requiredFieldCount)
    }

    // ── Test hooks (used by tests/tst_user_account.qml) ────────────
    property alias backgroundColor: backgroundRect.color
    property alias headingColor: headingLabel.color
    property alias headingLabel: headingLabel
    property alias displayNameField: displayNameField
    property alias usernameField: usernameField
    property alias computerNameField: computerNameField
    property alias passwordField: passwordField
    property alias passwordConfirmField: passwordConfirmField
    property alias autoLoginSwitch: autoLoginSwitch
    property alias sleepPasswordSwitch: sleepPasswordSwitch
    property alias avatarRows: avatarRows
    property alias avatarPreview: avatarPreview
    property alias strengthLabel: strengthLabel
    property alias strengthSegments: strengthSegments
    property alias weakWarning: weakWarning
    property alias formCaption: formCaption
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
                text: qsTr("Step %1 of %2 · Account").arg(root.step).arg(root.totalSteps)
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
                            text: qsTr("Preparing account settings…")
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
                                    text: qsTr("Account settings could not be loaded")
                                    font.weight: Typography.weightSemibold
                                    color: Colors.contentOnErrorContainer
                                }
                                Label {
                                    text: qsTr("The account configuration could not be verified. Check the installation media and try again.")
                                    font.pixelSize: Typography.bodySmall.size
                                    color: Colors.contentOnErrorContainer
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                            MissionButton {
                                id: retryButton
                                objectName: "accountRetry"
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
                                    text: qsTr("Account details saved")
                                    font.weight: Typography.weightSemibold
                                    color: Colors.contentOnSuccessContainer
                                }
                                Label {
                                    text: qsTr("The local account will be created during installation.")
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
                                    text: qsTr("This step works without an internet connection. Your account is local to this device — no online account is required.")
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
                        text: qsTr("Create your user account")
                        width: parent.width
                        font.pixelSize: Typography.headline.size
                        font.weight: Typography.headline.weight
                        color: MissionTheme.textPrimary
                        wrapMode: Text.Wrap
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    Label {
                        text: qsTr("This is the primary local account for Mission OS — it is used to sign in and manage the system. Everything stays on this device: no online account or cloud service is required.")
                        width: parent.width
                        font.pixelSize: Typography.bodyLarge.size
                        color: MissionTheme.textSecondary
                        wrapMode: Text.Wrap
                        lineHeight: Typography.lineHeightRelaxed
                    }

                    // ── Required information (reference Screen 10) ──
                    Label {
                        text: qsTr("Required information")
                        width: parent.width
                        font.pixelSize: Typography.subtitle.size
                        font.weight: Typography.subtitle.weight
                        color: MissionTheme.textPrimary
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    GridLayout {
                        id: requiredGrid
                        width: parent.width
                        columns: root.wideLayout ? 2 : 1
                        columnSpacing: Spacing.gapLarge
                        rowSpacing: Spacing.gapMedium

                        // ── Display name ──
                        Column {
                            Layout.fillWidth: true
                            spacing: Spacing.gapTiny

                            Label {
                                text: qsTr("Display name")
                                font.pixelSize: Typography.bodySmall.size
                                font.weight: Typography.weightSemibold
                                color: MissionTheme.textPrimary
                            }
                            TextField {
                                id: displayNameField
                                objectName: "accountDisplayName"
                                width: parent.width
                                implicitHeight: Spacing.minimumTouchTarget
                                placeholderText: qsTr("e.g. Alex Johnson")
                                font.pixelSize: Typography.body.size
                                color: MissionTheme.textPrimary
                                placeholderTextColor: MissionTheme.textTertiary
                                selectByMouse: true
                                leftPadding: Spacing.paddingMedium
                                rightPadding: Spacing.paddingMedium
                                // User edits only — never fires on load
                                // or for programmatic `text` writes.
                                onTextEdited: root.accountChangeRequested("displayName", text)
                                background: Rectangle {
                                    radius: Radii.input
                                    color: MissionTheme.surface
                                    border.width: displayNameField.activeFocus ? 2 : 1
                                    border.color: displayNameField.activeFocus ? MissionTheme.focusRing : MissionTheme.outline
                                }
                                Accessible.role: Accessible.EditableText
                                Accessible.name: qsTr("Display name")
                            }
                        }

                        // ── Username ──
                        Column {
                            Layout.fillWidth: true
                            spacing: Spacing.gapTiny

                            Label {
                                text: qsTr("Username")
                                font.pixelSize: Typography.bodySmall.size
                                font.weight: Typography.weightSemibold
                                color: MissionTheme.textPrimary
                            }
                            TextField {
                                id: usernameField
                                objectName: "accountUsername"
                                width: parent.width
                                implicitHeight: Spacing.minimumTouchTarget
                                placeholderText: qsTr("e.g. alex")
                                font.pixelSize: Typography.body.size
                                color: MissionTheme.textPrimary
                                placeholderTextColor: MissionTheme.textTertiary
                                selectByMouse: true
                                leftPadding: Spacing.paddingMedium
                                rightPadding: Spacing.paddingMedium
                                onTextEdited: root.accountChangeRequested("username", text)
                                background: Rectangle {
                                    radius: Radii.input
                                    color: MissionTheme.surface
                                    border.width: usernameField.activeFocus ? 2 : 1
                                    border.color: usernameField.activeFocus ? MissionTheme.focusRing : MissionTheme.outline
                                }
                                Accessible.role: Accessible.EditableText
                                Accessible.name: qsTr("Username")
                                Accessible.description: qsTr("The name you use to sign in to Mission OS")
                            }

                            Label {
                                text: qsTr("Used to sign in to this computer.")
                                width: parent.width
                                font.pixelSize: Typography.caption.size
                                color: MissionTheme.textTertiary
                                wrapMode: Text.Wrap
                            }
                        }

                        // ── Computer name (full width) ──
                        Column {
                            Layout.fillWidth: true
                            Layout.columnSpan: root.wideLayout ? 2 : 1
                            spacing: Spacing.gapTiny

                            Label {
                                text: qsTr("Computer name")
                                font.pixelSize: Typography.bodySmall.size
                                font.weight: Typography.weightSemibold
                                color: MissionTheme.textPrimary
                            }
                            TextField {
                                id: computerNameField
                                objectName: "accountComputerName"
                                width: parent.width
                                implicitHeight: Spacing.minimumTouchTarget
                                placeholderText: qsTr("e.g. alex-pc")
                                font.pixelSize: Typography.body.size
                                color: MissionTheme.textPrimary
                                placeholderTextColor: MissionTheme.textTertiary
                                selectByMouse: true
                                leftPadding: Spacing.paddingMedium
                                rightPadding: Spacing.paddingMedium
                                onTextEdited: root.accountChangeRequested("computerName", text)
                                background: Rectangle {
                                    radius: Radii.input
                                    color: MissionTheme.surface
                                    border.width: computerNameField.activeFocus ? 2 : 1
                                    border.color: computerNameField.activeFocus ? MissionTheme.focusRing : MissionTheme.outline
                                }
                                Accessible.role: Accessible.EditableText
                                Accessible.name: qsTr("Computer name")
                                Accessible.description: qsTr("How this computer appears on the network")
                            }
                        }

                        // ── Password ──
                        Column {
                            Layout.fillWidth: true
                            spacing: Spacing.gapTiny

                            Label {
                                text: qsTr("Password")
                                font.pixelSize: Typography.bodySmall.size
                                font.weight: Typography.weightSemibold
                                color: MissionTheme.textPrimary
                            }
                            TextField {
                                id: passwordField
                                objectName: "accountPassword"
                                width: parent.width
                                implicitHeight: Spacing.minimumTouchTarget
                                echoMode: TextInput.Password
                                placeholderText: qsTr("Enter a password")
                                font.pixelSize: Typography.body.size
                                color: MissionTheme.textPrimary
                                placeholderTextColor: MissionTheme.textTertiary
                                selectByMouse: true
                                leftPadding: Spacing.paddingMedium
                                rightPadding: Spacing.paddingMedium
                                onTextEdited: root.accountChangeRequested("password", text)
                                background: Rectangle {
                                    radius: Radii.input
                                    color: MissionTheme.surface
                                    border.width: passwordField.activeFocus ? 2 : 1
                                    border.color: passwordField.activeFocus ? MissionTheme.focusRing : MissionTheme.outline
                                }
                                Accessible.role: Accessible.EditableText
                                Accessible.name: qsTr("Password")
                            }
                        }

                        // ── Password confirmation ──
                        Column {
                            Layout.fillWidth: true
                            spacing: Spacing.gapTiny

                            Label {
                                text: qsTr("Password confirmation")
                                font.pixelSize: Typography.bodySmall.size
                                font.weight: Typography.weightSemibold
                                color: MissionTheme.textPrimary
                            }
                            TextField {
                                id: passwordConfirmField
                                objectName: "accountPasswordConfirm"
                                width: parent.width
                                implicitHeight: Spacing.minimumTouchTarget
                                echoMode: TextInput.Password
                                placeholderText: qsTr("Re-enter your password")
                                font.pixelSize: Typography.body.size
                                color: MissionTheme.textPrimary
                                placeholderTextColor: MissionTheme.textTertiary
                                selectByMouse: true
                                leftPadding: Spacing.paddingMedium
                                rightPadding: Spacing.paddingMedium
                                onTextEdited: root.accountChangeRequested("passwordConfirmation", text)
                                background: Rectangle {
                                    radius: Radii.input
                                    color: MissionTheme.surface
                                    border.width: passwordConfirmField.activeFocus ? 2 : 1
                                    border.color: passwordConfirmField.activeFocus ? MissionTheme.focusRing : MissionTheme.outline
                                }
                                Accessible.role: Accessible.EditableText
                                Accessible.name: qsTr("Password confirmation")
                            }
                        }

                        // ── Password strength (real time) ──
                        Column {
                            Layout.fillWidth: true
                            Layout.columnSpan: root.wideLayout ? 2 : 1
                            spacing: Spacing.gapTiny

                            RowLayout {
                                width: parent.width
                                spacing: Spacing.gapMedium

                                Label {
                                    text: qsTr("Password strength")
                                    font.pixelSize: Typography.bodySmall.size
                                    font.weight: Typography.weightSemibold
                                    color: MissionTheme.textPrimary
                                }
                                Item { Layout.fillWidth: true }
                                Label {
                                    id: strengthLabel
                                    text: root.passwordStrengthLabel
                                    font.pixelSize: Typography.bodySmall.size
                                    font.weight: Typography.weightSemibold
                                    color: {
                                        if (root.passwordStrengthLevel === 1 || root.passwordStrengthLevel === 2)
                                            return MissionTheme.warning
                                        if (root.passwordStrengthLevel === 3)
                                            return MissionTheme.primary
                                        if (root.passwordStrengthLevel === 4)
                                            return MissionTheme.success
                                        return MissionTheme.textTertiary
                                    }
                                }
                            }

                            // 4-segment live meter (Repeater aliased so
                            // tests can inspect the real segment colors)
                            Row {
                                id: strengthRow
                                spacing: Spacing.gapTiny
                                Repeater {
                                    id: strengthSegments
                                    model: 4
                                    delegate: Rectangle {
                                        width: 20
                                        height: 6
                                        radius: 3
                                        color: root.strengthSegmentColor(index)
                                    }
                                }
                            }

                            // Explicit weak-password warning (reference
                            // Screen 10: "Weak passwords should generate
                            // warnings"). Wording + warning color — not
                            // color alone (color-blind friendly).
                            Label {
                                id: weakWarning
                                visible: root.weakPassword
                                width: parent.width
                                text: qsTr("Warning: this password is weak. Use at least 8 characters with a mix of letters, numbers, and symbols.")
                                font.pixelSize: Typography.bodySmall.size
                                font.weight: Typography.weightSemibold
                                color: MissionTheme.warning
                                wrapMode: Text.Wrap
                                lineHeight: Typography.lineHeightNormal
                                Accessible.role: Accessible.StaticText
                                Accessible.name: text
                            }
                        }
                    }

                    // ── Optional (reference Screen 10) ──
                    Label {
                        text: qsTr("Optional")
                        width: parent.width
                        font.pixelSize: Typography.subtitle.size
                        font.weight: Typography.subtitle.weight
                        color: MissionTheme.textPrimary
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    // ── Profile picture (preset avatars; no File Picker
                    //    component is shipped — chip pattern, see header) ──
                    RowLayout {
                        width: parent.width
                        spacing: Spacing.gapMedium

                        // Live preview of the selected avatar
                        Rectangle {
                            id: avatarPreview
                            Layout.preferredWidth: 40
                            Layout.preferredHeight: 40
                            radius: 20
                            color: root.avatarColor(root.profilePicture)
                            border.width: root.profilePicture === "none" ? 1 : 0
                            border.color: MissionTheme.outline
                            Rectangle {
                                anchors.centerIn: parent
                                width: 14
                                height: 14
                                radius: 7
                                color: "transparent"
                                border.width: 2
                                border.color: root.profilePicture === "none"
                                             ? MissionTheme.outline
                                             : MissionTheme.contentOnPrimary
                            }
                            Accessible.role: Accessible.Graphic
                            Accessible.name: qsTr("Profile picture preview")
                        }

                        Column {
                            Layout.fillWidth: true
                            spacing: Spacing.gapTiny
                            Label {
                                text: qsTr("Profile picture")
                                font.pixelSize: Typography.bodySmall.size
                                font.weight: Typography.weightSemibold
                                color: MissionTheme.textPrimary
                            }
                            Label {
                                text: qsTr("Optional — choose a preset avatar or keep none. You can change it later after installation.")
                                width: parent.width
                                font.pixelSize: Typography.caption.size
                                color: MissionTheme.textTertiary
                                wrapMode: Text.Wrap
                            }
                        }
                    }

                    // Avatar preset chips (None preselected, non-emitting)
                    Flow {
                        width: parent.width
                        spacing: Spacing.gapSmall

                        Repeater {
                            id: avatarRows
                            model: root.avatarOptions

                            delegate: Rectangle {
                                id: avatarChip
                                required property var modelData
                                required property int index

                                objectName: "accountAvatarItem" + index
                                height: Spacing.minimumTouchTarget
                                width: avatarChipRow.implicitWidth + Spacing.paddingMedium * 2
                                radius: Radii.chip
                                color: index === root.selectedAvatarIndex
                                     ? (MissionTheme.darkMode ? MissionTheme.primary
                                                             : MissionTheme.primaryContainer)
                                     : (avatarChipMouse.containsMouse ? MissionTheme.surfaceVariant
                                                                     : MissionTheme.surface)
                                border.width: index === root.selectedAvatarIndex ? 0 : 1
                                border.color: MissionTheme.outline
                                activeFocusOnTab: true

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
                                    radius: Radii.chip + 2
                                    color: "transparent"
                                    border.color: MissionTheme.focusRing
                                    border.width: 2
                                    visible: avatarChip.activeFocus
                                }

                                RowLayout {
                                    id: avatarChipRow
                                    anchors.centerIn: parent
                                    spacing: Spacing.gapSmall

                                    // Color swatch (token colors; "none"
                                    // renders as an outlined empty dot)
                                    Rectangle {
                                        Layout.preferredWidth: 16
                                        Layout.preferredHeight: 16
                                        radius: 8
                                        color: root.avatarColor(modelData.code)
                                        border.width: modelData.code === "none" ? 1 : 0
                                        border.color: MissionTheme.outline
                                    }

                                    Label {
                                        text: modelData.label
                                        font.pixelSize: Typography.bodySmall.size
                                        font.weight: index === root.selectedAvatarIndex
                                                     ? Typography.weightSemibold : Typography.weightRegular
                                        color: index === root.selectedAvatarIndex
                                             ? (MissionTheme.darkMode ? MissionTheme.contentOnPrimary
                                                                     : MissionTheme.contentOnPrimaryContainer)
                                             : MissionTheme.textPrimary
                                    }
                                }

                                MouseArea {
                                    id: avatarChipMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: root.selectAvatar(index)
                                }

                                Keys.onReturnPressed: root.selectAvatar(index)
                                Keys.onSpacePressed: root.selectAvatar(index)

                                Accessible.role: Accessible.RadioButton
                                Accessible.name: modelData.label
                                Accessible.checked: index === root.selectedAvatarIndex
                            }
                        }
                    }

                    // ── Automatic login (optional; off by default) ──
                    Rectangle {
                        id: autoLoginCard
                        width: parent.width
                        radius: Radii.card
                        color: MissionTheme.surface
                        border.color: MissionTheme.outlineVariant
                        border.width: 1
                        // Explicit height from content (the proven
                        // pattern — a plain layout would otherwise
                        // collapse the card to 0 height).
                        height: autoLoginColumn.height + Spacing.paddingMedium * 2

                        Column {
                            id: autoLoginColumn
                            x: Spacing.paddingMedium
                            y: Spacing.paddingMedium
                            width: parent.width - Spacing.paddingMedium * 2
                            spacing: Spacing.gapSmall

                            RowLayout {
                                width: parent.width
                                spacing: Spacing.gapMedium

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Spacing.gapTiny
                                    Label {
                                        text: qsTr("Automatic login")
                                        font.pixelSize: Typography.subtitle.size
                                        font.weight: Typography.subtitle.weight
                                        color: MissionTheme.textPrimary
                                    }
                                    Label {
                                        text: qsTr("Optional — sign in automatically when this computer starts. Off by default for your security and privacy.")
                                        width: parent.width
                                        font.pixelSize: Typography.bodySmall.size
                                        color: MissionTheme.textSecondary
                                        wrapMode: Text.Wrap
                                        lineHeight: Typography.lineHeightNormal
                                    }
                                }

                                // Stock Switch styled with tokens
                                // (Toggle Switch component not yet
                                // shipped — inline pattern, same as
                                // PrivacySetup).
                                Switch {
                                    id: autoLoginSwitch
                                    objectName: "accountAutoLogin"
                                    // No binding on checked so the
                                    // host helpers can flip it without
                                    // breaking one (PrivacySetup
                                    // pattern).
                                    Layout.preferredHeight: Spacing.minimumTouchTarget
                                    Layout.preferredWidth: 64
                                    Layout.alignment: Qt.AlignVCenter

                                    // Fires on every `checked` change —
                                    // user interaction AND programmatic
                                    // host assignment (verified
                                    // empirically in PrivacySetup).
                                    onCheckedChanged: {
                                        root.automaticLogin = checked
                                        root.accountChangeRequested("automaticLogin", checked)
                                    }

                                    indicator: Rectangle {
                                        id: autoLoginTrack
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: autoLoginSwitch.width - width - 4
                                        width: 44
                                        height: 24
                                        radius: 12
                                        color: autoLoginSwitch.checked
                                             ? MissionTheme.primary
                                             : (autoLoginSwitch.hovered
                                                ? MissionTheme.outline
                                                : MissionTheme.surfaceDim)
                                        // Unchecked state: 1px outline so the
                                        // track stays visible on the card.
                                        border.width: autoLoginSwitch.checked ? 0 : 1
                                        border.color: MissionTheme.outline

                                        Behavior on color {
                                            enabled: !root.reducedMotion
                                            animation: ColorAnimation { duration: Motion.colorChange }
                                        }

                                        // Visible focus ring (keyboard)
                                        Rectangle {
                                            anchors.fill: parent
                                            anchors.margins: -3
                                            radius: 15
                                            color: "transparent"
                                            border.color: MissionTheme.focusRing
                                            border.width: 2
                                            visible: autoLoginSwitch.activeFocus
                                        }

                                        // Knob
                                        Rectangle {
                                            x: autoLoginSwitch.checked
                                               ? parent.width - width - 3
                                               : 3
                                            width: 18
                                            height: 18
                                            radius: 9
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: autoLoginSwitch.checked
                                                 ? MissionTheme.contentOnPrimary
                                                 : MissionTheme.textSecondary

                                            Behavior on x {
                                                enabled: !root.reducedMotion
                                                NumberAnimation { duration: Motion.durationFast }
                                            }
                                        }
                                    }

                                    Accessible.role: Accessible.CheckBox
                                    Accessible.name: qsTr("Automatic login")
                                    Accessible.checked: autoLoginSwitch.checked
                                }
                            }
                        }
                    }

                    // ── Require password after sleep (on by default) ──
                    Rectangle {
                        id: sleepPasswordCard
                        width: parent.width
                        radius: Radii.card
                        color: MissionTheme.surface
                        border.color: MissionTheme.outlineVariant
                        border.width: 1
                        height: sleepPasswordColumn.height + Spacing.paddingMedium * 2

                        Column {
                            id: sleepPasswordColumn
                            x: Spacing.paddingMedium
                            y: Spacing.paddingMedium
                            width: parent.width - Spacing.paddingMedium * 2
                            spacing: Spacing.gapSmall

                            RowLayout {
                                width: parent.width
                                spacing: Spacing.gapMedium

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Spacing.gapTiny
                                    Label {
                                        text: qsTr("Require password after sleep")
                                        font.pixelSize: Typography.subtitle.size
                                        font.weight: Typography.subtitle.weight
                                        color: MissionTheme.textPrimary
                                    }
                                    Label {
                                        text: qsTr("Optional — keeps your account locked when the computer wakes. On by default (security by default).")
                                        width: parent.width
                                        font.pixelSize: Typography.bodySmall.size
                                        color: MissionTheme.textSecondary
                                        wrapMode: Text.Wrap
                                        lineHeight: Typography.lineHeightNormal
                                    }
                                }

                                Switch {
                                    id: sleepPasswordSwitch
                                    objectName: "accountSleepPassword"
                                    checked: true
                                    Layout.preferredHeight: Spacing.minimumTouchTarget
                                    Layout.preferredWidth: 64
                                    Layout.alignment: Qt.AlignVCenter

                                    onCheckedChanged: {
                                        root.requirePasswordAfterSleep = checked
                                        root.accountChangeRequested("requirePasswordAfterSleep", checked)
                                    }

                                    indicator: Rectangle {
                                        id: sleepPasswordTrack
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: sleepPasswordSwitch.width - width - 4
                                        width: 44
                                        height: 24
                                        radius: 12
                                        color: sleepPasswordSwitch.checked
                                             ? MissionTheme.primary
                                             : (sleepPasswordSwitch.hovered
                                                ? MissionTheme.outline
                                                : MissionTheme.surfaceDim)
                                        border.width: sleepPasswordSwitch.checked ? 0 : 1
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
                                            visible: sleepPasswordSwitch.activeFocus
                                        }

                                        Rectangle {
                                            x: sleepPasswordSwitch.checked
                                               ? parent.width - width - 3
                                               : 3
                                            width: 18
                                            height: 18
                                            radius: 9
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: sleepPasswordSwitch.checked
                                                 ? MissionTheme.contentOnPrimary
                                                 : MissionTheme.textSecondary

                                            Behavior on x {
                                                enabled: !root.reducedMotion
                                                NumberAnimation { duration: Motion.durationFast }
                                            }
                                        }
                                    }

                                    Accessible.role: Accessible.CheckBox
                                    Accessible.name: qsTr("Require password after sleep")
                                    Accessible.checked: sleepPasswordSwitch.checked
                                }
                            }
                        }
                    }

                    // ── Live validation feedback ──
                    Label {
                        id: formCaption
                        width: parent.width
                        text: root.formCaptionText
                        font.pixelSize: Typography.caption.size
                        color: root.formComplete ? MissionTheme.success
                                                 : MissionTheme.textTertiary
                        wrapMode: Text.Wrap
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
                        text: qsTr("Mission OS creates one local account on this device. No online account, telemetry, or cloud service is required — everything you enter stays here.")
                        width: parent.width
                        font.pixelSize: Typography.bodySmall.size
                        color: MissionTheme.textSecondary
                        wrapMode: Text.Wrap
                        lineHeight: Typography.lineHeightNormal
                    }

                    Item { width: 1; height: Spacing.gapSmall }

                    Label {
                        text: qsTr("Password strength is checked as you type. A weak password shows a warning — add length, numbers, and symbols to strengthen it.")
                        width: parent.width
                        font.pixelSize: Typography.bodySmall.size
                        color: MissionTheme.textSecondary
                        wrapMode: Text.Wrap
                        lineHeight: Typography.lineHeightNormal
                    }

                    Item { width: 1; height: Spacing.gapSmall }

                    Label {
                        text: qsTr("Security by default: Mission OS requires your password after sleep. Automatic login is off by default and can be changed later in Settings → Accounts.")
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
                objectName: "accountBack"
                variant: MissionButton.Variant.Secondary
                text: qsTr("Back")
                enabled: root.step > 1
                onClicked: root.backRequested()
            }

            Item { Layout.fillWidth: true }

            // Continue (primary action). Disabled until every required
            // field is complete and the passwords match (validation
            // before continuing — wireframe UX rules) and while
            // loading/error so it never advances when validation is
            // pending. A weak password warns but does not block
            // (reference Screen 10).
            MissionButton {
                id: continueButton
                objectName: "accountContinue"
                variant: MissionButton.Variant.Primary
                text: qsTr("Continue")
                loading: root.screenState === "loading"
                enabled: root.formComplete &&
                         root.screenState !== "loading" &&
                         root.screenState !== "error"
                onClicked: root.continueRequested()
                focus: true
            }
        }
    }
}
