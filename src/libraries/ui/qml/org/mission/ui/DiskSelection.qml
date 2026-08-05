// Mission OS — Installer Disk Selection (MOS-INS-006)
//
// Sixth screen of the Mission OS installer.
// Implements the source-defined Disk structure (docs/wireframes/
// 01_INSTALLER.md + docs/design/03_SCREEN_REGISTRY.md MOS-INS-006
// "Disk Selection" + docs/reference/01_INSTALLER.md Screen 06):
//
//   Hosting: place inside MissionWindow (or MissionPage) content and
//   anchor to fill, e.g.  MissionWindow { DiskSelection { anchors.fill: parent } }
//   The component itself sizes to its implicit 1024x768 like MissionPage.
//
//   Header → Stepper Navigation → Main Content → Help Panel → Bottom actions
//
// Displayed items (per reference Screen 06):
//   - Every detected drive: friendly name, size, model, interface,
//     health status, existing operating systems, available space.
//   - Friendly names are always shown — "Samsung 990 Pro (2 TB)" instead
//     of "/dev/nvme0n1". The Linux device name is shown only as secondary
//     information, never as the primary identifier ("Users should never
//     need to identify disks using Linux device names alone").
//   - Single-select destination list; selected row highlighted; visible
//     focus ring; Up/Down moves, Enter/Space/click selects.
//     No search/filter (not specified for this screen — do not invent).
//   - Live feedback of the current selection
//   - Back / Continue (wireframe UX rules: linear workflow, back always
//     available, validation before continuing)
//
// No disk is preselected on load: installing targets a disk, and the
// installer philosophy is to prevent mistakes and clearly identify
// affected disks before any change ("No irreversible action should occur
// without explicit confirmation", "Every destructive action should be
// clearly highlighted"). Continue stays disabled until the user picks a
// destination disk (validation before continuing), and no host signal is
// emitted during initialization.
//
// States (per wireframe): empty · loading · error · success · offline
// The screen exposes *Requested signals; the host application decides
// what each action does (e.g. driving storage detection / partitioning).
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
    property int step: 6

    /// Total number of installer steps (screen registry: 12)
    property int totalSteps: 17

    /// Reduced motion (accessibility)
    property bool reducedMotion: false

    /// Installer/OS version string shown in the header
    property string version: "0.1.0"

    /// Build channel: Stable | Beta | Nightly
    property string buildType: "Nightly"

    /// Available destination disks. Each entry: { label, device,
    /// interface, health, os, available } — friendly name first, then
    /// the Linux device name as secondary information only (reference
    /// Screen 06: "Users should never need to identify disks using
    /// Linux device names alone. Friendly names should always be
    /// shown. Example: Samsung 990 Pro (2 TB) instead of /dev/nvme0n1").
    /// Static fixture; the host service (storage daemon) supplies the
    /// real detected drives when diskSelectionRequested fires.
    property var diskOptions: [
        { label: "Samsung 990 Pro (2 TB)",
          device: "nvme0n1",
          interface: "NVMe",
          health: "Good",
          os: "None detected",
          available: "1.8 TB free" },
        { label: "Seagate BarraCuda (1 TB)",
          device: "sda",
          interface: "SATA",
          health: "Good",
          os: "Windows 11",
          available: "512 GB free" },
        { label: "SanDisk Ultra Fit (128 GB)",
          device: "sdb",
          interface: "USB",
          health: "Good",
          os: "Mission OS Live",
          available: "96 GB free" },
        { label: "WD Blue (512 GB)",
          device: "sdc",
          interface: "SATA",
          health: "Warning",
          os: "None detected",
          available: "480 GB free" }
    ]

    /// Index of the selected destination disk within `diskOptions`
    /// (-1 = nothing selected; no preselection on load — installing
    /// targets a disk, so the user must explicitly choose one).
    property int selectedDiskIndex: -1

    /// The selected disk object (from `diskOptions`); null until chosen
    property var selectedDisk: null

    /// Friendly label of the selected disk (e.g. "Samsung 990 Pro (2 TB)")
    property string selectedDiskLabel: ""

    /// Linux device name of the selected disk (e.g. "nvme0n1") — the
    /// identifier passed to the host when diskSelectionRequested fires.
    property string selectedDiskDevice: ""

    // ── Signals (host wiring) ──────────────────────────────────────
    /// User requested to continue to the next step
    signal continueRequested()
    /// User requested to go back to the previous step
    signal backRequested()
    /// User selected a destination disk (device name, e.g. "nvme0n1").
    /// Never emitted on load — no disk is preselected and nothing is
    /// selected during initialization.
    signal diskSelectionRequested(string device)
    /// User requested to retry after an error
    signal retryRequested()

    // ── Escape navigates back (Master UX: Back always available) ──
    // No child on this screen consumes Escape (the list handles
    // Up/Down/Enter/Space), so root Escape always → backRequested.
    Keys.onEscapePressed: root.backRequested()

    // ── Responsive helpers ─────────────────────────────────────────
    readonly property bool wideLayout: root.width >= 760
    readonly property bool compactLayout: root.width < 640

    /// Height of a two-line drive row (friendly name + details). Named
    /// once so the ListView height formula and the delegate height can
    /// never drift apart (the row carries two text lines, so it is
    /// taller than Spacing.minimumTouchTarget — no single token fits).
    readonly property int diskRowHeight: 72

    // ── Selection helper ───────────────────────────────────────────
    /// Select the destination disk at `index` (host wiring / tests).
    /// Emits diskSelectionRequested exactly once with the device name.
    function selectDisk(index) {
        if (index < 0 || index >= root.diskOptions.length)
            return
        var option = root.diskOptions[index]
        root.selectedDiskIndex = index
        root.selectedDisk = option
        root.selectedDiskLabel = option.label
        root.selectedDiskDevice = option.device
        root.diskSelectionRequested(root.selectedDiskDevice)
    }

    // ── Test hooks (used by tests/tst_disk_selection.qml) ──────────
    property alias backgroundColor: backgroundRect.color
    property alias headingColor: headingLabel.color
    property alias headingLabel: headingLabel
    property alias diskList: diskList
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
                text: qsTr("Step %1 of %2 · Disk").arg(root.step).arg(root.totalSteps)
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
                            text: qsTr("Scanning drives…")
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
                        // latent bug class as 001–005; proven fix).
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
                                    text: qsTr("Drives could not be loaded")
                                    font.weight: Typography.weightSemibold
                                    color: Colors.contentOnErrorContainer
                                }
                                Label {
                                    text: qsTr("The storage devices could not be detected. Check the installation media and try again.")
                                    font.pixelSize: Typography.bodySmall.size
                                    color: Colors.contentOnErrorContainer
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                            MissionButton {
                                id: retryButton
                                objectName: "diskRetry"
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
                                    text: qsTr("Destination disk selected")
                                    font.weight: Typography.weightSemibold
                                    color: Colors.contentOnSuccessContainer
                                }
                                Label {
                                    text: qsTr("The selected drive will be used for this installation.")
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
                                    text: qsTr("Mission OS installs fully without an internet connection. Drive detection works locally.")
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
                        text: qsTr("Select a destination disk")
                        width: parent.width
                        font.pixelSize: Typography.headline.size
                        font.weight: Typography.headline.weight
                        color: MissionTheme.textPrimary
                        wrapMode: Text.Wrap
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    Label {
                        text: qsTr("Choose the drive where Mission OS will be installed. Drives are shown with friendly names — you never need to identify disks by Linux device names alone.")
                        width: parent.width
                        font.pixelSize: Typography.bodyLarge.size
                        color: MissionTheme.textSecondary
                        wrapMode: Text.Wrap
                        lineHeight: Typography.lineHeightRelaxed
                    }

                    // ── Detected drives (no search — not specified
                    //    for this screen) ──
                    Label {
                        text: qsTr("Detected drives")
                        width: parent.width
                        font.pixelSize: Typography.subtitle.size
                        font.weight: Typography.subtitle.weight
                        color: MissionTheme.textPrimary
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    ListView {
                        id: diskList
                        objectName: "diskList"
                        width: parent.width
                        // All rows visible by default; capped so the list
                        // never dominates short windows (scrolls inside).
                        height: Math.min(root.diskOptions.length * root.diskRowHeight
                                         + (root.diskOptions.length - 1) * Spacing.gapTiny,
                                         396)
                        clip: true
                        model: root.diskOptions
                        spacing: Spacing.gapTiny
                        activeFocusOnTab: true
                        keyNavigationWraps: true
                        highlightFollowsCurrentItem: true
                        ScrollIndicator.vertical: ScrollIndicator {}
                        onCountChanged: {
                            if (diskList.count > 0 && diskList.currentIndex < 0)
                                diskList.currentIndex = 0
                        }
                        Keys.onReturnPressed: root.selectDisk(diskList.currentIndex)
                        Keys.onSpacePressed: root.selectDisk(diskList.currentIndex)
                        Accessible.role: Accessible.List
                        Accessible.name: qsTr("Detected drives")

                        delegate: Rectangle {
                            id: diskDelegate
                            required property var modelData
                            required property int index

                            // When the list is reached via Tab, focus lands on
                            // the currentItem delegate — not on the ListView
                            // itself — so the delegate carries the objectName
                            // used by the keyboard-focus test.
                            objectName: "diskItem" + index
                            width: diskList.width
                            height: root.diskRowHeight
                            radius: Radii.input
                            color: {
                                if (root.selectedDiskIndex === index)
                                    return MissionTheme.darkMode ? MissionTheme.primary
                                                                 : MissionTheme.primaryContainer
                                if (diskList.currentIndex === index && diskList.activeFocus)
                                    return MissionTheme.surfaceVariant
                                if (diskDelegateMouse.containsMouse)
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
                                visible: diskList.currentIndex === index &&
                                         diskList.activeFocus
                            }

                            // Friendly name + free space on the first line,
                            // interface · health · OS + device name on the
                            // second (device name is secondary information
                            // only — friendly names always lead).
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
                                        color: root.selectedDiskIndex === index
                                             ? (MissionTheme.darkMode ? MissionTheme.contentOnPrimary
                                                                      : MissionTheme.contentOnPrimaryContainer)
                                             : MissionTheme.textPrimary
                                    }

                                    Label {
                                        text: modelData.available
                                        font.pixelSize: Typography.bodySmall.size
                                        font.weight: Typography.weightMedium
                                        color: root.selectedDiskIndex === index
                                             ? (MissionTheme.darkMode ? MissionTheme.contentOnPrimary
                                                                      : MissionTheme.contentOnPrimaryContainer)
                                             : MissionTheme.textSecondary
                                    }
                                }

                                RowLayout {
                                    width: parent.width
                                    spacing: Spacing.gapMedium

                                    Label {
                                        // interface · health · existing OS.
                                        // Health "Warning" is tinted with the
                                        // warning token so caution states stand
                                        // out (semantic use of an existing token).
                                        text: qsTr("%1 · %2 · %3").arg(modelData.interface)
                                                                  .arg(modelData.health)
                                                                  .arg(modelData.os)
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        font.pixelSize: Typography.bodySmall.size
                                        color: root.selectedDiskIndex === index
                                             ? (MissionTheme.darkMode ? MissionTheme.contentOnPrimary
                                                                      : MissionTheme.contentOnPrimaryContainer)
                                             : (modelData.health === "Warning"
                                                ? MissionTheme.warning
                                                : MissionTheme.textTertiary)
                                    }

                                    Label {
                                        text: modelData.device
                                        font.family: Typography.fontFamilyMono
                                        font.pixelSize: Typography.caption.size
                                        color: root.selectedDiskIndex === index
                                             ? (MissionTheme.darkMode ? MissionTheme.contentOnPrimary
                                                                      : MissionTheme.contentOnPrimaryContainer)
                                             : MissionTheme.textTertiary
                                    }
                                }
                            }

                            MouseArea {
                                id: diskDelegateMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    diskList.currentIndex = index
                                    root.selectDisk(index)
                                }
                            }

                            Accessible.role: Accessible.ListItem
                            Accessible.name: modelData.label + ", " + modelData.device
                            Accessible.description: modelData.interface + ", " +
                                                    modelData.health + ", " +
                                                    modelData.os + ", " +
                                                    modelData.available
                            Accessible.selected: root.selectedDiskIndex === index
                        }
                    }

                    // ── Live selection feedback ──
                    Label {
                        id: selectionCaption
                        width: parent.width
                        visible: root.selectedDiskIndex >= 0
                        text: qsTr("Selected: %1 · %2").arg(root.selectedDiskLabel)
                                                      .arg(root.selectedDiskDevice)
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
                        text: qsTr("Mission OS shows friendly drive names (for example, Samsung 990 Pro (2 TB)) so you never need to identify disks by Linux device names like /dev/nvme0n1.")
                        width: parent.width
                        font.pixelSize: Typography.bodySmall.size
                        color: MissionTheme.textSecondary
                        wrapMode: Text.Wrap
                        lineHeight: Typography.lineHeightNormal
                    }

                    Item { width: 1; height: Spacing.gapSmall }

                    Label {
                        text: qsTr("Review each drive's interface, health status, existing operating systems, and available space before choosing.")
                        width: parent.width
                        font.pixelSize: Typography.bodySmall.size
                        color: MissionTheme.textSecondary
                        wrapMode: Text.Wrap
                        lineHeight: Typography.lineHeightNormal
                    }

                    Item { width: 1; height: Spacing.gapSmall }

                    Label {
                        text: qsTr("Nothing is written to any drive until you confirm the installation summary later in this installer.")
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
                objectName: "diskBack"
                variant: MissionButton.Variant.Secondary
                text: qsTr("Back")
                enabled: root.step > 1
                onClicked: root.backRequested()
            }

            Item { Layout.fillWidth: true }

            // Continue (primary action). Disabled until a destination
            // disk is chosen (validation before continuing — installing
            // targets a disk and the installer never silently picks one)
            // and while loading/error so it never advances when
            // validation is pending.
            MissionButton {
                id: continueButton
                objectName: "diskContinue"
                variant: MissionButton.Variant.Primary
                text: qsTr("Continue")
                loading: root.screenState === "loading"
                enabled: root.selectedDiskIndex >= 0 &&
                         root.screenState !== "loading" &&
                         root.screenState !== "error"
                onClicked: root.continueRequested()
                focus: true
            }
        }
    }
}
