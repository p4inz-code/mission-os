// Mission OS — Desktop (MOS-DES-001)
//
// First screen of the Mission OS desktop family.
// Implements the source-defined Desktop structure
// (docs/wireframes/03_DESKTOP.md + docs/design/07_DESKTOP_LAYOUT.md +
// docs/design/03_SCREEN_REGISTRY.md MOS-DES-001 "Desktop"):
//
//   Hosting: place inside MissionWindow (or MissionPage) content and
//   anchor to fill, e.g.  MissionWindow { Desktop { anchors.fill: parent } }
//   The component itself sizes to its implicit 1280x720 (a 16:9 desktop
//   default; the family screens use 1024x768 but the desktop is a
//   widescreen surface — documented interpretation).
//
//   Regions (per wireframe): Top Panel · Dock · Workspace
//   (Notifications, Quick Settings and the Search Overlay are separate
//   registry screens — MOS-DES-003/004/005 — this screen only routes
//   toward them via signals, it does not implement them.)
//
//   Components (per wireframe, minus the separate-screens ones):
//   - Clock (live, host-pinnable — same contract as MOS-LCK-001..004)
//   - Running Apps (top panel taskbar buttons, host-driven model)
//   - Dock (pinned applications with running indicators, host-driven)
//   - Workspace area (the primary working surface)
//   - System Status chips (network/battery — the same token chip
//     pattern as the lock family; the full System Tray is MOS-DES-008)
//   - Workspace Indicator (top panel, routes to MOS-DES-002)
//   - Mission Menu + User Menu entries (host-driven menus, like the
//     lock family's Accessibility button)
//
//   Top Panel contents (per 07_DESKTOP_LAYOUT.md §3, always visible):
//   Mission Menu · Workspace Indicator · Running Applications · Clock
//   · System Status · User Menu. The panel is rendered as a subtle
//   token surface over the wallpaper.
//
//   Dock (per §4): pinned applications, running application
//   indicators, auto-hide support. Auto-hide is host-driven via
//   dockVisible (interactive edge-reveal is host-side, like the clock
//   timer — documented interpretation). The dock floats over the
//   wallpaper at the bottom of the workspace.
//
//   States (per wireframe): Idle · Notifications · Workspace Switching
//   · Search Active. The Desktop models these via `overlayState`; when
//   an overlay is active the matching panel control is highlighted
//   (primary indicator dot + "(active)" Accessible name — color is
//   never the only indicator) and the workspace area gains a subtle
//   scrim so overlays never obscure critical information
//   (07_DESKTOP_LAYOUT.md acceptance criterion).
//
// Interpretation notes (documented — no authoritative source specifies
// further detail):
//   - No wallpaper asset is shipped yet, so the backdrop is a calm
//     token-only vertical gradient plus a subtle scrim (same treatment
//     as the lock family); the host may layer a real wallpaper behind.
//   - No icon assets ship, so every control is a text-labeled token
//     control (the established MissionButton pattern) and dock
//     application tiles show the app's initial like the lock-family
//     avatar treatment.
//   - Application lists (runningApps / pinnedApps) are host-driven:
//     each entry is { id, name }. A pinned dock tile shows a running
//     indicator when its id is present in runningApps. Taskbar buttons
//     size to their label, so hosts should keep app names short (the
//     running-apps row clips visually on narrow widths).
//   - Clicking a taskbar or dock application emits the corresponding
//     activation signal with the app id; launching/switching windows is
//     the host's job.
//   - Escape is deliberately unmapped (same contract as the lock family
//     and the installer Completion screen): the desktop must not
//     dismiss itself — the host owns overlay dismissal.
//
// Design-system compliance:
//   - Tokens only (Colors, Typography, Spacing, Radii, Motion, MissionTheme)
//   - Light + dark themes via MissionTheme (driven by host)
//   - Keyboard navigation with visible focus states; 44px minimum
//     touch targets (Spacing.minimumTouchTarget)
//   - WCAG AA-oriented contrast, reduced-motion aware
//   - Responsive reflow per docs/design/14_RESPONSIVE_RULES.md
//     (compactLayout trims the status chip labels on narrow widths)

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.mission.ui 1.0

