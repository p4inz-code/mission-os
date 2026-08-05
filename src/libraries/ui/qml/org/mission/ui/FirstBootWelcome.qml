// Mission OS — First Boot Welcome (MOS-INS-014)
//
// Fourteenth screen of the Mission OS installer — step 14 of 17,
// appended after the completion screen (MOS-INS-012, step 13) as the
// first screen of the first-boot experience.
// Implements the source-defined First Boot Welcome structure
// (docs/wireframes/01_INSTALLER.md + docs/reference/01_INSTALLER.md
// § "Screen 16 — First Boot Welcome" + § "First Boot Principles"):
//
//   Hosting: place inside MissionWindow (or MissionPage) content and
//   anchor to fill, e.g.  MissionWindow { FirstBootWelcome { anchors.fill: parent } }
//   The component itself sizes to its implicit 1024x768 like MissionPage.
//
//   Header → Stepper Navigation → Main Content → Help Panel → Bottom actions
//
// Displayed items (per reference § "Screen 16 — First Boot Welcome"),
// exactly the seven listed items:
//   - Welcome to Mission OS   (heading)
//   - Installed version       (host-fed read-back)
//   - Build channel           (host-fed read-back)
//   - Quick introduction      (concise intro paragraph)
//   - Documentation link      (button → documentationRequested())
//   - Release notes           (button → releaseNotesRequested())
//   - Continue                (primary action)
//
// First Boot Principles (reference § "First Boot Principles") are
// respected: the screen is fast and requires minimal interaction (a
// single Continue); there are no unnecessary tutorials, no marketing
// content, and no mandatory sign-in; trust is reinforced through the
// privacy-by-default copy and the always-available documentation links.
//
// Interpretation notes (documented; no authoritative source specifies
// further detail):
//   - The screen is host-fed: the host wires the real installed version
//     and build channel into `version` / `buildType`; the header and the
//     read-back rows share the same properties so they can never drift
//     apart (the established pattern, e.g. Completion).
//   - The reference defines Continue explicitly. Per the wireframe UX
//     rules ("Back navigation always available", "Linear workflow") the
//     action bar carries Back (enabled past step 1; Escape → backRequested
//     like every non-terminal screen) and Continue. The host decides what
//     backRequested() means on this screen (e.g. returning to the login
//     screen).
//   - Documentation and Release notes are buttons that emit
//     documentationRequested() / releaseNotesRequested(); the host opens
//     the real documentation (offline where available) — the same
//     host-driven pattern as MOS-INS-001 Welcome.
//   - States follow the wireframe (empty · loading · error · success ·
//     offline). The screen exposes *Requested signals; no host/change
//     signal is emitted during initialization.
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

    /// Current installer step (1-based); this is step 14 of 17
    property int step: 14

    /// Total number of installer steps (screen registry: 16)
    property int totalSteps: 17

    /// Reduced motion (accessibility)
    property bool reducedMotion: false

    /// Installer/OS version string shown in the header
    property string version: "0.1.0"

    /// Build channel: Stable | Beta | Nightly
    property string buildType: "Nightly"

    /// The first-boot read-back details — the reference's display items
    /// 2–3 exactly (item 1, "Welcome to Mission OS", is the heading).
    /// Each entry: { code, label }. The values always mirror the public
    /// `version` / `buildType` properties (host-fed), so the header and
    /// the read-back rows can never drift apart.
    property var firstBootDetails: [
        { code: "version", label: "Installed version" },
        { code: "channel", label: "Build channel" }
    ]

    /// Number of read-back details (all are shown)
    property int firstBootDetailCount: root.firstBootDetails.length

    // ── Signals (host wiring) ──────────────────────────────────────
    /// User requested to continue to the next step
    signal continueRequested()
    /// User requested to go back to the previous step
    signal backRequested()
    /// User requested documentation
    signal documentationRequested()
    /// User requested release notes
    signal releaseNotesRequested()
    /// User requested to retry after an error
    signal retryRequested()

    // ── Escape navigates back (Master UX: Back always available) ──
    // No child on this screen consumes Escape (the read-back rows are
    // read-only), so root Escape always → backRequested.
    Keys.onEscapePressed: root.backRequested()

    // ── Responsive helpers ─────────────────────────────────────────
    readonly property bool wideLayout: root.width >= 760
    readonly property bool compactLayout: root.width < 640

    /// Height of one read-back row (label + value). Named once so the
    /// ListView height formula and the delegate height can never drift
    /// apart (established pattern).
    readonly property int detailRowHeight: 44

    // ── Read-back helpers (host wiring / tests) ────────────────────
    /// The detail object (from `firstBootDetails`) with `code`, or null.
    function getDetail(code) {
        for (var i = 0; i < root.firstBootDetails.length; ++i) {
            if (root.firstBootDetails[i].code === code)
                return root.firstBootDetails[i]
        }
        return null
    }

    // ── Test hooks (used by tests/tst_first_boot_welcome.qml) ──────
    property alias backgroundColor: backgroundRect.color
    property alias headingColor: headingLabel.color
    property alias headingLabel: headingLabel
    property alias introLabel: introLabel
    property alias detailList: detailList
    property alias helpPanel: helpPanel
    property alias backButton: backButton
    property alias continueButton: continueButton
    property alias documentationButton: documentationButton
    property alias releaseNotesButton: releaseNotesButton
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
                text: qsTr("Step %1 of %2 · First Boot").arg(root.step).arg(root.totalSteps)
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
                            text: qsTr("Preparing your first boot…")
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
                                    text: qsTr("First boot could not be prepared")
                                    font.weight: Typography.weightSemibold
                                    color: Colors.contentOnErrorContainer
                                }
                                Label {
                                    text: qsTr("The first-boot information could not be verified. Check the installation and try again.")
                                    font.pixelSize: Typography.bodySmall.size
                                    color: Colors.contentOnErrorContainer
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                            MissionButton {
                                id: retryButton
                                objectName: "firstbootRetry"
                                variant: MissionButton.Variant.Secondary
                                text: qsTr("Retry")
                                onClicked: root.retryRequested()
                            }
                        }
                    }

                    // Success (first-boot configuration confirmed)
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
                                    text: qsTr("Your system is ready")
                                    font.weight: Typography.weightSemibold
                                    color: Colors.contentOnSuccessContainer
                                }
                                Label {
                                    text: qsTr("Mission OS is installed and ready to use. Continue to finish the first-boot setup.")
                                    font.pixelSize: Typography.bodySmall.size
                                    color: Colors.contentOnSuccessContainer
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }

                    // Offline (informational — the installed system
                    // works fully offline)
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
                                    text: qsTr("Mission OS works fully offline — no account or internet connection is required. Documentation and release notes are available when you are online.")
                                    font.pixelSize: Typography.bodySmall.size
                                    color: MissionTheme.textSecondary
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }

                    // ── Heading (reference display item 1:
                    //    "Welcome to Mission OS") ──
                    Label {
                        id: headingLabel
                        text: qsTr("Welcome to Mission OS")
                        width: parent.width
                        font.pixelSize: Typography.headline.size
                        font.weight: Typography.headline.weight
                        color: MissionTheme.textPrimary
                        wrapMode: Text.Wrap
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    // ── Quick introduction (reference display item 4).
                    //    Kept concise per First Boot Principles: fast,
                    //    minimal interaction, no unnecessary tutorials. ──
                    Label {
                        id: introLabel
                        text: qsTr("Mission OS is installed and ready to use. This short welcome gets you started — you can change language, appearance, and accessibility options at any time from Settings, and no account or internet connection is required.")
                        width: parent.width
                        font.pixelSize: Typography.bodyLarge.size
                        color: MissionTheme.textSecondary
                        wrapMode: Text.Wrap
                        lineHeight: Typography.lineHeightRelaxed
                        Accessible.role: Accessible.StaticText
                        Accessible.name: text
                    }

                    // ── Installed version + Build channel (reference
                    //    display items 2–3; read-only — the host drives
                    //    the values via `version` / `buildType`) ──
                    ListView {
                        id: detailList
                        objectName: "firstbootDetailList"
                        width: parent.width
                        height: Math.max(0, root.firstBootDetails.length * root.detailRowHeight
                                         + (root.firstBootDetails.length - 1) * Spacing.gapTiny)
                        clip: true
                        model: root.firstBootDetails
                        spacing: Spacing.gapTiny
                        ScrollIndicator.vertical: ScrollIndicator {}
                        Accessible.role: Accessible.List
                        Accessible.name: qsTr("Installed system details")

                        delegate: Rectangle {
                            id: detailDelegate
                            required property var modelData
                            required property int index

                            // Read-only rows are not Tab stops; the
                            // objectName is used by the keyboard-focus
                            // test to verify they are NOT in the chain.
                            objectName: "firstbootDetailItem" + index
                            width: detailList.width
                            height: root.detailRowHeight
                            radius: Radii.input
                            color: MissionTheme.surface

                            // Test hook: expose the rendered value label
                            // so tests can verify the row reflects the
                            // public version/buildType properties.
                            property alias valueLabel: detailValueLabel

                            // Bottom hairline separator between rows
                            Rectangle {
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    bottom: parent.bottom
                                }
                                height: 1
                                color: MissionTheme.outlineVariant
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Spacing.paddingMedium
                                anchors.rightMargin: Spacing.paddingMedium
                                spacing: Spacing.gapMedium

                                // Detail label (left)
                                Label {
                                    text: modelData.label
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    font.pixelSize: Typography.body.size
                                    color: MissionTheme.textSecondary
                                    verticalAlignment: Text.AlignVCenter
                                }

                                // Detail value (right). Always mirrors
                                // the public properties so the header
                                // and the read-back can never drift.
                                Label {
                                    id: detailValueLabel
                                    text: modelData.code === "version" ? root.version
                                         : modelData.code === "channel" ? root.buildType
                                         : ""
                                    elide: Text.ElideRight
                                    font.pixelSize: Typography.body.size
                                    font.weight: Typography.weightSemibold
                                    color: MissionTheme.textPrimary
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }

                            Accessible.role: Accessible.ListItem
                            Accessible.name: qsTr("%1: %2").arg(modelData.label).arg(detailValueLabel.text)
                        }
                    }

                    // ── Documentation / Release notes (reference
                    //    display items 5–6; always reachable) ──
                    Row {
                        spacing: Spacing.gapMedium
                        MissionButton {
                            id: documentationButton
                            objectName: "firstbootDocumentation"
                            variant: MissionButton.Variant.Tertiary
                            text: qsTr("Documentation")
                            onClicked: root.documentationRequested()
                        }
                        MissionButton {
                            id: releaseNotesButton
                            objectName: "firstbootReleaseNotes"
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
                        text: qsTr("Welcome to your new system. Mission OS is ready to use — you can adjust language, appearance, and accessibility settings at any time from Settings, and your workspace profile can be changed without reinstalling.")
                        width: parent.width
                        font.pixelSize: Typography.bodySmall.size
                        color: MissionTheme.textSecondary
                        wrapMode: Text.Wrap
                        lineHeight: Typography.lineHeightNormal
                    }

                    Item { width: 1; height: Spacing.gapSmall }

                    Label {
                        text: qsTr("Documentation and release notes are available from this screen and from Mission Hub — no external search needed.")
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
                objectName: "firstbootBack"
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
                objectName: "firstbootContinue"
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
