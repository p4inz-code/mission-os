// Mission OS — Installer Summary (MOS-INS-010)
//
// Tenth screen of the Mission OS installer — now step 11 of 17
// after MOS-INS-013 Security Options was added between Encryption
// and Summary.
// Implements the source-defined Summary structure (docs/wireframes/
// 01_INSTALLER.md + docs/design/03_SCREEN_REGISTRY.md MOS-INS-010
// "Summary" + docs/reference/01_INSTALLER.md § "Configuration Summary"):
//
//   Hosting: place inside MissionWindow (or MissionPage) content and
//   anchor to fill, e.g.  MissionWindow { Summary { anchors.fill: parent } }
//   The component itself sizes to its implicit 1024x768 like MissionPage.
//
//   Header → Stepper Navigation → Main Content → Help Panel → Bottom actions
//
// Displayed items (per reference § "Configuration Summary") — the
// complete review shown before installation begins, exactly the eleven
// listed items:
//   - Installation mode
//   - Target disk
//   - Partition changes
//   - Region
//   - Keyboard layout
//   - Platform preset
//   - Workspace profile
//   - Privacy settings
//   - Security settings
//   - Estimated installation time
//   - Estimated storage usage
//
// Behavior (per reference § "Configuration Summary"):
//   - "Users may return to any previous step before confirming
//     installation." — Back is always available (wireframe UX rules:
//     linear workflow, back always available). In the linear installer
//     flow the user reaches any previous step by navigating back; the
//     summary itself makes no system changes.
//   - "No system changes occur until the user explicitly approves the
//     final summary." — the primary action (Continue) only fires
//     continueRequested(); the host application decides what approval
//     means (e.g. beginning the installation — MOS-INS-011). The
//     summary screen itself is strictly read-only and performs no
//     system changes.
//
// Interpretation notes (documented; no authoritative source specifies
// further detail):
//   - The screen is host-fed: the host wires the real configuration
//     values into `summarySections` (replace the model or use
//     setSectionValue() per section). The default values shown on load
//     mirror the established preselects of the preceding screens
//     (MOS-INS-002 English/United States, MOS-INS-003 US + Linux
//     (Default), MOS-INS-005 all optional services disabled, MOS-INS-009
//     No encryption, reference Screen 04 "Install Mission OS" permanent
//     mode, reference Screen 11 "General" profile) so the review renders
//     coherently before the host supplies real data. No previous screen
//     establishes an installation mode, workspace profile, or storage/
//     time estimate — the two estimates default to a neutral "—" and the
//     host fills real values.
//   - Read-only review: no per-section edit controls are specified by
//     the sources, so none are invented — the established linear Back
//     navigation is how the user returns to any previous step.
//   - No *ChangeRequested signal exists on this screen: nothing is
//     configured here (the summary is a review, not a configuration
//     step), so there is no user-editable state to report.
//
// States (per wireframe): empty · loading · error · success · offline
// The screen exposes *Requested signals; the host application decides
// what each action does.
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
    property int step: 11

    /// Total number of installer steps (screen registry: 16)
    property int totalSteps: 17

    /// Reduced motion (accessibility)
    property bool reducedMotion: false

    /// Installer/OS version string shown in the header
    property string version: "0.1.0"

    /// Build channel: Stable | Beta | Nightly
    property string buildType: "Nightly"

    // ── Configuration summary (reference § "Configuration Summary") ──
    // The eleven items exactly as listed in the reference. Each entry:
    // { code, label, value, detail }. The host supplies the real values
    // (replace `summarySections` wholesale, or call setSectionValue()
    // per section); the defaults mirror the preselects of the preceding
    // screens so the review renders coherently before host wiring (see
    // the header interpretation notes). No signal is emitted on load —
    // this is a read-only review and the host already knows the state.
    property var summarySections: [
        { code: "mode",        label: "Installation mode",              value: "Install Mission OS",             detail: "" },
        { code: "disk",        label: "Target disk",                    value: "No disk selected",              detail: "" },
        { code: "partitions",  label: "Partition changes",              value: "None",                          detail: "" },
        { code: "region",      label: "Region",                         value: "English (United States)",       detail: "en_US" },
        { code: "keyboard",    label: "Keyboard layout",                value: "US",                            detail: "us" },
        { code: "preset",      label: "Platform preset",                value: "Linux (Default)",               detail: "linux" },
        { code: "profile",     label: "Workspace profile",              value: "General",                       detail: "" },
        { code: "privacy",     label: "Privacy settings",               value: "All optional services disabled", detail: "0 of 6 enabled" },
        { code: "security",    label: "Security settings",              value: "Auto updates enabled",           detail: "" },
        { code: "time",        label: "Estimated installation time",    value: "—",                             detail: "" },
        { code: "storage",     label: "Estimated storage usage",        value: "—",                             detail: "" }
    ]

    /// Number of summary sections (all are shown; reference lists eleven)
    property int summaryCount: root.summarySections.length

    /// Height of one two-line summary row (label + optional detail).
    /// Named once so the ListView height formula and the delegate height
    /// can never drift apart (same pattern as the Encryption row height).
    readonly property int summaryRowHeight: 56

    // ── Signals (host wiring) ──────────────────────────────────────
    /// User approved the summary and requested to continue (the host
    /// decides what approval means — e.g. starting installation)
    signal continueRequested()
    /// User requested to go back to the previous step
    signal backRequested()
    /// User requested to retry after an error
    signal retryRequested()

    // ── Escape navigates back (Master UX: Back always available) ──
    // No child on this screen consumes Escape (the summary list is
    // read-only), so root Escape always → backRequested.
    Keys.onEscapePressed: root.backRequested()

    // ── Responsive helpers ─────────────────────────────────────────
    readonly property bool wideLayout: root.width >= 760
    readonly property bool compactLayout: root.width < 640

    // ── Summary helpers (host wiring / tests) ──────────────────────
    /// Index of the section with `code` within `summarySections`,
    /// or -1 when no such section exists.
    function sectionIndex(code) {
        for (var i = 0; i < root.summarySections.length; ++i) {
            if (root.summarySections[i].code === code)
                return i
        }
        return -1
    }

    /// The section object (from `summarySections`) with `code`, or null.
    function getSection(code) {
        var i = root.sectionIndex(code)
        return i >= 0 ? root.summarySections[i] : null
    }

    /// Host wiring: update the value (and optional detail) of the
    /// section identified by `code` without replacing the whole model.
    /// The model is reassigned (slice copy of the same section objects)
    /// so the summarySectionsChanged notification reaches the list and
    /// the rendered rows re-evaluate. Unknown codes are ignored.
    function setSectionValue(code, value, detail) {
        var i = root.sectionIndex(code)
        if (i < 0)
            return
        var sections = root.summarySections
        sections[i].value = value
        if (detail !== undefined)
            sections[i].detail = detail
        root.summarySections = sections.slice()
    }

    // ── Test hooks (used by tests/tst_summary.qml) ─────────────────
    property alias backgroundColor: backgroundRect.color
    property alias headingColor: headingLabel.color
    property alias headingLabel: headingLabel
    property alias summaryList: summaryList
    property alias summaryCaption: summaryCaption
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
                text: qsTr("Step %1 of %2 · Summary").arg(root.step).arg(root.totalSteps)
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
                            text: qsTr("Preparing configuration summary…")
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
                                    text: qsTr("Summary could not be loaded")
                                    font.weight: Typography.weightSemibold
                                    color: Colors.contentOnErrorContainer
                                }
                                Label {
                                    text: qsTr("The configuration could not be verified. Check the installation media and try again.")
                                    font.pixelSize: Typography.bodySmall.size
                                    color: Colors.contentOnErrorContainer
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                            MissionButton {
                                id: retryButton
                                objectName: "summaryRetry"
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
                                    text: qsTr("Configuration confirmed")
                                    font.weight: Typography.weightSemibold
                                    color: Colors.contentOnSuccessContainer
                                }
                                Label {
                                    text: qsTr("Your configuration has been reviewed. No system changes have been made — installation begins only when you continue.")
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
                                    text: qsTr("This step works without an internet connection. Your configuration is stored locally on this device.")
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
                        text: qsTr("Configuration summary")
                        width: parent.width
                        font.pixelSize: Typography.headline.size
                        font.weight: Typography.headline.weight
                        color: MissionTheme.textPrimary
                        wrapMode: Text.Wrap
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    Label {
                        text: qsTr("Before installation begins, review the complete configuration below. No system changes occur until you explicitly approve this summary.")
                        width: parent.width
                        font.pixelSize: Typography.bodyLarge.size
                        color: MissionTheme.textSecondary
                        wrapMode: Text.Wrap
                        lineHeight: Typography.lineHeightRelaxed
                    }

                    // ── Configuration summary list (read-only review) ──
                    // The eleven items from the reference § "Configuration
                    // Summary". Rows are non-interactive: no selection, no
                    // edit controls (none specified — Back returns to any
                    // previous step instead). Read-only rows are not Tab
                    // stops, so the focus chain is Back → Continue.
                    ListView {
                        id: summaryList
                        objectName: "summaryList"
                        width: parent.width
                        // All rows visible by default; capped so the list
                        // never dominates short windows (scrolls inside).
                        height: Math.min(root.summarySections.length * root.summaryRowHeight
                                         + (root.summarySections.length - 1) * Spacing.gapTiny,
                                         396)
                        clip: true
                        model: root.summarySections
                        spacing: Spacing.gapTiny
                        ScrollIndicator.vertical: ScrollIndicator {}
                        Accessible.role: Accessible.List
                        Accessible.name: qsTr("Configuration summary")
                        Accessible.description: qsTr("Review of the installation configuration before it is applied")

                        delegate: Rectangle {
                            id: summaryDelegate
                            required property var modelData
                            required property int index

                            objectName: "summaryItem" + index
                            width: summaryList.width
                            height: root.summaryRowHeight
                            radius: Radii.input
                            color: MissionTheme.surface

                            // Test hook: expose the rendered value label so
                            // the suite can verify the list reflects host
                            // value updates (see tests/tst_summary.qml).
                            property alias valueLabel: valueLabel

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

                                // Section label (left)
                                Label {
                                    text: modelData.label
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    font.pixelSize: Typography.body.size
                                    color: MissionTheme.textPrimary
                                    verticalAlignment: Text.AlignVCenter
                                }

                                // Value (+ optional detail, right-aligned)
                                Column {
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: 0

                                    Label {
                                        id: valueLabel
                                        text: modelData.value
                                        anchors.right: parent.right
                                        elide: Text.ElideRight
                                        font.pixelSize: Typography.body.size
                                        font.weight: Typography.weightSemibold
                                        color: MissionTheme.textPrimary
                                    }

                                    Label {
                                        text: modelData.detail
                                        anchors.right: parent.right
                                        visible: modelData.detail.length > 0
                                        elide: Text.ElideRight
                                        font.pixelSize: Typography.caption.size
                                        color: MissionTheme.textTertiary
                                    }
                                }
                            }

                            Accessible.role: Accessible.ListItem
                            Accessible.name: qsTr("%1: %2").arg(modelData.label).arg(modelData.value)
                            Accessible.description: modelData.detail
                        }
                    }

                    // ── Live confirmation caption (read-only review) ──
                    Label {
                        id: summaryCaption
                        width: parent.width
                        text: qsTr("No system changes occur until you approve this summary.")
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
                        text: qsTr("Review everything before confirming. You can return to any previous step with Back — nothing is changed until you approve this summary.")
                        width: parent.width
                        font.pixelSize: Typography.bodySmall.size
                        color: MissionTheme.textSecondary
                        wrapMode: Text.Wrap
                        lineHeight: Typography.lineHeightNormal
                    }

                    Item { width: 1; height: Spacing.gapSmall }

                    Label {
                        text: qsTr("Estimated installation time and storage usage are filled in by the installer as it finalizes the plan.")
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

            // Back is only available past step 1 (linear workflow) and is
            // how the user returns to any previous step (reference §
            // "Configuration Summary": "Users may return to any previous
            // step before confirming installation.")
            MissionButton {
                id: backButton
                objectName: "summaryBack"
                variant: MissionButton.Variant.Secondary
                text: qsTr("Back")
                enabled: root.step > 1
                onClicked: root.backRequested()
            }

            Item { Layout.fillWidth: true }

            // Continue (primary action; disabled while loading/error so it
            // never silently advances when validation is pending). This is
            // the explicit approval of the final summary — the reference
            // states no system changes occur until the user approves it;
            // the host decides what continueRequested() means (e.g.
            // starting the installation).
            MissionButton {
                id: continueButton
                objectName: "summaryContinue"
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
