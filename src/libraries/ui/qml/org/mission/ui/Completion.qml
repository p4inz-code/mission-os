// Mission OS — Installer Completion (MOS-INS-012)
//
// Twelfth screen of the Mission OS installer — the final installation
// screen, now step 13 of 17 after MOS-INS-013 Security Options was
// added between Encryption and Summary (the first-boot screens
// MOS-INS-014→016 follow after it).
// Implements the source-defined Completion structure (docs/wireframes/
// 01_INSTALLER.md + docs/design/03_SCREEN_REGISTRY.md MOS-INS-012
// "Completion" + docs/reference/01_INSTALLER.md § "Screen 15 —
// Installation Complete"):
//
//   Hosting: place inside MissionWindow (or MissionPage) content and
//   anchor to fill, e.g.  MissionWindow { Completion { anchors.fill: parent } }
//   The component itself sizes to its implicit 1024x768 like MissionPage.
//
//   Header → Stepper Navigation → Main Content → Help Panel → Bottom actions
//
// Displayed items (per reference § "Screen 15 — Installation Complete"),
// exactly the five listed items:
//   - Installation successful  (heading)
//   - Installed version
//   - Build channel
//   - Installation duration
//   - Disk usage summary
//
// Available actions (per reference § "Screen 15"), exactly the five
// listed actions — each exposed as a *Requested signal the host wires to
// the real system operation (reboot, live session, report export):
//   - Restart now
//   - Continue in Live Mode
//   - View installation report
//   - Export installation log
//   - Shut down
//
// The reference also states: "If installation media must be removed
// before reboot, the user should receive a clear prompt." — a warning
// note is rendered whenever `requiresMediaRemoval` is true (the host
// sets it when Mission OS was installed from removable media).
//
// Interpretation notes (documented; no authoritative source specifies
// further detail):
//   - This is the terminal screen of the installer: installation is
//     complete, so there is no Back and no Continue (the reference
//     defines exactly the five completion actions; the wireframe's
//     generic "Back / Continue" shell layout is a template, and
//     backing out of a finished installation is meaningless). Escape
//     therefore has no mapping on this screen — the host controls the
//     exit paths through the five actions above.
//   - The screen is host-fed: the host wires the real values into
//     `completionDetails` (replace the model or use setDetailValue()
//     per detail). The defaults shown on load mirror the established
//     version/build channel and neutral "—" placeholders; the host
//     fills the real installation duration and disk usage summary.
//   - The four detail rows mirror the reference's display items 2–5
//     verbatim (Installed version, Build channel, Installation
//     duration, Disk usage summary); the "Installation successful"
//     item is the heading itself.
//   - The installation report's contents (installation date, installer
//     version, operating system version, hardware summary, selected
//     options, encryption status, recovery configuration, verification
//     results — reference § "Installation Report") are surfaced
//     through the View/Export report actions; the report itself is
//     host-side and is not rendered inline on this screen.
//   - The action buttons are always enabled: the completion screen only
//     exists after a successful installation, and the reference does
//     not gate the five available actions.
//
// States (per wireframe): empty · loading · error · success · offline
// The screen exposes *Requested signals; the host application decides
// what each action does. No host/change signal is emitted during
// initialization.
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

    /// Current installer step (1-based); this is the final step (13 of 17)
    property int step: 13

    /// Total number of installer steps (screen registry: 16)
    property int totalSteps: 17

    /// Reduced motion (accessibility)
    property bool reducedMotion: false

    /// Installer/OS version string shown in the header
    property string version: "0.1.0"

    /// Build channel: Stable | Beta | Nightly
    property string buildType: "Nightly"

    /// Whether Mission OS was installed from removable media — when
    /// true, a clear prompt reminds the user to remove the media
    /// before restarting (reference § "Screen 15": "If installation
    /// media must be removed before reboot, the user should receive a
    /// clear prompt.")
    property bool requiresMediaRemoval: false

    /// The completion details — the reference's display items 2–5
    /// exactly (item 1, "Installation successful", is the heading).
    /// Each entry: { code, label, value }. Static fixture the host may
    /// replace wholesale or update via setDetailValue(); the defaults
    /// mirror the established version/build channel and neutral "—"
    /// placeholders for the host-fed duration and disk usage.
    property var completionDetails: [
        { code: "version",  label: "Installed version",      value: "0.1.0" },
        { code: "channel",  label: "Build channel",          value: "Nightly" },
        { code: "duration", label: "Installation duration",  value: "—" },
        { code: "storage",  label: "Disk usage summary",     value: "—" }
    ]

    /// Number of completion details (all are shown)
    property int completionDetailCount: root.completionDetails.length

    // ── Signals (host wiring) ──────────────────────────────────────
    /// User requested to restart the computer into the installed system
    signal restartRequested()
    /// User requested to continue in live mode (stay on the media
    /// without installing further)
    signal continueLiveRequested()
    /// User requested to view the installation report
    signal viewReportRequested()
    /// User requested to export the installation log
    signal exportLogRequested()
    /// User requested to shut down the computer
    signal shutdownRequested()
    /// User requested to retry after an error
    signal retryRequested()

    // ── Responsive helpers ─────────────────────────────────────────
    readonly property bool wideLayout: root.width >= 760
    readonly property bool compactLayout: root.width < 640

    /// Height of one detail row (label + value). Named once so the
    /// ListView height formula and the delegate height can never drift
    /// apart (established pattern).
    readonly property int detailRowHeight: 44

    // ── Detail helpers (host wiring / tests) ───────────────────────
    /// Index of the detail with `code` within `completionDetails`,
    /// or -1 when no such detail exists.
    function detailIndex(code) {
        for (var i = 0; i < root.completionDetails.length; ++i) {
            if (root.completionDetails[i].code === code)
                return i
        }
        return -1
    }

    /// The detail object (from `completionDetails`) with `code`, or null.
    function getDetail(code) {
        var i = root.detailIndex(code)
        return i >= 0 ? root.completionDetails[i] : null
    }

    /// Host wiring: update the value of the detail identified by
    /// `code` without replacing the whole model. The model is
    /// reassigned (slice copy of the same detail objects) so the
    /// rendered rows re-evaluate. Unknown codes are ignored.
    function setDetailValue(code, value) {
        var i = root.detailIndex(code)
        if (i < 0)
            return
        var details = root.completionDetails
        details[i].value = value
        root.completionDetails = details.slice()
    }

    // ── Test hooks (used by a future tst_completion.qml) ───────────
    property alias backgroundColor: backgroundRect.color
    property alias headingColor: headingLabel.color
    property alias headingLabel: headingLabel
    property alias detailList: detailList
    property alias mediaNote: mediaNote
    property alias helpPanel: helpPanel
    property alias restartButton: restartButton
    property alias continueLiveButton: continueLiveButton
    property alias viewReportButton: viewReportButton
    property alias exportLogButton: exportLogButton
    property alias shutdownButton: shutdownButton
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
                text: qsTr("Step %1 of %2 · Completion").arg(root.step).arg(root.totalSteps)
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
                            text: qsTr("Preparing completion details…")
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
                                    text: qsTr("Completion details could not be loaded")
                                    font.weight: Typography.weightSemibold
                                    color: Colors.contentOnErrorContainer
                                }
                                Label {
                                    text: qsTr("The installation report could not be verified. Check the installation media and try again.")
                                    font.pixelSize: Typography.bodySmall.size
                                    color: Colors.contentOnErrorContainer
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                            MissionButton {
                                id: retryButton
                                objectName: "completionRetry"
                                variant: MissionButton.Variant.Secondary
                                text: qsTr("Retry")
                                onClicked: root.retryRequested()
                            }
                        }
                    }

                    // Success (verification confirmed — the completion
                    // screen itself already shows a successful
                    // installation; this banner confirms verification)
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
                                    text: qsTr("Installation verified")
                                    font.weight: Typography.weightSemibold
                                    color: Colors.contentOnSuccessContainer
                                }
                                Label {
                                    text: qsTr("Mission OS was installed and verified successfully. Choose how to continue below.")
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
                                    text: qsTr("Mission OS is installed and works fully offline — no account or internet connection is required.")
                                    font.pixelSize: Typography.bodySmall.size
                                    color: MissionTheme.textSecondary
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }

                    // ── Heading (reference display item 1:
                    //    "Installation successful") ──
                    Label {
                        id: headingLabel
                        text: qsTr("Installation successful")
                        width: parent.width
                        font.pixelSize: Typography.headline.size
                        font.weight: Typography.headline.weight
                        color: MissionTheme.textPrimary
                        wrapMode: Text.Wrap
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    Label {
                        text: qsTr("Mission OS was installed, verified, and is ready to use. Choose how to continue below.")
                        width: parent.width
                        font.pixelSize: Typography.bodyLarge.size
                        color: MissionTheme.textSecondary
                        wrapMode: Text.Wrap
                        lineHeight: Typography.lineHeightRelaxed
                    }

                    // ── Completion details (reference display items
                    //    2–5; read-only — the host drives the values) ──
                    ListView {
                        id: detailList
                        objectName: "completionDetailList"
                        width: parent.width
                        height: Math.max(0, root.completionDetails.length * root.detailRowHeight
                                         + (root.completionDetails.length - 1) * Spacing.gapTiny)
                        clip: true
                        model: root.completionDetails
                        spacing: Spacing.gapTiny
                        ScrollIndicator.vertical: ScrollIndicator {}
                        Accessible.role: Accessible.List
                        Accessible.name: qsTr("Installation completion details")

                        delegate: Rectangle {
                            id: detailDelegate
                            required property var modelData
                            required property int index

                            // Read-only rows are not Tab stops; the
                            // objectName is used by future keyboard-focus
                            // tests to verify they are NOT in the chain.
                            objectName: "completionDetailItem" + index
                            width: detailList.width
                            height: root.detailRowHeight
                            radius: Radii.input
                            color: MissionTheme.surface

                            // Test hook: expose the rendered value label so
                            // tests can verify the row reflects host/API
                            // updates (same pattern as the Summary rows).
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

                                // Detail value (right). The version and
                                // channel rows always mirror the public
                                // properties so the header and the summary
                                // can never drift apart; the remaining
                                // rows are host-fed via setDetailValue().
                                Label {
                                    id: detailValueLabel
                                    text: modelData.code === "version" ? root.version
                                         : modelData.code === "channel" ? root.buildType
                                         : modelData.value
                                    elide: Text.ElideRight
                                    font.pixelSize: Typography.body.size
                                    font.weight: Typography.weightSemibold
                                    color: MissionTheme.textPrimary
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }

                            Accessible.role: Accessible.ListItem
                            // Announce exactly what is rendered — the
                            // version/channel rows mirror the public
                            // properties, so the name follows the label.
                            Accessible.name: qsTr("%1: %2").arg(modelData.label).arg(detailValueLabel.text)
                        }
                    }

                    // ── Clear prompt when removable media must be
                    //    removed before reboot (reference § "Screen 15") ──
                    Rectangle {
                        id: mediaNote
                        visible: root.requiresMediaRemoval
                        width: parent.width
                        height: mediaLayout.implicitHeight + Spacing.paddingMedium * 2
                        radius: Radii.card
                        color: Colors.warningContainer

                        RowLayout {
                            id: mediaLayout
                            anchors.fill: parent
                            anchors.margins: Spacing.paddingMedium
                            spacing: Spacing.gapMedium

                            Rectangle {
                                Layout.preferredWidth: 12
                                Layout.preferredHeight: 12
                                radius: 6
                                color: MissionTheme.warning
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Spacing.gapTiny
                                Label {
                                    text: qsTr("Remove the installation media before restarting")
                                    font.weight: Typography.weightSemibold
                                    color: Colors.contentOnWarningContainer
                                }
                                Label {
                                    text: qsTr("If you installed from removable media, remove it now — after restarting, Mission OS boots from your installed disk.")
                                    font.pixelSize: Typography.bodySmall.size
                                    color: Colors.contentOnWarningContainer
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                        }

                        Accessible.role: Accessible.Grouping
                        Accessible.name: qsTr("Remove the installation media before restarting")
                        Accessible.description: qsTr("If you installed from removable media, remove it before restarting")
                    }

                    // ── Report / log actions (reference § "Screen 15" —
                    //    View installation report, Export installation
                    //    log; the report itself is host-side) ──
                    Row {
                        spacing: Spacing.gapMedium
                        MissionButton {
                            id: viewReportButton
                            objectName: "completionViewReport"
                            variant: MissionButton.Variant.Tertiary
                            text: qsTr("View installation report")
                            onClicked: root.viewReportRequested()
                        }
                        MissionButton {
                            id: exportLogButton
                            objectName: "completionExportLog"
                            variant: MissionButton.Variant.Tertiary
                            text: qsTr("Export installation log")
                            onClicked: root.exportLogRequested()
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
                        text: qsTr("Mission OS is installed and ready. Restart now to boot into your new system, or continue in live mode to keep using the installation media without changing anything further.")
                        width: parent.width
                        font.pixelSize: Typography.bodySmall.size
                        color: MissionTheme.textSecondary
                        wrapMode: Text.Wrap
                        lineHeight: Typography.lineHeightNormal
                    }

                    Item { width: 1; height: Spacing.gapSmall }

                    Label {
                        text: qsTr("The installation report records the installation date, installer version, operating system version, hardware summary, selected options, encryption status, recovery configuration, and verification results. You can view or export it at any time.")
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
    // Bottom action bar — the reference's five completion actions.
    // Restart now (primary) and Continue in Live Mode (secondary) are
    // the main choices; Shut down sits on the left. There is no Back
    // and no Continue on this terminal screen (documented in the
    // header interpretation notes).
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

            MissionButton {
                id: shutdownButton
                objectName: "completionShutdown"
                variant: MissionButton.Variant.Secondary
                text: qsTr("Shut down")
                onClicked: root.shutdownRequested()
            }

            Item { Layout.fillWidth: true }

            MissionButton {
                id: continueLiveButton
                objectName: "completionContinueLive"
                variant: MissionButton.Variant.Secondary
                text: qsTr("Continue in Live Mode")
                onClicked: root.continueLiveRequested()
            }

            MissionButton {
                id: restartButton
                objectName: "completionRestart"
                variant: MissionButton.Variant.Primary
                text: qsTr("Restart now")
                onClicked: root.restartRequested()
                focus: true
            }
        }
    }
}