FocusScope {
    id: root

    implicitWidth: 1280
    implicitHeight: 720

    // ── Public API ─────────────────────────────────────────────────
    /// Desktop overlay state (wireframe states): "idle" |
    /// "notifications" | "workspaceSwitching" | "search" — drives the
    /// active highlight on the matching panel control and a subtle
    /// workspace scrim. The overlays themselves are separate screens
    /// (MOS-DES-002/003/004/005); the host shows them.
    property string overlayState: "idle"

    /// Reduced motion (accessibility)
    property bool reducedMotion: false

    /// Running applications: [{ id, name }] — host-driven; shown as
    /// taskbar buttons in the top panel
    property var runningApps: []

    /// Pinned applications: [{ id, name }] — host-driven; shown as
    /// dock tiles with a running indicator when the id is in
    /// runningApps
    property var pinnedApps: []

    /// Current workspace number (1-based) shown by the Workspace
    /// Indicator
    property int currentWorkspace: 1
    /// Total number of workspaces shown by the Workspace Indicator
    property int workspaceCount: 1

    /// Dock visibility (host-driven; supports the layout doc's
    /// auto-hide capability — interactive edge-reveal is host-side)
    property bool dockVisible: true

    /// Signed-in user display name for the User Menu entry
    property string userName: ""

    /// Live clock time text (e.g. "14:32"). The component updates it
    /// from the system clock while clockRunning is true; hosts pin it
    /// by setting it and disabling the timer.
    property string clockTimeText: ""
    /// When true, a 30s timer keeps the clock text current
    property bool clockRunning: true

    /// Network status label (e.g. "Connected" / "Offline") — host-driven
    property string networkStatusText: qsTr("Connected")
    /// Whether the network is up (drives the status dot color; the dot
    /// is never the only indicator — the label always carries the text)
    property bool networkConnected: true

    /// Battery status label (e.g. "100%") — host-driven
    property string batteryStatusText: "100%"
    /// Battery level 0-100 (drives the fill width + semantic color)
    property int batteryLevel: 100

    // ── Signals (host wiring) ──────────────────────────────────────
    /// User requested the Mission Menu (launcher) — host-driven
    signal missionMenuRequested()
    /// User requested the User Menu — host-driven
    signal userMenuRequested()
    /// User requested the Workspace Switcher (routes to MOS-DES-002)
    signal workspaceSwitchRequested()
    /// User requested the Notification Center (routes to MOS-DES-003)
    signal notificationsRequested()
    /// User requested Quick Settings (routes to MOS-DES-004)
    signal quickSettingsRequested()
    /// User requested Search (routes to MOS-DES-005)
    signal searchRequested()
    /// User clicked a running application in the top panel taskbar
    signal runningAppActivated(string appId)
    /// User clicked a pinned application in the dock
    signal pinnedAppActivated(string appId)

    // Escape is deliberately unmapped (see interpretation notes): the
    // desktop must not dismiss itself. No Keys.onEscapePressed here.

    // ── Derived helpers ────────────────────────────────────────────
    /// Backdrop base color (theme-aware; test hook). Equivalent to the
    /// wallpaper gradient's top stop, which is bound to
    /// MissionTheme.background.
    readonly property color backdropColor: MissionTheme.background

    /// Whether a desktop overlay is currently active (wireframe states)
    readonly property bool overlayActive: root.overlayState !== "idle"

    /// Compact layout: narrow widths trim the status chip labels so the
    /// panel never overflows (docs/design/14_RESPONSIVE_RULES.md)
    readonly property bool compactLayout: root.width < 1024

    /// Whether an app id is in the running-apps list (drives the dock
    /// running indicators)
    function isRunning(appId) {
        for (var i = 0; i < root.runningApps.length; ++i) {
            if (String(root.runningApps[i].id) === String(appId))
                return true
        }
        return false
    }

    // ── Clock helpers ──────────────────────────────────────────────
    /// Refresh the clock text from the system clock (host wiring / tests)
    function updateClock() {
        var now = new Date()
        root.clockTimeText = Qt.formatTime(now, "HH:mm")
    }

    // ── Test hooks (used by tests/tst_desktop.qml) ─────────────────
    property alias backdropRect: wallpaperRect
    property alias topPanel: topPanel
    property alias missionMenuButton: missionMenuButton
    property alias searchButton: searchButton
    property alias searchActiveDot: searchActiveDot
    property alias workspaceIndicator: workspaceIndicator
    property alias workspaceActiveDot: workspaceActiveDot
    property alias runningAppsRepeater: runningAppsRepeater
    property alias clockLabel: clockLabel
    property alias networkChip: networkChip
    property alias networkStatusLabel: networkStatusLabel
    property alias networkDot: networkDot
    property alias batteryChip: batteryChip
    property alias batteryStatusLabel: batteryStatusLabel
    property alias batteryFill: batteryFill
    property alias notificationsButton: notificationsButton
    property alias notificationsActiveDot: notificationsActiveDot
    property alias quickSettingsButton: quickSettingsButton
    property alias userMenuButton: userMenuButton
    property alias dock: dock
    property alias dockRepeater: dockRepeater
    property alias workspaceScrim: workspaceScrim

    // ── Wallpaper backdrop (token gradient + scrim) ────────────────
    Rectangle {
        id: wallpaperRect
        anchors.fill: parent
        // Calm token-only gradient standing in for the wallpaper until a
        // real wallpaper asset ships (see interpretation notes).
        gradient: Gradient {
            GradientStop { position: 0.0; color: MissionTheme.background }
            GradientStop { position: 1.0; color: MissionTheme.surfaceVariant }
        }

        // Subtle scrim improves contrast for the panel + dock
        Rectangle {
            anchors.fill: parent
            color: Colors.scrim
            opacity: MissionTheme.darkMode ? 0.0 : 0.06
        }
    }

    // ══════════════════════════════════════════════════════════════
    // Top Panel (07_DESKTOP_LAYOUT.md §3 — always visible)
    // ══════════════════════════════════════════════════════════════
    Rectangle {
        id: topPanel
        objectName: "desktopTopPanel"
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        height: Spacing.headerHeight
        // Subtle token surface so the panel reads as chrome over the
        // wallpaper without fighting the theme
        color: MissionTheme.surface
        opacity: 0.92
        border.color: MissionTheme.outlineVariant
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Spacing.paddingMedium
            anchors.rightMargin: Spacing.paddingMedium
            spacing: Spacing.gapSmall

            // ── Mission Menu ──
            MissionButton {
                id: missionMenuButton
                objectName: "desktopMenu"
                variant: MissionButton.Variant.Secondary
                compact: true
                text: qsTr("Menu")
                onClicked: root.missionMenuRequested()
                Accessible.description: qsTr("Open the application menu")
            }

            // ── Search (routes to MOS-DES-005) ──
            Item {
                Layout.preferredWidth: searchButton.implicitWidth
                Layout.preferredHeight: 44

                MissionButton {
                    id: searchButton
                    objectName: "desktopSearch"
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    variant: MissionButton.Variant.Secondary
                    compact: true
                    text: qsTr("Search")
                    onClicked: root.searchRequested()
                    Accessible.name: root.overlayState === "search"
                                     ? qsTr("Search (active)") : qsTr("Search")
                    Accessible.description: qsTr("Open search")
                }

                // Active-overlay indicator (wireframe "Search Active"
                // state; the Accessible name above carries the text so
                // color is never the only indicator)
                Rectangle {
                    id: searchActiveDot
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 2
                    width: 5
                    height: 5
                    radius: 3
                    visible: root.overlayState === "search"
                    color: MissionTheme.primary
                }
            }

            // ── Workspace Indicator (routes to MOS-DES-002) ──
            Item {
                Layout.preferredWidth: workspaceIndicator.implicitWidth
                Layout.preferredHeight: 44

                MissionButton {
                    id: workspaceIndicator
                    objectName: "desktopWorkspace"
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    variant: MissionButton.Variant.Secondary
                    compact: true
                    text: "%1 / %2".arg(root.currentWorkspace).arg(root.workspaceCount)
                    onClicked: root.workspaceSwitchRequested()
                    Accessible.name: root.overlayState === "workspaceSwitching"
                                     ? qsTr("Workspace %1 of %2 (active)")
                                         .arg(root.currentWorkspace).arg(root.workspaceCount)
                                     : qsTr("Workspace %1 of %2")
                                         .arg(root.currentWorkspace).arg(root.workspaceCount)
                    Accessible.description: qsTr("Open the workspace switcher")
                }

                Rectangle {
                    id: workspaceActiveDot
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 2
                    width: 5
                    height: 5
                    radius: 3
                    visible: root.overlayState === "workspaceSwitching"
                    color: MissionTheme.primary
                }
            }

            // ── Running Applications (taskbar) ──
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: parent.height
                spacing: Spacing.gapTiny
                clip: true

                Repeater {
                    id: runningAppsRepeater
                    model: root.runningApps

                    delegate: MissionButton {
                        required property var modelData
                        required property int index

                        objectName: "desktopRunning" + index
                        variant: MissionButton.Variant.Secondary
                        compact: true
                        text: String(modelData.name)
                        onClicked: root.runningAppActivated(String(modelData.id))
                        Accessible.description: qsTr("Switch to %1").arg(String(modelData.name))
                    }
                }
            }

            // ── Clock ──
            Label {
                id: clockLabel
                objectName: "desktopClock"
                text: root.clockTimeText
                font.pixelSize: Typography.bodySmall.size
                font.weight: Typography.weightMedium
                color: MissionTheme.textPrimary
                verticalAlignment: Text.AlignVCenter
                Accessible.role: Accessible.StaticText
                Accessible.name: qsTr("Current time: %1").arg(text)
            }

            // ── System Status chips (family token pattern) ──
            Rectangle {
                id: networkChip
                visible: !root.compactLayout
                height: Spacing.minimumTouchTarget - Spacing.gapSmall * 2
                width: networkRow.implicitWidth + Spacing.paddingMedium * 2
                radius: Radii.chip
                color: MissionTheme.surface
                border.color: MissionTheme.outlineVariant
                border.width: 1

                RowLayout {
                    id: networkRow
                    anchors.centerIn: parent
                    spacing: Spacing.gapSmall

                    Rectangle {
                        id: networkDot
                        Layout.preferredWidth: 6
                        Layout.preferredHeight: 6
                        radius: 3
                        color: root.networkConnected ? MissionTheme.success
                                                     : MissionTheme.textTertiary
                    }
                    Label {
                        id: networkStatusLabel
                        objectName: "desktopNetworkStatus"
                        text: root.networkStatusText
                        font.pixelSize: Typography.bodySmall.size
                        color: MissionTheme.textPrimary
                    }
                }

                Accessible.role: Accessible.Grouping
                Accessible.name: qsTr("Network status: %1").arg(root.networkStatusText)
            }

            Rectangle {
                id: batteryChip
                visible: !root.compactLayout
                height: Spacing.minimumTouchTarget - Spacing.gapSmall * 2
                width: batteryRow.implicitWidth + Spacing.paddingMedium * 2
                radius: Radii.chip
                color: MissionTheme.surface
                border.color: MissionTheme.outlineVariant
                border.width: 1

                RowLayout {
                    id: batteryRow
                    anchors.centerIn: parent
                    spacing: Spacing.gapSmall

                    // Mini battery bar (token colors; label carries
                    // the text so color is never the only indicator)
                    Rectangle {
                        Layout.preferredWidth: 18
                        Layout.preferredHeight: 8
                        radius: 2
                        color: MissionTheme.surfaceDim
                        border.color: MissionTheme.outline
                        border.width: 1

                        Rectangle {
                            id: batteryFill
                            anchors {
                                left: parent.left
                                top: parent.top
                                bottom: parent.bottom
                                margins: 1
                            }
                            width: Math.max(2, (parent.width - 2) *
                                               Math.min(1, Math.max(0, root.batteryLevel / 100)))
                            radius: 1
                            color: root.batteryLevel <= 20 ? MissionTheme.warning
                                                           : MissionTheme.success
                        }
                    }
                    Label {
                        id: batteryStatusLabel
                        objectName: "desktopBatteryStatus"
                        text: root.batteryStatusText
                        font.pixelSize: Typography.bodySmall.size
                        color: MissionTheme.textPrimary
                    }
                }

                Accessible.role: Accessible.Grouping
                Accessible.name: qsTr("Battery status: %1").arg(root.batteryStatusText)
            }

            // ── Notifications (routes to MOS-DES-003) ──
            Item {
                Layout.preferredWidth: notificationsButton.implicitWidth
                Layout.preferredHeight: 44

                MissionButton {
                    id: notificationsButton
                    objectName: "desktopNotifications"
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    variant: MissionButton.Variant.Secondary
                    compact: true
                    text: qsTr("Notify")
                    onClicked: root.notificationsRequested()
                    Accessible.name: root.overlayState === "notifications"
                                     ? qsTr("Notifications (active)") : qsTr("Notifications")
                    Accessible.description: qsTr("Open notifications")
                }

                Rectangle {
                    id: notificationsActiveDot
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 2
                    width: 5
                    height: 5
                    radius: 3
                    visible: root.overlayState === "notifications"
                    color: MissionTheme.primary
                }
            }

            // ── Quick Settings (routes to MOS-DES-004) ──
            MissionButton {
                id: quickSettingsButton
                objectName: "desktopQuickSettings"
                variant: MissionButton.Variant.Secondary
                compact: true
                text: qsTr("Settings")
                onClicked: root.quickSettingsRequested()
                Accessible.description: qsTr("Open quick settings")
            }

            // ── User Menu ──
            MissionButton {
                id: userMenuButton
                objectName: "desktopUserMenu"
                variant: MissionButton.Variant.Secondary
                compact: true
                text: root.userName.length > 0 ? root.userName : qsTr("User")
                onClicked: root.userMenuRequested()
                Accessible.description: qsTr("Open the user menu")
            }
        }
    }

    // ══════════════════════════════════════════════════════════════
    // Workspace Area (07_DESKTOP_LAYOUT.md §5 — primary working area)
    // ══════════════════════════════════════════════════════════════
    Item {
        id: workspaceArea
        anchors {
            left: parent.left
            right: parent.right
            top: topPanel.bottom
            bottom: parent.bottom
        }

        // Subtle scrim while an overlay is active so overlays never
        // obscure critical information (layout acceptance criterion;
        // interpreted — a gentle dim, not a modal blackout)
        Rectangle {
            id: workspaceScrim
            objectName: "desktopWorkspaceScrim"
            anchors.fill: parent
            color: Colors.scrim
            opacity: root.overlayActive ? 0.08 : 0.0
            Behavior on opacity {
                enabled: !root.reducedMotion
                animation: NumberAnimation { duration: Motion.fadeIn }
            }
        }
    }

    // ══════════════════════════════════════════════════════════════
    // Dock (07_DESKTOP_LAYOUT.md §4 — pinned + running applications;
    // floats over the wallpaper at the bottom of the workspace)
    // ══════════════════════════════════════════════════════════════
    Rectangle {
        id: dock
        objectName: "desktopDock"
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: 72
        visible: root.dockVisible
        color: MissionTheme.surface
        opacity: 0.92
        border.color: MissionTheme.outlineVariant
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Spacing.paddingLarge
            anchors.rightMargin: Spacing.paddingLarge
            spacing: Spacing.gapSmall

            // Pinned applications (host-driven; running indicator when
            // the id is in runningApps)
            Repeater {
                id: dockRepeater
                model: root.pinnedApps

                delegate: Rectangle {
                    required property var modelData
                    required property int index

                    id: pinnedTile
                    objectName: "desktopPinned" + index
                    width: 48
                    height: 48
                    radius: Radii.card
                    color: pinnedTileMouse.containsMouse ? MissionTheme.surfaceVariant
                                                         : MissionTheme.surfaceDim
                    border.width: 1
                    border.color: MissionTheme.outlineVariant
                    activeFocusOnTab: true

                    Behavior on color {
                        enabled: !root.reducedMotion
                        animation: ColorAnimation { duration: Motion.colorChange }
                    }

                    // Visible focus ring (keyboard navigation)
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -2
                        radius: Radii.card + 2
                        color: "transparent"
                        border.color: MissionTheme.focusRing
                        border.width: 2
                        visible: pinnedTile.activeFocus
                    }

                    // App initial (no icon assets ship — inline
                    // treatment, same as the lock-family avatars)
                    Label {
                        anchors.centerIn: parent
                        text: String(modelData.name).length > 0
                              ? String(modelData.name).charAt(0).toUpperCase() : "\u2022"
                        font.pixelSize: Typography.title.size
                        font.weight: Typography.weightSemibold
                        color: MissionTheme.textPrimary
                    }

                    // Running indicator (top-right; color is never the
                    // only indicator — the Accessible name carries it)
                    Rectangle {
                        anchors {
                            top: parent.top
                            right: parent.right
                            margins: 3
                        }
                        width: 8
                        height: 8
                        radius: 4
                        visible: root.isRunning(modelData.id)
                        color: MissionTheme.primary
                    }

                    MouseArea {
                        id: pinnedTileMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            pinnedTile.forceActiveFocus()
                            root.pinnedAppActivated(String(modelData.id))
                        }
                    }

                    Keys.onReturnPressed: root.pinnedAppActivated(String(modelData.id))
                    Keys.onSpacePressed: root.pinnedAppActivated(String(modelData.id))

                    Accessible.role: Accessible.Button
                    Accessible.name: root.isRunning(modelData.id)
                                     ? qsTr("%1 (running)").arg(String(modelData.name))
                                     : String(modelData.name)
                }
            }

            Item { Layout.fillWidth: true }

            // Workspace count summary (right side of the dock; the
            // workspace switcher itself is MOS-DES-002). Shows the
            // multi-workspace count when there is more than one, and a
            // single "1 workspace" only when the dock is otherwise
            // empty so the bar never looks abandoned (interpreted).
            Label {
                text: root.workspaceCount > 1
                      ? qsTr("%1 workspaces").arg(root.workspaceCount)
                      : qsTr("1 workspace")
                font.pixelSize: Typography.caption.size
                color: MissionTheme.textSecondary
                visible: root.workspaceCount > 1 || root.pinnedApps.length === 0
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }
        }
    }

    // ── Clock timer (host-disabled via clockRunning) ───────────────
    Timer {
        id: clockTimer
        interval: 30000
        repeat: true
        running: root.clockRunning
        triggeredOnStart: true
        onTriggered: root.updateClock()
    }

    Component.onCompleted: {
        // Seed the clock once so it is never empty at first paint
        root.updateClock()
    }
}
