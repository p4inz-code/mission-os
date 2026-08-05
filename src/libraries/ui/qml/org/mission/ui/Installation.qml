// Mission OS — Installer Installation (MOS-INS-011)
//
// Eleventh screen of the Mission OS installer — now step 12 of 17
// after MOS-INS-013 Security Options was added between Encryption
// and Summary.
// Implements the source-defined Installation structure (docs/wireframes/
// 01_INSTALLER.md + docs/design/03_SCREEN_REGISTRY.md MOS-INS-011
// "Installation" + docs/reference/01_INSTALLER.md § "Screen 14 —
// Installation Progress"):
//
//   Hosting: place inside MissionWindow (or MissionPage) content and
//   anchor to fill, e.g.  MissionWindow { Installation { anchors.fill: parent } }
//   The component itself sizes to its implicit 1024x768 like MissionPage.
//
//   Header → Stepper Navigation → Main Content → Help Panel → Bottom actions
//
// Displayed items (per reference § "Screen 14 — Installation Progress"),
// exactly the six listed items:
//   - Overall progress percentage
//   - Current installation stage
//   - Current task description
//   - Estimated remaining time
//   - Installation log (expandable)
//   - Overall health indicator
//
// The twelve installation stages mirror the reference's example stages
// list exactly ("1. Preparing installation … 12. Finalizing
// installation") — no stage is invented or omitted. They are a static
// fixture the host may replace wholesale; the host drives the progress
// display (progress, currentStageIndex, currentTask,
// estimatedTimeRemaining, installationLog).
//
// Architecture (documented interpretation; no authoritative source
// specifies further detail):
//   - This screen is a progress display, not a configuration step. The
//     user approved the configuration on the previous screen (MOS-INS-010
//     Summary); per the reference § "Configuration Summary" "no system
//     changes occur until the user explicitly approves the final
//     summary", installation begins only after that approval and runs
//     automatically under host control ("When recovery succeeds,
//     installation should continue automatically" — § "Error Recovery").
//     The UI component performs NO real system changes and never
//     advances itself — the host wires the real installer engine values
//     into the properties above and navigates forward when installation
//     completes (MOS-INS-012 Completion is a separate screen, out of
//     scope here).
//   - No Continue button: the reference defines no user-initiated
//     "continue" on this screen (progression is automatic; the host
//     advances to Completion). The wireframe's generic "Back / Continue"
//     shell layout is a template; this screen's authoritative content is
//     the progress display, so the action bar carries only Back (Back
//     navigation always available — wireframe UX rules; Escape →
//     backRequested like every installer screen). The host decides what
//     backRequested() means (e.g. aborting with explicit confirmation —
//     "No irreversible action should occur without explicit
//     confirmation").
//   - Error handling follows the reference: recoverable situations
//     surface through Retry ("Mission OS should attempt automatic
//     recovery whenever possible"), and non-recoverable errors stop
//     immediately, explain the problem in plain language, suggest
//     possible solutions, and allow exporting a diagnostic report
//     ("allow exporting a diagnostic report" — § "Non-Recoverable
//     Errors") via exportReportRequested() — the host performs the real
//     export. The expandable installation log doubles as the required
//     "technical details (expandable)".
//   - The log is collapsed by default ("Normal users never need to open
//     it") and displays completed tasks, warnings, errors, and
//     timestamps (reference § "Live Installation Log"). Log entries are
//     host-fed via appendLog(); none are fabricated on load.
//   - The overall health indicator reflects the wireframe states
//     (empty/loading/error/success/offline).
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

    /// Current installer step (1-based); Back is only enabled past step 1
    /// Current installer step (1-based); Back is only enabled past step 1
    property int step: 12

    /// Total number of installer steps (screen registry: 16)
    property int totalSteps: 17

    /// Reduced motion (accessibility)
    property bool reducedMotion: false

    /// Installer/OS version string shown in the header
    property string version: "0.1.0"

    /// Build channel: Stable | Beta | Nightly
    property string buildType: "Nightly"

    /// Overall installation progress, 0.0–1.0 (host-driven; the UI
    /// component never advances itself)
    property real progress: 0.0

    /// The twelve installation stages (reference § "Screen 14 —
    /// Installation Progress" example stages, exactly in order). Static
    /// fixture the host may replace wholesale. Each entry:
    /// { code, label }.
    property var installationStages: [
        { code: "preparing",  label: "Preparing installation" },
        { code: "partitions", label: "Creating partitions" },
        { code: "formatting", label: "Formatting storage" },
        { code: "base",       label: "Installing base system" },
        { code: "desktop",    label: "Installing desktop environment" },
        { code: "drivers",    label: "Installing drivers" },
        { code: "security",   label: "Configuring security" },
        { code: "recovery",   label: "Creating recovery environment" },
        { code: "profile",    label: "Applying workspace profile" },
        { code: "verifying",  label: "Verifying installation" },
        { code: "cleaning",   label: "Cleaning temporary files" },
        { code: "finalizing", label: "Finalizing installation" }
    ]

    /// Index of the current stage within `installationStages`
    /// (-1 = not started; host-driven)
    property int currentStageIndex: -1

    /// The current stage object (from `installationStages`), or null
    property var currentStage: root.currentStageIndex >= 0 && root.currentStageIndex < root.installationStages.length
                               ? root.installationStages[root.currentStageIndex] : null

    /// Current stage label, or "Not started" when installation has not
    /// begun
    readonly property string currentStageLabel: root.currentStage
                                                ? root.currentStage.label
                                                : qsTr("Not started")

    /// Current task description (host-driven, e.g. "Extracting base
    /// system packages")
    property string currentTask: ""

    /// Estimated remaining time (host-driven; neutral "—" until the
    /// host reports a real estimate)
    property string estimatedTimeRemaining: "—"

    /// Overall progress as a whole percentage (0–100)
    readonly property int progressPercent: Math.round(Math.max(0, Math.min(1, root.progress)) * 100)

    /// Installation log (host-fed). Each entry: { level: "info" |
    /// "warning" | "error", text, timestamp }. Shows completed tasks,
    /// warnings, errors, and timestamps (reference § "Live Installation
    /// Log"). Defaults empty — the host appends entries via appendLog();
    /// no entry is fabricated on load.
    property var installationLog: []

    /// Whether the expandable installation log is shown. Collapsed by
    /// default ("Normal users never need to open it").
    property bool logExpanded: false

    /// Number of installation stages (all are shown)
    property int installationStageCount: root.installationStages.length

    /// Number of log entries
    property int logCount: root.installationLog.length

    /// Overall health indicator label, derived from the wireframe
    /// states (reference display item "Overall health indicator").
    readonly property string healthLabel: {
        switch (root.screenState) {
        case "loading":  return qsTr("Installing")
        case "error":    return qsTr("Installation stopped")
        case "success":  return qsTr("Installation complete")
        case "offline":  return qsTr("Offline — installation continues without internet")
        default:         return qsTr("Not started")
        }
    }

    /// Overall health indicator color, derived from `screenState`
    readonly property color healthColor: {
        switch (root.screenState) {
        case "loading":  return MissionTheme.primary
        case "error":    return MissionTheme.error
        case "success":  return MissionTheme.success
        default:         return MissionTheme.textTertiary
        }
    }

    // ── Signals (host wiring) ──────────────────────────────────────
    /// User requested to go back (e.g. abort with confirmation — the
    /// host decides; Back navigation always available per wireframe)
    signal backRequested()
    /// User requested to retry after an error (recoverable situations —
    /// automatic recovery is attempted by the host)
    signal retryRequested()
    /// User requested to export a diagnostic report after a
    /// non-recoverable error (reference: "allow exporting a diagnostic
    /// report" — the host performs the real export)
    signal exportReportRequested()

    // ── Escape navigates back (Master UX: Back always available) ──
    // No child on this screen consumes Escape (the stage list and log
    // list are read-only), so root Escape always → backRequested.
    Keys.onEscapePressed: root.backRequested()

    // ── Responsive helpers ─────────────────────────────────────────
    readonly property bool wideLayout: root.width >= 760
    readonly property bool compactLayout: root.width < 640

    /// Height of one stage row (status dot + label + optional tag).
    /// Named once so the ListView height formula and the delegate height
    /// can never drift apart (established pattern).
    readonly property int stageRowHeight: 36

    /// Height of one log entry row (level dot + timestamp + text).
    /// Named once like the other fixed row heights.
    readonly property int logRowHeight: 40

    // ── Stage / log helpers (host wiring / tests) ──────────────────
    /// Index of the stage with `code` within `installationStages`,
    /// or -1 when no such stage exists.
    function stageIndex(code) {
        for (var i = 0; i < root.installationStages.length; ++i) {
            if (root.installationStages[i].code === code)
                return i
        }
        return -1
    }

    /// Host wiring: append a log entry { level, text, timestamp }.
    /// `level` is "info" | "warning" | "error"; `timestamp` is
    /// optional — when omitted the current time is formatted. The model
    /// is reassigned (slice copy of the same entry objects) so the
    /// rendered log re-evaluates.
    function appendLog(level, text, timestamp) {
        var ts = timestamp
        if (ts === undefined || ts === "")
            ts = Qt.formatTime(new Date(), "hh:mm:ss")
        var log = root.installationLog
        log.push({ level: level, text: text, timestamp: ts })
        root.installationLog = log.slice()
    }

    // ── Test hooks (used by tests/tst_installation.qml) ────────────
    property alias backgroundColor: backgroundRect.color
    property alias headingColor: headingLabel.color
    property alias headingLabel: headingLabel
    property alias installationCaption: installationCaption
    property alias helpPanel: helpPanel
    property alias progressBar: progressBar
    property alias progressFill: progressFill
    property alias progressLabel: progressLabel
    property alias healthDot: healthDot
    property alias healthIndicator: healthIndicator
    property alias stageValueLabel: stageValueLabel
    property alias taskLabel: taskLabel
    property alias etaLabel: etaLabel
    property alias stageList: stageList
    property alias contentFlickable: contentFlickable
    property alias contentColumn: contentColumn
    property alias progressCard: progressCard
    property alias logSection: logSection
    property alias logToggle: logToggle
    property alias logList: logList
    property alias backButton: backButton
    property alias retryButton: retryButton
    property alias exportButton: exportButton
    property alias errorBanner: errorBanner
    property alias successBanner: successBanner
    property alias offlineBanner: offlineBanner

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
                text: qsTr("Step %1 of %2 · Installation").arg(root.step).arg(root.totalSteps)
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
                    // Error (title + plain-language explanation +
                    // suggested solutions + recovery actions). The
                    // buttons live on their own row below the text so the
                    // banner never squeezes the explanation on compact
                    // widths (two actions cannot share the row beside the
                    // text at 480px).
                    Rectangle {
                        id: errorBanner
                        visible: root.screenState === "error"
                        width: parent.width
                        // The inner ColumnLayout uses anchors (not layout
                        // sizing), so give the banner an explicit height
                        // from its content — otherwise the Rectangle has
                        // implicit height 0 and the state banner is
                        // invisible even when `visible` is true (the
                        // proven fix from MOS-INS-001 onward).
                        height: errorLayout.implicitHeight + Spacing.paddingMedium * 2
                        radius: Radii.card
                        color: Colors.errorContainer

                        ColumnLayout {
                            id: errorLayout
                            anchors.fill: parent
                            anchors.margins: Spacing.paddingMedium
                            spacing: Spacing.gapSmall

                            RowLayout {
                                Layout.fillWidth: true
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
                                        text: qsTr("Installation stopped")
                                        font.weight: Typography.weightSemibold
                                        color: Colors.contentOnErrorContainer
                                    }
                                    Label {
                                        text: qsTr("The installation could not continue safely and stopped immediately. No further changes are being made; partial changes are rolled back where safe. Check the installation media and available storage space, then try again — or export a diagnostic report for support.")
                                        font.pixelSize: Typography.bodySmall.size
                                        color: Colors.contentOnErrorContainer
                                        wrapMode: Text.Wrap
                                        Layout.fillWidth: true
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Spacing.gapMedium
                                Item { Layout.fillWidth: true }
                                MissionButton {
                                    id: retryButton
                                    objectName: "installationRetry"
                                    variant: MissionButton.Variant.Secondary
                                    text: qsTr("Retry")
                                    onClicked: root.retryRequested()
                                }
                                MissionButton {
                                    id: exportButton
                                    objectName: "installationExport"
                                    variant: MissionButton.Variant.Tertiary
                                    text: qsTr("Export diagnostic report")
                                    onClicked: root.exportReportRequested()
                                }
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
                                    text: qsTr("Installation complete")
                                    font.weight: Typography.weightSemibold
                                    color: Colors.contentOnSuccessContainer
                                }
                                Label {
                                    text: qsTr("Mission OS was installed and verified successfully. The next screen offers restart options and the installation report.")
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
                                    text: qsTr("Mission OS installs fully without an internet connection. Installation continues normally — no online service is required.")
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
                        text: qsTr("Installation")
                        width: parent.width
                        font.pixelSize: Typography.headline.size
                        font.weight: Typography.headline.weight
                        color: MissionTheme.textPrimary
                        wrapMode: Text.Wrap
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    Label {
                        text: qsTr("Mission OS is installing to your device. Progress is reported below, so you always know what the system is doing — most of the work happens automatically and runs in parallel where possible.")
                        width: parent.width
                        font.pixelSize: Typography.bodyLarge.size
                        color: MissionTheme.textSecondary
                        wrapMode: Text.Wrap
                        lineHeight: Typography.lineHeightRelaxed
                    }

                    // ── Progress card (the six display items of
                    //    reference § "Screen 14 — Installation Progress")
                    //    — visible in every state so progress is never
                    //    lost; the host drives the values. ──
                    Rectangle {
                        id: progressCard
                        width: parent.width
                        // The inner Column uses anchors (not layout
                        // sizing), so give the card an explicit height
                        // from its content — otherwise the Rectangle has
                        // implicit height 0 and collapses (the proven
                        // banner-height fix pattern from MOS-INS-001
                        // onward; a 0-height positioner child also loses
                        // its managed y position).
                        height: progressCardContent.implicitHeight + Spacing.paddingMedium * 2
                        radius: Radii.card
                        color: MissionTheme.surface

                        Column {
                            id: progressCardContent
                            anchors.fill: parent
                            anchors.margins: Spacing.paddingMedium
                            spacing: Spacing.gapMedium

                            // Overall progress percentage
                            RowLayout {
                                width: parent.width
                                spacing: Spacing.gapMedium
                                Label {
                                    text: qsTr("Overall progress")
                                    font.pixelSize: Typography.caption.size
                                    font.weight: Typography.weightSemibold
                                    color: MissionTheme.textSecondary
                                    Layout.fillWidth: true
                                }
                                Label {
                                    id: progressLabel
                                    text: qsTr("%1%").arg(root.progressPercent)
                                    font.pixelSize: Typography.body.size
                                    font.weight: Typography.weightSemibold
                                    color: MissionTheme.primary
                                    Accessible.role: Accessible.StaticText
                                    Accessible.name: text
                                }
                            }

                            // Progress bar (determinate; host-driven).
                            // Plain Column (not a ColumnLayout) sizes
                            // children vertically only, so the track takes
                            // its width/height explicitly.
                            Rectangle {
                                id: progressBar
                                width: parent.width
                                height: 12
                                radius: 6
                                color: MissionTheme.surfaceDim
                                // Note: Accessible.value is not exposed
                                // on this Ubuntu Qt 6.10 toolchain (same
                                // quirk class as Behavior `duration`), so
                                // the percentage is conveyed by the
                                // adjacent progressLabel (StaticText)
                                // instead of an Accessible.value binding.
                                Accessible.role: Accessible.ProgressBar
                                Accessible.name: qsTr("Overall installation progress")

                                Rectangle {
                                    id: progressFill
                                    width: root.progress * parent.width
                                    height: parent.height
                                    radius: 6
                                    color: MissionTheme.primary
                                    Behavior on width {
                                        enabled: !root.reducedMotion
                                        // Ubuntu Qt 6.10 toolchain: Behavior
                                        // `duration` convenience property is
                                        // rejected; use the equivalent
                                        // `animation:` group property.
                                        animation: NumberAnimation { duration: Motion.durationFast }
                                    }
                                }
                            }

                            // Overall health indicator
                            RowLayout {
                                width: parent.width
                                spacing: Spacing.gapSmall
                                Rectangle {
                                    id: healthDot
                                    Layout.preferredWidth: 10
                                    Layout.preferredHeight: 10
                                    radius: 5
                                    color: root.healthColor
                                    Behavior on color {
                                        enabled: !root.reducedMotion
                                        animation: ColorAnimation { duration: Motion.colorChange }
                                    }
                                }
                                Label {
                                    id: healthIndicator
                                    text: root.healthLabel
                                    font.pixelSize: Typography.bodySmall.size
                                    font.weight: Typography.weightSemibold
                                    color: MissionTheme.textPrimary
                                    Accessible.role: Accessible.StaticText
                                    Accessible.name: qsTr("Overall health: %1").arg(root.healthLabel)
                                }
                            }

                            // Hairline separator
                            Rectangle {
                                width: parent.width
                                height: 1
                                color: MissionTheme.outlineVariant
                            }

                            // Current installation stage
                            RowLayout {
                                width: parent.width
                                spacing: Spacing.gapMedium
                                Label {
                                    text: qsTr("Current stage")
                                    font.pixelSize: Typography.caption.size
                                    color: MissionTheme.textTertiary
                                }
                                Label {
                                    id: stageValueLabel
                                    // Stage numbering counts against the
                                    // stage fixture itself (host may
                                    // replace `installationStages`), not
                                    // the installer step count.
                                    text: root.currentStageIndex >= 0
                                          ? qsTr("Stage %1 of %2 · %3").arg(root.currentStageIndex + 1)
                                                                        .arg(root.installationStages.length)
                                                                        .arg(root.currentStageLabel)
                                          : root.currentStageLabel
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignRight
                                    font.pixelSize: Typography.body.size
                                    font.weight: Typography.weightSemibold
                                    color: MissionTheme.textPrimary
                                }
                            }

                            // Current task description
                            RowLayout {
                                width: parent.width
                                spacing: Spacing.gapMedium
                                Label {
                                    text: qsTr("Current task")
                                    font.pixelSize: Typography.caption.size
                                    color: MissionTheme.textTertiary
                                }
                                Label {
                                    id: taskLabel
                                    text: root.currentTask.length > 0 ? root.currentTask : "—"
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignRight
                                    font.pixelSize: Typography.body.size
                                    color: MissionTheme.textSecondary
                                }
                            }

                            // Estimated remaining time
                            RowLayout {
                                width: parent.width
                                spacing: Spacing.gapMedium
                                Label {
                                    text: qsTr("Estimated remaining time")
                                    font.pixelSize: Typography.caption.size
                                    color: MissionTheme.textTertiary
                                }
                                Label {
                                    id: etaLabel
                                    text: root.estimatedTimeRemaining
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignRight
                                    font.pixelSize: Typography.body.size
                                    font.weight: Typography.weightSemibold
                                    color: MissionTheme.textPrimary
                                }
                            }
                        }
                    }

                    // ── Installation stages (reference example stages;
                    //    read-only — the host drives progression) ──
                    Label {
                        text: qsTr("Installation stages")
                        width: parent.width
                        font.pixelSize: Typography.subtitle.size
                        font.weight: Typography.subtitle.weight
                        color: MissionTheme.textPrimary
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    ListView {
                        id: stageList
                        objectName: "installationStageList"
                        width: parent.width
                        // All rows visible by default; capped so the list
                        // never dominates short windows (scrolls inside).
                        // Math.max(0, …) guards a host-replaced empty
                        // stage fixture (no negative-height collapse).
                        height: Math.max(0, Math.min(root.installationStages.length * root.stageRowHeight
                                                     + (root.installationStages.length - 1) * Spacing.gapTiny,
                                                     300))
                        clip: true
                        model: root.installationStages
                        spacing: Spacing.gapTiny
                        ScrollIndicator.vertical: ScrollIndicator {}
                        Accessible.role: Accessible.List
                        Accessible.name: qsTr("Installation stages")
                        Accessible.description: qsTr("The %1 installation stages and their current status").arg(root.installationStages.length)

                        delegate: Rectangle {
                            id: stageDelegate
                            required property var modelData
                            required property int index

                            // Read-only rows are not Tab stops; the
                            // objectName is used by the keyboard-focus
                            // test to verify they are NOT in the chain.
                            objectName: "installationStageItem" + index
                            width: stageList.width
                            height: root.stageRowHeight
                            radius: Radii.input
                            color: index === root.currentStageIndex ? MissionTheme.surfaceVariant
                                                                    : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Spacing.paddingMedium
                                anchors.rightMargin: Spacing.paddingMedium
                                spacing: Spacing.gapMedium

                                // Status dot: done = success, current =
                                // primary, pending = outline
                                Rectangle {
                                    Layout.preferredWidth: 12
                                    Layout.preferredHeight: 12
                                    radius: 6
                                    color: index < root.currentStageIndex ? MissionTheme.success
                                         : index === root.currentStageIndex ? MissionTheme.primary
                                         : "transparent"
                                    border.width: index < root.currentStageIndex || index === root.currentStageIndex ? 0 : 2
                                    border.color: index < root.currentStageIndex || index === root.currentStageIndex
                                                  ? "transparent" : MissionTheme.outline
                                }

                                Label {
                                    text: modelData.label
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    font.pixelSize: Typography.body.size
                                    font.weight: index === root.currentStageIndex ? Typography.weightSemibold
                                                                                   : Typography.weightRegular
                                    color: index < root.currentStageIndex ? MissionTheme.textSecondary
                                         : index === root.currentStageIndex ? MissionTheme.textPrimary
                                         : MissionTheme.textTertiary
                                }

                                Label {
                                    text: index < root.currentStageIndex ? qsTr("Done")
                                         : index === root.currentStageIndex ? qsTr("In progress")
                                         : ""
                                    visible: index <= root.currentStageIndex
                                    font.pixelSize: Typography.caption.size
                                    font.weight: Typography.weightSemibold
                                    color: index < root.currentStageIndex ? MissionTheme.success
                                         : MissionTheme.primary
                                }
                            }

                            Accessible.role: Accessible.ListItem
                            Accessible.name: modelData.label + " — " +
                                             (index < root.currentStageIndex ? qsTr("done")
                                              : index === root.currentStageIndex ? qsTr("in progress")
                                              : qsTr("pending"))
                        }
                    }

                    // ── Live installation log (expandable) ──
                    // Collapsed by default — "Normal users never need to
                    // open it" (reference § "Live Installation Log").
                    Rectangle {
                        id: logSection
                        width: parent.width
                        // Explicit height from the content Column (same
                        // collapse-prevention as the banners and the
                        // progress card); re-evaluates when the log is
                        // expanded/collapsed via logExpanded.
                        height: logSectionContent.implicitHeight + Spacing.paddingMedium * 2
                        radius: Radii.card
                        color: MissionTheme.surfaceVariant

                        Column {
                            id: logSectionContent
                            anchors.fill: parent
                            anchors.margins: Spacing.paddingMedium
                            spacing: Spacing.gapSmall

                            RowLayout {
                                width: parent.width
                                spacing: Spacing.gapMedium

                                Label {
                                    text: qsTr("Installation log")
                                    Layout.fillWidth: true
                                    font.pixelSize: Typography.body.size
                                    font.weight: Typography.weightSemibold
                                    color: MissionTheme.textPrimary
                                    Accessible.role: Accessible.StaticText
                                    Accessible.name: text
                                }

                                MissionButton {
                                    id: logToggle
                                    objectName: "installationLogToggle"
                                    variant: MissionButton.Variant.Secondary
                                    compact: true
                                    text: root.logExpanded ? qsTr("Hide details") : qsTr("Show details")
                                    onClicked: root.logExpanded = !root.logExpanded
                                }
                            }

                            // Expanded log content
                            Column {
                                width: parent.width
                                visible: root.logExpanded
                                spacing: Spacing.gapTiny

                                Label {
                                    text: qsTr("Completed tasks, warnings, and errors appear here with timestamps. This is technical detail — normal users never need to open it.")
                                    width: parent.width
                                    font.pixelSize: Typography.caption.size
                                    color: MissionTheme.textTertiary
                                    wrapMode: Text.Wrap
                                    Accessible.role: Accessible.StaticText
                                    Accessible.name: text
                                }

                                ListView {
                                    id: logList
                                    objectName: "installationLogList"
                                    width: parent.width
                                    // Capped so the expanded log never
                                    // dominates the screen (scrolls inside).
                                    // Math.max(0, …) guards the empty log
                                    // (no negative-height collapse).
                                    height: Math.max(0, Math.min(root.installationLog.length * root.logRowHeight
                                                                 + (root.installationLog.length - 1) * Spacing.gapTiny,
                                                                 240))
                                    clip: true
                                    model: root.installationLog
                                    spacing: Spacing.gapTiny
                                    ScrollIndicator.vertical: ScrollIndicator {}
                                    Accessible.role: Accessible.List
                                    Accessible.name: qsTr("Installation log entries")

                                    delegate: Rectangle {
                                        id: logDelegate
                                        required property var modelData
                                        required property int index

                                        // Read-only rows are not Tab stops;
                                        // the objectName is used by the
                                        // keyboard-focus test.
                                        objectName: "installationLogItem" + index
                                        width: logList.width
                                        height: root.logRowHeight
                                        radius: Radii.input
                                        color: MissionTheme.surface

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: Spacing.paddingMedium
                                            anchors.rightMargin: Spacing.paddingMedium
                                            spacing: Spacing.gapMedium

                                            // Level marker (warning/error
                                            // stand out; info is neutral)
                                            Rectangle {
                                                Layout.preferredWidth: 8
                                                Layout.preferredHeight: 8
                                                radius: 4
                                                color: modelData.level === "warning" ? MissionTheme.warning
                                                     : modelData.level === "error" ? MissionTheme.error
                                                     : MissionTheme.primary
                                            }

                                            Label {
                                                text: modelData.timestamp
                                                font.family: Typography.fontFamilyMono
                                                font.pixelSize: Typography.caption.size
                                                color: MissionTheme.textTertiary
                                            }

                                            Label {
                                                text: modelData.text
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                                font.pixelSize: Typography.bodySmall.size
                                                font.weight: modelData.level === "error" ? Typography.weightSemibold
                                                                                          : Typography.weightNormal
                                                color: modelData.level === "error" ? MissionTheme.textPrimary
                                                                                   : MissionTheme.textSecondary
                                            }
                                        }

                                        Accessible.role: Accessible.ListItem
                                        Accessible.name: qsTr("%1 — %2").arg(modelData.timestamp).arg(modelData.text)
                                    }
                                }
                            }
                        }
                    }

                    // ── Grounding caption (read-only review) ──
                    Label {
                        id: installationCaption
                        width: parent.width
                        text: qsTr("Installation began only after you approved the configuration summary. No changes were made before that point.")
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
                        text: qsTr("Installation runs automatically after you approved the configuration summary. Most work happens in parallel: filesystem creation, bootloader installation, package deployment, driver detection, hardware optimization, locale configuration, user creation, security configuration, recovery environment creation, and integrity verification.")
                        width: parent.width
                        font.pixelSize: Typography.bodySmall.size
                        color: MissionTheme.textSecondary
                        wrapMode: Text.Wrap
                        lineHeight: Typography.lineHeightNormal
                    }

                    Item { width: 1; height: Spacing.gapSmall }

                    Label {
                        text: qsTr("The installation log is technical — normal users never need to open it. It shows completed tasks, warnings, and errors so you always know if anything needs attention.")
                        width: parent.width
                        font.pixelSize: Typography.bodySmall.size
                        color: MissionTheme.textSecondary
                        wrapMode: Text.Wrap
                        lineHeight: Typography.lineHeightNormal
                    }

                    Item { width: 1; height: Spacing.gapSmall }

                    Label {
                        text: qsTr("Mission OS attempts automatic recovery when possible and verifies installed files, bootloader configuration, filesystem integrity, your account, encryption status, and package integrity before completion. If installation cannot continue safely, it stops and preserves diagnostic information.")
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
    // Bottom action bar (Back — the reference defines no Continue on
    // this screen; progression is automatic under host control)
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

            // Back is only available past step 1 (linear workflow) and is
            // how the user leaves this screen; the host decides what it
            // means (e.g. aborting with explicit confirmation).
            MissionButton {
                id: backButton
                objectName: "installationBack"
                variant: MissionButton.Variant.Secondary
                text: qsTr("Back")
                enabled: root.step > 1
                onClicked: root.backRequested()
            }

            // The action bar carries no primary action on this screen —
            // installation advances automatically under host control and
            // the host navigates to the completion screen (MOS-INS-012)
            // when it finishes. The overall health indicator lives in the
            // progress card above, next to the progress it describes.
            Item { Layout.fillWidth: true }
        }
    }
}
