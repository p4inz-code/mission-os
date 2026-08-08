// Mission OS — Installer Keyboard Selection (MOS-INS-003)
//
// Third screen of the Mission OS installer.
// Implements the source-defined Keyboard structure (docs/wireframes/
// 01_INSTALLER.md + docs/reference/01_INSTALLER.md Screen 09):
//
//   Hosting: place inside MissionWindow (or MissionPage) content and
//   anchor to fill, e.g.  MissionWindow { KeyboardSelection { anchors.fill: parent } }
//   The component itself sizes to its implicit 1024x768 like MissionPage.
//
//   Header → Stepper Navigation → Main Content → Help Panel → Bottom actions
//
// Displayed items (per registry MOS-INS-003 "Keyboard", reference Screen 09
// "Keyboard & Input"):
//   - Keyboard layout list (US, UK, German, French, Japanese, Indian, Custom)
//   - Keyboard test / capture area ("Users can test their keyboard before
//     continuing") — a focused key-capture field; Escape clears/exits the
//     test area without trapping focus
//   - Platform preset selector (Linux (Default) / Windows / macOS) reusing
//     the LanguageSelection region-chip pattern (Segmented Control is not
//     implemented yet — chips are the established inline pattern)
//   - Live feedback of the current selection
//   - Back / Continue (wireframe UX rules: linear workflow, back always
//     available, validation before continuing)
//
// States (per wireframe): empty · loading · error · success · offline
// The screen exposes *Requested signals; the host application decides what
// each action does (e.g. applying the layout via xkbcommon).
//
// Escape precedence (same parent-vs-child rule as 002's search field):
//   while the key-capture test area is focused, Escape clears/exits the
//   test area (focus is never trapped); elsewhere, root Escape →
//   backRequested().
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
    property int step: 3

    /// Total number of installer steps (screen registry: 12)
    property int totalSteps: 17

    /// Reduced motion (accessibility)
    property bool reducedMotion: false

    /// Installer/OS version string shown in the header
    property string version: "0.1.0"

    /// Build channel: Stable | Beta | Nightly
    property string buildType: "Nightly"

    /// Available keyboard layouts. Each entry: { label, code }.
    /// Static fixture — the host service (xkbcommon) applies the real
    /// layout when keyboardLayoutChangeRequested fires.
    property var layouts: [
        { label: "US", code: "us" },
        { label: "UK", code: "uk" },
        { label: "German", code: "de" },
        { label: "French", code: "fr" },
        { label: "Japanese", code: "ja" },
        { label: "Indian", code: "in" },
        { label: "Custom", code: "custom" }
    ]

    /// Available platform presets. Each entry: { label, code }.
    /// Linux is the default; presets can be switched at any time after
    /// installation (reference Screen 09).
    property var presets: [
        { label: "Linux (Default)", code: "linux" },
        { label: "Windows", code: "windows" },
        { label: "macOS", code: "macos" }
    ]

    /// Index of the selected layout within `layouts`
    property int selectedLayoutIndex: 0

    /// The selected layout object (from `layouts`)
    property var selectedLayout: root.layouts.length > 0 ? root.layouts[0] : null

    /// Currently selected layout label. Preselected to the first layout
    /// (US) so the screen loads with a valid selection (no signal is
    /// emitted on load — the host already knows the default layout).
    property string currentLayoutLabel: root.layouts.length > 0 ? root.layouts[0].label : ""

    /// Currently selected layout code (e.g. "us")
    property string currentLayoutCode: root.layouts.length > 0 ? root.layouts[0].code : ""

    /// Index of the selected preset within `presets`
    property int selectedPresetIndex: 0

    /// The selected preset object (from `presets`)
    property var selectedPreset: root.presets.length > 0 ? root.presets[0] : null

    /// Currently selected preset label. Preselected to Linux (the default)
    /// without emitting on load.
    property string currentPresetLabel: root.presets.length > 0 ? root.presets[0].label : ""

    /// Currently selected preset code ("linux" | "windows" | "macos")
    property string currentPresetCode: root.presets.length > 0 ? root.presets[0].code : ""

    // ── Signals (host wiring) ──────────────────────────────────────
    /// User requested to continue to the next step
    signal continueRequested()
    /// User requested to go back to the previous step
    signal backRequested()
    /// User selected a keyboard layout (layout code, e.g. "us")
    signal keyboardLayoutChangeRequested(string code)
    /// User selected a platform preset ("linux" | "windows" | "macos")
    signal platformPresetChangeRequested(string preset)
    /// User requested to retry after an error
    signal retryRequested()

    // ── Escape navigates back (Master UX: Back always available) ──
    // While the key-capture test area is focused, its own Escape handler
    // clears the capture and accepts the event, so this root handler only
    // fires when the test area does not have focus (Escape precedence).
    Keys.onEscapePressed: root.backRequested()

    // ── Responsive helpers ─────────────────────────────────────────
    readonly property bool wideLayout: root.width >= 760
    readonly property bool compactLayout: root.width < 640

    // ── Selection helpers ──────────────────────────────────────────
    function selectLayout(index) {
        if (index < 0 || index >= root.layouts.length)
            return
        var layout = root.layouts[index]
        root.selectedLayoutIndex = index
        root.selectedLayout = layout
        root.currentLayoutLabel = layout.label
        root.currentLayoutCode = layout.code
        root.keyboardLayoutChangeRequested(root.currentLayoutCode)
    }

    function selectPreset(index) {
        if (index < 0 || index >= root.presets.length)
            return
        var preset = root.presets[index]
        root.selectedPresetIndex = index
        root.selectedPreset = preset
        root.currentPresetLabel = preset.label
        root.currentPresetCode = preset.code
        root.platformPresetChangeRequested(root.currentPresetCode)
    }

    // ── Test hooks (used by tests/tst_keyboard.qml) ────────────────
    property alias backgroundColor: backgroundRect.color
    property alias headingColor: headingLabel.color
    property alias headingLabel: headingLabel
    property alias layoutList: layoutList
    property alias testField: testField
    property alias clearTestButton: clearTestButton
    property alias presetRows: presetRows
    property alias presetSection: presetSection
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
                text: qsTr("Step %1 of %2 · Keyboard").arg(root.step).arg(root.totalSteps)
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
                            text: qsTr("Loading keyboard settings…")
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
                        // invisible even when `visible` is true.
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
                                    text: qsTr("Keyboard settings could not be loaded")
                                    font.weight: Typography.weightSemibold
                                    color: Colors.contentOnErrorContainer
                                }
                                Label {
                                    text: qsTr("The keyboard catalog could not be verified. Check the installation media and try again.")
                                    font.pixelSize: Typography.bodySmall.size
                                    color: Colors.contentOnErrorContainer
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                            MissionButton {
                                id: retryButton
                                objectName: "keyboardRetry"
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
                                    text: qsTr("Keyboard settings saved")
                                    font.weight: Typography.weightSemibold
                                    color: Colors.contentOnSuccessContainer
                                }
                                Label {
                                    text: qsTr("Your keyboard layout and platform preset will be used throughout the installation.")
                                    font.pixelSize: Typography.bodySmall.size
                                    color: Colors.contentOnSuccessContainer
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }

                    // Offline (informational — no online service required for this step)
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
                                    text: qsTr("This step works without an internet connection. Keyboard layouts and platform presets are included on the installation media.")
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
                        text: qsTr("Select your keyboard")
                        width: parent.width
                        font.pixelSize: Typography.headline.size
                        font.weight: Typography.headline.weight
                        color: MissionTheme.textPrimary
                        wrapMode: Text.Wrap
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    Label {
                        text: qsTr("Choose the keyboard layout and shortcut style used by the installer and the installed system. You can test your keyboard before continuing.")
                        width: parent.width
                        font.pixelSize: Typography.bodyLarge.size
                        color: MissionTheme.textSecondary
                        wrapMode: Text.Wrap
                        lineHeight: Typography.lineHeightRelaxed
                    }

                    // ── Keyboard layout list (no search — not specified
                    //    for this screen; only Screen 08 has search) ──
                    Label {
                        text: qsTr("Keyboard layout")
                        width: parent.width
                        font.pixelSize: Typography.subtitle.size
                        font.weight: Typography.subtitle.weight
                        color: MissionTheme.textPrimary
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    ListView {
                        id: layoutList
                        objectName: "keyboardList"
                        width: parent.width
                        // All rows visible by default; capped so the list
                        // never dominates short windows (scrolls inside).
                        height: Math.min(root.layouts.length * Spacing.minimumTouchTarget
                                         + (root.layouts.length - 1) * Spacing.gapTiny,
                                         396)
                        clip: true
                        model: root.layouts
                        spacing: Spacing.gapTiny
                        activeFocusOnTab: true
                        keyNavigationWraps: true
                        highlightFollowsCurrentItem: true
                        ScrollIndicator.vertical: ScrollIndicator {}
                        onCountChanged: {
                            if (layoutList.count > 0 && layoutList.currentIndex < 0)
                                layoutList.currentIndex = 0
                        }
                        Keys.onReturnPressed: root.selectLayout(layoutList.currentIndex)
                        Keys.onSpacePressed: root.selectLayout(layoutList.currentIndex)
                        Accessible.role: Accessible.List
                        Accessible.name: qsTr("Keyboard layouts")

                        delegate: Rectangle {
                            id: layoutDelegate
                            required property var modelData
                            required property int index

                            // When the list is reached via Tab, focus lands on
                            // the currentItem delegate — not on the ListView
                            // itself — so the delegate carries the objectName
                            // used by the keyboard-focus test.
                            objectName: "keyboardItem" + index
                            width: layoutList.width
                            height: Spacing.minimumTouchTarget
                            radius: Radii.input
                            color: {
                                if (root.selectedLayoutIndex === index)
                                    return MissionTheme.darkMode ? MissionTheme.primary
                                                                 : MissionTheme.primaryContainer
                                if (layoutList.currentIndex === index && layoutList.activeFocus)
                                    return MissionTheme.surfaceVariant
                                if (layoutDelegateMouse.containsMouse)
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
                                visible: layoutList.currentIndex === index &&
                                         layoutList.activeFocus
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Spacing.paddingMedium
                                anchors.rightMargin: Spacing.paddingMedium
                                spacing: Spacing.gapMedium

                                Label {
                                    text: modelData.label
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    font.pixelSize: Typography.body.size
                                    font.weight: root.selectedLayoutIndex === index
                                                 ? Typography.weightSemibold : Typography.weightRegular
                                    color: root.selectedLayoutIndex === index
                                         ? (MissionTheme.darkMode ? MissionTheme.contentOnPrimary
                                                                 : MissionTheme.contentOnPrimaryContainer)
                                         : MissionTheme.textPrimary
                                }

                                Label {
                                    text: modelData.code
                                    font.pixelSize: Typography.caption.size
                                    color: root.selectedLayoutIndex === index
                                         ? (MissionTheme.darkMode ? MissionTheme.contentOnPrimary
                                                                 : MissionTheme.contentOnPrimaryContainer)
                                         : MissionTheme.textTertiary
                                }
                            }

                            MouseArea {
                                id: layoutDelegateMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    layoutList.currentIndex = index
                                    root.selectLayout(index)
                                }
                            }

                            Accessible.role: Accessible.ListItem
                            Accessible.name: modelData.label + ", " + modelData.code
                            Accessible.selected: root.selectedLayoutIndex === index
                        }
                    }

                    // ── Keyboard test / capture area ──
                    // Reference Screen 09: "Users can test their keyboard
                    // before continuing." A focused key-capture field that
                    // shows what the user types; Escape clears/exits without
                    // trapping focus (Tab still leaves the field).
                    Label {
                        text: qsTr("Test your keyboard")
                        width: parent.width
                        font.pixelSize: Typography.subtitle.size
                        font.weight: Typography.subtitle.weight
                        color: MissionTheme.textPrimary
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    RowLayout {
                        width: parent.width
                        spacing: Spacing.gapMedium

                        TextField {
                            id: testField
                            objectName: "keyboardTest"
                            Layout.fillWidth: true
                            Layout.preferredHeight: Spacing.minimumTouchTarget
                            placeholderText: qsTr("Type here to test your keyboard")
                            font.pixelSize: Typography.body.size
                            color: MissionTheme.textPrimary
                            placeholderTextColor: MissionTheme.textTertiary
                            selectByMouse: true
                            leftPadding: Spacing.paddingMedium
                            rightPadding: Spacing.paddingMedium
                            Keys.onEscapePressed: {
                                testField.text = ""
                                testField.focus = true
                            }
                            background: Rectangle {
                                radius: Radii.input
                                color: MissionTheme.surface
                                border.width: testField.activeFocus ? 2 : 1
                                border.color: testField.activeFocus ? MissionTheme.focusRing : MissionTheme.outline
                            }
                            Accessible.role: Accessible.EditableText
                            Accessible.name: qsTr("Keyboard test area")
                            Accessible.description: qsTr("Type to verify your keyboard works. Press Escape to clear.")
                        }

                        MissionButton {
                            id: clearTestButton
                            objectName: "keyboardClear"
                            variant: MissionButton.Variant.Secondary
                            text: qsTr("Clear")
                            onClicked: testField.text = ""
                        }
                    }

                    Label {
                        text: qsTr("Press Escape to clear the captured text. Tab leaves this field — focus is never trapped.")
                        width: parent.width
                        font.pixelSize: Typography.caption.size
                        color: MissionTheme.textTertiary
                        wrapMode: Text.Wrap
                    }

                    // ── Platform preset selector (Linux default) ──
                    // NOTE: this screen's content lives in a plain Column
                    // (inside the Flickable), so `Layout.fillWidth` would be
                    // silently ignored — explicit widths are used instead.
                    Column {
                        id: presetSection
                        width: parent.width
                        spacing: Spacing.gapSmall

                        Label {
                            text: qsTr("Platform shortcuts")
                            font.pixelSize: Typography.subtitle.size
                            font.weight: Typography.subtitle.weight
                            color: MissionTheme.textPrimary
                            Accessible.role: Accessible.Heading
                            Accessible.name: text
                        }

                        // Inline chips (Segmented Control not yet shipped —
                        // reuse the LanguageSelection region-chip pattern).
                        Flow {
                            width: parent.width
                            spacing: Spacing.gapSmall

                            Repeater {
                                id: presetRows
                                model: root.presets

                                delegate: Rectangle {
                                    id: presetDelegate
                                    required property var modelData
                                    required property int index

                                    objectName: "presetItem" + index
                                    height: Spacing.minimumTouchTarget
                                    width: presetLabel.implicitWidth + Spacing.paddingMedium * 2
                                    radius: Radii.chip
                                    color: index === root.selectedPresetIndex
                                         ? (MissionTheme.darkMode ? MissionTheme.primary
                                                                 : MissionTheme.primaryContainer)
                                         : (presetMouse.containsMouse ? MissionTheme.surfaceVariant
                                                                     : MissionTheme.surface)
                                    border.width: index === root.selectedPresetIndex ? 0 : 1
                                    border.color: MissionTheme.outline
                                    activeFocusOnTab: true

                                    Behavior on color {
                                        enabled: !root.reducedMotion
                                        animation: ColorAnimation { duration: Motion.colorChange }
                                    }

                                    // Visible focus ring
                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.margins: -2
                                        radius: Radii.chip + 2
                                        color: "transparent"
                                        border.color: MissionTheme.focusRing
                                        border.width: 2
                                        visible: presetDelegate.activeFocus
                                    }

                                    Label {
                                        id: presetLabel
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        font.pixelSize: Typography.bodySmall.size
                                        font.weight: index === root.selectedPresetIndex
                                                     ? Typography.weightSemibold : Typography.weightRegular
                                        color: index === root.selectedPresetIndex
                                             ? (MissionTheme.darkMode ? MissionTheme.contentOnPrimary
                                                                     : MissionTheme.contentOnPrimaryContainer)
                                             : MissionTheme.textPrimary
                                    }

                                    MouseArea {
                                        id: presetMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: root.selectPreset(index)
                                    }

                                    Keys.onReturnPressed: root.selectPreset(index)
                                    Keys.onSpacePressed: root.selectPreset(index)

                                    Accessible.role: Accessible.RadioButton
                                    Accessible.name: modelData.label
                                    Accessible.checked: index === root.selectedPresetIndex
                                }
                            }
                        }

                        // Reference Screen 09: presets can be switched at any
                        // time after installation.
                        Label {
                            text: qsTr("Linux is the default. You can change the platform preset at any time after installation.")
                            width: parent.width
                            font.pixelSize: Typography.caption.size
                            color: MissionTheme.textTertiary
                            wrapMode: Text.Wrap
                        }
                    }

                    // ── Live selection feedback ──
                    Label {
                        id: selectionCaption
                        width: parent.width
                        visible: root.currentLayoutCode.length > 0
                        text: qsTr("Selected: %1 layout · %2 preset").arg(root.currentLayoutLabel)
                                                                     .arg(root.currentPresetLabel)
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
                        text: qsTr("Type in the test area to make sure every key works before continuing. Then pick the platform preset that matches the shortcuts you already know.")
                        width: parent.width
                        font.pixelSize: Typography.bodySmall.size
                        color: MissionTheme.textSecondary
                        wrapMode: Text.Wrap
                        lineHeight: Typography.lineHeightNormal
                    }

                    Item { width: 1; height: Spacing.gapSmall }

                    Label {
                        text: qsTr("You can switch the platform preset at any time after installation.")
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
                objectName: "keyboardBack"
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
                objectName: "keyboardContinue"
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
