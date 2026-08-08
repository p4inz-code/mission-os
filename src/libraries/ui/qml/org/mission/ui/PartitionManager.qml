// Mission OS — Installer Partition Manager (MOS-INS-007)
//
// Seventh screen of the Mission OS installer.
// Implements the source-defined Partition structure (docs/wireframes/
// 01_INSTALLER.md + docs/design/03_SCREEN_REGISTRY.md MOS-INS-007
// "Partition Manager" + docs/reference/01_INSTALLER.md Screen 07
// "Partition Review"):
//
//   Hosting: place inside MissionWindow (or MissionPage) content and
//   anchor to fill, e.g.  MissionWindow { PartitionManager { anchors.fill: parent } }
//   The component itself sizes to its implicit 1024x768 like MissionPage.
//
//   Header → Stepper Navigation → Main Content → Help Panel → Bottom actions
//
// Displayed items (per reference Screen 07):
//   - existing partitions
//   - proposed changes (Create / Format / Keep per partition)
//   - filesystem
//   - mount points
//   - boot partition (badge) and recovery partition (badge)
//   - Every destructive action is clearly highlighted: destructive rows
//     render on the error container with an error border, a "Destructive"
//     text marker (non-color indicator for color-blind users) and an
//     error-styled change badge.
//
// This is a review screen: nothing is changed on this step ("No disk
// modifications have yet occurred" — reference Section Summary), and
// confirmation happens at the final installation summary ("No system
// changes occur until the user explicitly approves the final summary").
// The partition rows are therefore read-only — no selection and no
// host-change signal exist on this screen (nothing the user does here
// mutates the plan; the host supplies the plan via `partitionOptions`).
//
// States (per wireframe): empty · loading · error · success · offline
// The screen exposes *Requested signals; the host application decides
// what each action does (e.g. persisting the reviewed partition plan).
//
// The partition fixture follows the authoritative Mission OS partition
// scheme (docs/engineering/ARCHITECTURE.md §8.2): EFI System Partition
// → /boot/efi (512 MB), Boot → /boot (1 GB), Root → / (20+ GB),
// Home → /home (remaining), Recovery → /recovery (8+ GB). Filesystems
// per docs/engineering/DATA_ARCHITECTURE.md (ext4) and UEFI practice
// (FAT32 EFI). Static fixture; the host storage service supplies the
// real plan.
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
    property int step: 7

    /// Total number of installer steps (screen registry: 12)
    property int totalSteps: 17

    /// Reduced motion (accessibility)
    property bool reducedMotion: false

    /// Installer/OS version string shown in the header
    property string version: "0.1.0"

    /// Build channel: Stable | Beta | Nightly
    property string buildType: "Nightly"

    /// Friendly name of the destination disk whose plan is being
    /// reviewed ("clearly identify affected disks" — installer
    /// philosophy). Host wiring sets this from Disk Selection;
    /// never a fabricated default (FABRICATION-8).
    property string diskLabel: ""

    /// The proposed partition plan for the destination disk. Each entry:
    /// { name, label, size, filesystem, mountPoint, boot, recovery,
    ///   change, destructive } — displays existing partitions (reformatted
    /// or kept) and proposed changes (created), with the filesystem,
    /// mount point, and boot/recovery roles per reference Screen 07.
    /// Destructive entries (e.g. "Format") are rendered highlighted.
    /// Static fixture; the host storage service supplies the real plan.
    /// Default empty — host-fed only; no fabricated partition plan (FABRICATION-8)
    property var partitionOptions: []

    /// Number of partitions in the plan (all are shown)
    property int partitionCount: root.partitionOptions.length

    /// Number of destructive proposed changes (e.g. "Format") — used by
    /// the plan caption and by tests; destructive actions are the ones
    /// the installer must clearly highlight (reference Screen 07).
    property int destructiveCount: {
        var n = 0
        for (var i = 0; i < root.partitionOptions.length; ++i) {
            if (root.partitionOptions[i].destructive)
                ++n
        }
        return n
    }

    // ── Signals (host wiring) ──────────────────────────────────────
    /// User requested to continue to the next step
    signal continueRequested()
    /// User requested to go back to the previous step
    signal backRequested()
    /// User requested to retry after an error
    signal retryRequested()
    // NOTE: no host-change signal — this screen only reviews the plan
    // provided by the host; nothing the user does here mutates it, so
    // nothing is emitted on load or interaction (beyond the actions
    // above).

    // ── Escape navigates back (Master UX: Back always available) ──
    // No child on this screen consumes Escape (the plan rows are
    // read-only), so root Escape always → backRequested.
    Keys.onEscapePressed: root.backRequested()

    // ── Responsive helpers ─────────────────────────────────────────
    readonly property bool wideLayout: root.width >= 760
    readonly property bool compactLayout: root.width < 640

    /// Height of a two-line partition row (name + details). Named once
    /// so layout and delegate can never drift (same pattern as the
    /// Disk Selection row height — no single token fits two text lines).
    readonly property int partitionRowHeight: 72

    // ── Test hooks (used by tests/tst_partition_manager.qml) ───────
    property alias backgroundColor: backgroundRect.color
    property alias headingColor: headingLabel.color
    property alias headingLabel: headingLabel
    property alias partitionRows: partitionRows
    property alias planCaption: planCaption
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
                text: qsTr("Step %1 of %2 · Partition").arg(root.step).arg(root.totalSteps)
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
                            text: qsTr("Preparing the partition plan…")
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
                        // latent bug class as 001–006; proven fix).
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
                                    text: qsTr("Partition plan could not be loaded")
                                    font.weight: Typography.weightSemibold
                                    color: Colors.contentOnErrorContainer
                                }
                                Label {
                                    text: qsTr("The storage plan could not be verified. Check the installation media and try again.")
                                    font.pixelSize: Typography.bodySmall.size
                                    color: Colors.contentOnErrorContainer
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                            MissionButton {
                                id: retryButton
                                objectName: "partitionRetry"
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
                                    text: qsTr("Partition plan confirmed")
                                    font.weight: Typography.weightSemibold
                                    color: Colors.contentOnSuccessContainer
                                }
                                Label {
                                    text: qsTr("The reviewed plan will be applied during installation.")
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
                                    text: qsTr("Mission OS installs fully without an internet connection. Partition planning works locally.")
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
                        text: qsTr("Review the partition plan")
                        width: parent.width
                        font.pixelSize: Typography.headline.size
                        font.weight: Typography.headline.weight
                        color: MissionTheme.textPrimary
                        wrapMode: Text.Wrap
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    Label {
                        text: qsTr("The installer will prepare storage on %1 as shown below. No changes are made to your disk until you confirm the installation summary later in this installer. Destructive changes are highlighted.").arg(root.diskLabel)
                        width: parent.width
                        font.pixelSize: Typography.bodyLarge.size
                        color: MissionTheme.textSecondary
                        wrapMode: Text.Wrap
                        lineHeight: Typography.lineHeightRelaxed
                    }

                    // ── Partition plan ──
                    Label {
                        text: qsTr("Partition plan · %1").arg(root.diskLabel)
                        width: parent.width
                        font.pixelSize: Typography.subtitle.size
                        font.weight: Typography.subtitle.weight
                        color: MissionTheme.textPrimary
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    // Legend: destructive semantics are stated in words,
                    // not color alone (color-blind friendly indicator).
                    Label {
                        text: qsTr("Changes marked Destructive will erase data on that partition.")
                        width: parent.width
                        font.pixelSize: Typography.caption.size
                        color: Colors.contentOnErrorContainer
                        wrapMode: Text.Wrap
                        lineHeight: Typography.lineHeightNormal
                        Accessible.role: Accessible.StaticText
                        Accessible.name: text
                    }

                    // ── Read-only partition rows ──
                    // Review display only — no selection, no editing
                    // (reference Screen 07 is a review; modification
                    // belongs to advanced Manual Partitioning, which is
                    // not this linear step).
                    Repeater {
                        id: partitionRows
                        model: root.partitionOptions

                        delegate: Rectangle {
                            id: partitionDelegate
                            required property var modelData
                            required property int index

                            // Public access from the host / test suite
                            // (QML ids inside a Repeater delegate are
                            // scoped to the delegate component — an
                            // explicit alias makes them addressable).
                            property alias rowBackground: rowRect
                            property alias bootBadge: bootBadge
                            property alias recoveryBadge: recoveryBadge
                            property alias changeBadge: changeBadge
                            property alias changeBadgeText: changeBadgeLabel.text
                            property alias destructiveMarker: destructiveMarker

                            objectName: "partitionItem" + index
                            width: parent.width
                            height: root.partitionRowHeight

                            // Destructive actions are clearly highlighted
                            // (reference Screen 07): error container
                            // background + error border; all other rows
                            // render on the neutral surface.
                            Rectangle {
                                id: rowRect
                                anchors.fill: parent
                                radius: Radii.card
                                color: modelData.destructive
                                     ? Colors.errorContainer
                                     : MissionTheme.surface
                                border.color: modelData.destructive
                                     ? MissionTheme.error
                                     : MissionTheme.outlineVariant
                                border.width: 1

                                // Partition name + change badge on line 1,
                                // size · filesystem · mount point + role
                                // badges on line 2 (boot / recovery), with
                                // an explicit "Destructive" marker.
                                Column {
                                    x: Spacing.paddingMedium
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - Spacing.paddingMedium * 2
                                    spacing: Spacing.gapTiny

                                    RowLayout {
                                        width: parent.width
                                        spacing: Spacing.gapMedium

                                        Label {
                                            text: modelData.name
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                            font.pixelSize: Typography.body.size
                                            font.weight: Typography.weightSemibold
                                            color: MissionTheme.textPrimary
                                        }

                                        // Proposed change badge
                                        Rectangle {
                                            id: changeBadge
                                            Layout.preferredHeight: 24
                                            implicitWidth: changeBadgeLabel.implicitWidth + Spacing.paddingSmall * 2
                                            radius: Radii.chip
                                            color: modelData.destructive
                                                 ? MissionTheme.error
                                                 : MissionTheme.surfaceDim
                                            Label {
                                                id: changeBadgeLabel
                                                anchors.centerIn: parent
                                                text: modelData.change
                                                font.pixelSize: Typography.caption.size
                                                font.weight: Typography.weightSemibold
                                                color: modelData.destructive
                                                     ? MissionTheme.contentOnError
                                                     : MissionTheme.textSecondary
                                            }
                                        }
                                    }

                                    RowLayout {
                                        width: parent.width
                                        spacing: Spacing.gapMedium

                                        Label {
                                            text: qsTr("%1 · %2 · %3").arg(modelData.size)
                                                                      .arg(modelData.filesystem)
                                                                      .arg(modelData.mountPoint)
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                            font.pixelSize: Typography.bodySmall.size
                                            color: modelData.destructive
                                                 ? Colors.contentOnErrorContainer
                                                 : MissionTheme.textSecondary
                                        }

                                        // Boot partition role badge
                                        Rectangle {
                                            id: bootBadge
                                            visible: modelData.boot
                                            Layout.preferredHeight: 20
                                            implicitWidth: bootBadgeLabel.implicitWidth + Spacing.paddingSmall * 2
                                            radius: Radii.chip
                                            color: MissionTheme.primaryContainer
                                            Label {
                                                id: bootBadgeLabel
                                                anchors.centerIn: parent
                                                text: qsTr("Boot")
                                                font.pixelSize: Typography.caption.size
                                                font.weight: Typography.weightSemibold
                                                color: MissionTheme.contentOnPrimaryContainer
                                            }
                                        }

                                        // Recovery partition role badge
                                        Rectangle {
                                            id: recoveryBadge
                                            visible: modelData.recovery
                                            Layout.preferredHeight: 20
                                            implicitWidth: recoveryBadgeLabel.implicitWidth + Spacing.paddingSmall * 2
                                            radius: Radii.chip
                                            color: MissionTheme.secondaryContainer
                                            Label {
                                                id: recoveryBadgeLabel
                                                anchors.centerIn: parent
                                                text: qsTr("Recovery")
                                                font.pixelSize: Typography.caption.size
                                                font.weight: Typography.weightSemibold
                                                color: MissionTheme.contentOnSecondaryContainer
                                            }
                                        }

                                        // Explicit destructive marker — a
                                        // non-color indicator so the warning
                                        // is not conveyed by color alone.
                                        Label {
                                            id: destructiveMarker
                                            visible: modelData.destructive
                                            text: qsTr("Destructive")
                                            font.pixelSize: Typography.caption.size
                                            font.weight: Typography.weightSemibold
                                            color: Colors.contentOnErrorContainer
                                        }
                                    }
                                }
                            }

                            Accessible.role: Accessible.Grouping
                            Accessible.name: modelData.name + ", " + modelData.change
                            Accessible.description: modelData.size + ", " +
                                                    modelData.filesystem + ", " +
                                                    modelData.mountPoint +
                                                    (modelData.boot ? ", boot" : "") +
                                                    (modelData.recovery ? ", recovery" : "") +
                                                    (modelData.destructive ? ", destructive" : "")
                        }
                    }

                    // ── Plan summary caption ──
                    Label {
                        id: planCaption
                        width: parent.width
                        text: qsTr("%1 partitions planned · %2 destructive changes")
                              .arg(root.partitionCount).arg(root.destructiveCount)
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
                        text: qsTr("This screen reviews the partition plan for the selected destination disk — existing partitions and proposed changes with their filesystem, mount point, and size.")
                        width: parent.width
                        font.pixelSize: Typography.bodySmall.size
                        color: MissionTheme.textSecondary
                        wrapMode: Text.Wrap
                        lineHeight: Typography.lineHeightNormal
                    }

                    Item { width: 1; height: Spacing.gapSmall }

                    Label {
                        text: qsTr("Changes marked Destructive will erase data on that partition. Review each one before continuing.")
                        width: parent.width
                        font.pixelSize: Typography.bodySmall.size
                        color: MissionTheme.textSecondary
                        wrapMode: Text.Wrap
                        lineHeight: Typography.lineHeightNormal
                    }

                    Item { width: 1; height: Spacing.gapSmall }

                    Label {
                        text: qsTr("Nothing is written to your disk until you confirm the installation summary later in this installer.")
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
                objectName: "partitionBack"
                variant: MissionButton.Variant.Secondary
                text: qsTr("Back")
                enabled: root.step > 1
                onClicked: root.backRequested()
            }

            Item { Layout.fillWidth: true }

            // Continue (primary action; disabled while loading/error so
            // it never silently advances when the plan is pending —
            // this review screen has no other validation gate)
            MissionButton {
                id: continueButton
                objectName: "partitionContinue"
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
