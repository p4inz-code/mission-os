// Mission OS — Installer Language Selection (MOS-INS-002)
//
// Second screen of the Mission OS installer.
// Implements the source-defined Language screen structure
// (docs/wireframes/01_INSTALLER.md + docs/reference/01_INSTALLER.md):
//
//   Hosting: place inside MissionWindow (or MissionPage) content and
//   anchor to fill, e.g.  MissionWindow { LanguageSelection { anchors.fill: parent } }
//   The component itself sizes to its implicit 1024x768 like MissionPage.
//
//   Header → Stepper Navigation → Main Content → Help Panel → Bottom actions
//
// Displayed items (per registry MOS-INS-002 "Language", reference Screen 08
// "Region & Language"):
//   - Full language list (label + locale code)
//   - Search / filter (reference Screen 08: "Search by city or country" →
//     searchable locale selection; applied here to languages)
//   - Region / variant picker for languages with regional variants
//     (reference Screen 08 "Region" option, applied per-language)
//   - Live feedback of the current selection
//   - Back / Continue (wireframe UX rules: linear workflow, back always
//     available, validation before continuing)
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
    property int step: 2

    /// Total number of installer steps (screen registry: 12)
    property int totalSteps: 17

    /// Reduced motion (accessibility)
    property bool reducedMotion: false

    /// Installer/OS version string shown in the header
    property string version: "0.1.0"

    /// Build channel: Stable | Beta | Nightly
    property string buildType: "Nightly"

    /// Search query used to filter the language list
    property string searchText: ""

    /// Currently selected language label. Preselected to the first language
    /// so the screen loads with a valid selection (no signal is emitted on
    /// load — the host already knows the default locale).
    property string currentLanguage: root.languages.length > 0 ? root.languages[0].label : ""

    /// Currently selected locale code (language + region)
    property string currentLocale: root.languages.length > 0
        ? (root.languages[0].regions && root.languages[0].regions.length > 0
           ? root.languages[0].regions[0].code : root.languages[0].code)
        : ""

    /// Currently selected region label (empty when the language is regionless)
    property string currentRegion: root.languages.length > 0
        ? (root.languages[0].regions && root.languages[0].regions.length > 0
           ? root.languages[0].regions[0].label : "")
        : ""

    /// The selected language object (from `languages`)
    property var selectedLanguage: root.languages.length > 0 ? root.languages[0] : null

    /// Index of the selected region within the selected language's regions
    property int selectedRegionIndex: 0

    /// Available languages. Each entry: { label, code, regions: [{label, code}] }
    property var languages: [
        { label: "English", code: "en_US", regions: [
            { label: "United States", code: "en_US" },
            { label: "United Kingdom", code: "en_GB" },
            { label: "Australia", code: "en_AU" },
            { label: "Canada", code: "en_CA" }
        ]},
        { label: "Deutsch", code: "de_DE", regions: [
            { label: "Deutschland", code: "de_DE" },
            { label: "Österreich", code: "de_AT" },
            { label: "Schweiz", code: "de_CH" }
        ]},
        { label: "Français", code: "fr_FR", regions: [
            { label: "France", code: "fr_FR" },
            { label: "Canada", code: "fr_CA" },
            { label: "Belgique", code: "fr_BE" }
        ]},
        { label: "Español", code: "es_ES", regions: [
            { label: "España", code: "es_ES" },
            { label: "México", code: "es_MX" },
            { label: "Argentina", code: "es_AR" }
        ]},
        { label: "Português", code: "pt_PT", regions: [
            { label: "Portugal", code: "pt_PT" },
            { label: "Brasil", code: "pt_BR" }
        ]},
        { label: "Italiano", code: "it_IT", regions: [
            { label: "Italia", code: "it_IT" },
            { label: "Svizzera", code: "it_CH" }
        ]},
        { label: "Nederlands", code: "nl_NL", regions: [
            { label: "Nederland", code: "nl_NL" },
            { label: "België", code: "nl_BE" }
        ]},
        { label: "Polski", code: "pl_PL" },
        { label: "Русский", code: "ru_RU" },
        { label: "Українська", code: "uk_UA" },
        { label: "Türkçe", code: "tr_TR" },
        { label: "العربية", code: "ar_SA" },
        { label: "עברית", code: "he_IL" },
        { label: "हिन्दी", code: "hi_IN" },
        { label: "日本語", code: "ja_JP" },
        { label: "한국어", code: "ko_KR" },
        { label: "中文（简体）", code: "zh_CN" },
        { label: "中文（繁體）", code: "zh_TW", regions: [
            { label: "臺灣", code: "zh_TW" },
            { label: "香港", code: "zh_HK" }
        ]},
        { label: "Čeština", code: "cs_CZ" },
        { label: "Slovenčina", code: "sk_SK" },
        { label: "Magyar", code: "hu_HU" },
        { label: "Română", code: "ro_RO" },
        { label: "Български", code: "bg_BG" },
        { label: "Ελληνικά", code: "el_GR" },
        { label: "Svenska", code: "sv_SE" },
        { label: "Norsk", code: "nb_NO" },
        { label: "Dansk", code: "da_DK" },
        { label: "Suomi", code: "fi_FI" },
        { label: "Íslenska", code: "is_IS" },
        { label: "Bahasa Indonesia", code: "id_ID" },
        { label: "Tiếng Việt", code: "vi_VN" },
        { label: "ไทย", code: "th_TH" },
        { label: "Farsi", code: "fa_IR" }
    ]

    /// True when the search yields no matches (drives the empty overlay and
    /// removes the list from the focus chain so Tab cannot land behind it).
    readonly property bool emptySearchVisible: root.searchText.trim().length > 0 &&
                                               root.filteredLanguages.length === 0

    /// Languages matching the current search query (label / code / region).
    readonly property var filteredLanguages: {
        var q = root.searchText.trim().toLowerCase()
        if (q.length === 0)
            return root.languages
        return root.languages.filter(function(lang) {
            if (lang.label.toLowerCase().indexOf(q) >= 0)
                return true
            if (lang.code.toLowerCase().indexOf(q) >= 0)
                return true
            if (lang.regions) {
                for (var i = 0; i < lang.regions.length; ++i) {
                    if (lang.regions[i].label.toLowerCase().indexOf(q) >= 0)
                        return true
                    if (lang.regions[i].code.toLowerCase().indexOf(q) >= 0)
                        return true
                }
            }
            return false
        })
    }

    // ── Signals (host wiring) ──────────────────────────────────────
    /// User requested to continue to the next step
    signal continueRequested()
    /// User requested to go back to the previous step
    signal backRequested()
    /// User selected a language/region (effective locale code)
    signal languageChangeRequested(string code)
    /// User requested to retry after an error
    signal retryRequested()

    // ── Escape navigates back (Master UX: Back always available) ──
    Keys.onEscapePressed: root.backRequested()

    // ── Responsive helpers ─────────────────────────────────────────
    readonly property bool wideLayout: root.width >= 760
    readonly property bool compactLayout: root.width < 640

    // ── Language selection helpers ─────────────────────────────────
    function selectLanguage(index) {
        if (index < 0 || index >= root.filteredLanguages.length)
            return
        var lang = root.filteredLanguages[index]
        root.selectedLanguage = lang
        root.currentLanguage = lang.label
        root.selectedRegionIndex = 0
        if (lang.regions && lang.regions.length > 0) {
            root.currentRegion = lang.regions[0].label
            root.currentLocale = lang.regions[0].code
        } else {
            root.currentRegion = ""
            root.currentLocale = lang.code
        }
        root.languageChangeRequested(root.currentLocale)
    }

    function selectRegion(regionIndex) {
        var lang = root.selectedLanguage
        if (!lang || !lang.regions || regionIndex < 0 || regionIndex >= lang.regions.length)
            return
        root.selectedRegionIndex = regionIndex
        root.currentRegion = lang.regions[regionIndex].label
        root.currentLocale = lang.regions[regionIndex].code
        root.languageChangeRequested(root.currentLocale)
    }

    // ── Test hooks (used by tests/tst_language.qml) ────────────────
    property alias backgroundColor: backgroundRect.color
    property alias headingColor: headingLabel.color
    property alias headingLabel: headingLabel
    property alias searchField: searchField
    property alias languageList: languageList
    property alias helpPanel: helpPanel
    property alias regionRows: regionRows
    property alias regionSection: regionSection
    property alias selectionCaption: selectionCaption
    property alias emptyState: emptyState
    property alias clearSearchButton: clearSearchButton
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
                text: qsTr("Step %1 of %2 · Language").arg(root.step).arg(root.totalSteps)
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

            // ── Main content column ──
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Spacing.gapMedium

                // ── State area (per installer wireframe states) ──
                // Loading (non-blocking progress)
                RowLayout {
                    id: loadingIndicator
                    visible: root.screenState === "loading"
                    Layout.fillWidth: true
                    spacing: Spacing.gapMedium
                    Label {
                        text: qsTr("Loading languages…")
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
                    Layout.fillWidth: true
                    // The inner RowLayout uses anchors (not layout sizing),
                    // so give the banner an explicit height from its content
                    // — otherwise the Rectangle has implicit height 0 and the
                    // state banner is invisible even when `visible` is true
                    // (same latent bug as MOS-INS-003 KeyboardSelection;
                    // fixed here with the proven pattern).
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
                                text: qsTr("Languages could not be loaded")
                                font.weight: Typography.weightSemibold
                                color: Colors.contentOnErrorContainer
                            }
                            Label {
                                text: qsTr("The language catalog could not be verified. Check the installation media and try again.")
                                font.pixelSize: Typography.bodySmall.size
                                color: Colors.contentOnErrorContainer
                                wrapMode: Text.Wrap
                                Layout.fillWidth: true
                            }
                        }
                        MissionButton {
                            id: retryButton
                            objectName: "languageRetry"
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
                    Layout.fillWidth: true
                    // Explicit height from content (see errorBanner note).
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
                                text: qsTr("Language selection saved")
                                font.weight: Typography.weightSemibold
                                color: Colors.contentOnSuccessContainer
                            }
                            Label {
                                text: qsTr("Your language and region will be used throughout the installation.")
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
                    Layout.fillWidth: true
                    // Explicit height from content (see errorBanner note).
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
                                text: qsTr("Mission OS installs fully without an internet connection. The full language catalog is included on the installation media.")
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
                    text: qsTr("Select your language")
                    Layout.fillWidth: true
                    font.pixelSize: Typography.headline.size
                    font.weight: Typography.headline.weight
                    color: MissionTheme.textPrimary
                    wrapMode: Text.Wrap
                    Accessible.role: Accessible.Heading
                    Accessible.name: text
                }

                Label {
                    text: qsTr("Choose the language used by the installer and the installed system. You can change it at any time.")
                    Layout.fillWidth: true
                    font.pixelSize: Typography.bodyLarge.size
                    color: MissionTheme.textSecondary
                    wrapMode: Text.Wrap
                    lineHeight: Typography.lineHeightRelaxed
                }

                // ── Search / filter ──
                TextField {
                    id: searchField
                    objectName: "languageSearch"
                    Layout.fillWidth: true
                    Layout.preferredHeight: Spacing.minimumTouchTarget
                    text: root.searchText
                    onTextChanged: {
                        if (text !== root.searchText)
                            root.searchText = text
                    }
                    placeholderText: qsTr("Search languages")
                    font.pixelSize: Typography.body.size
                    color: MissionTheme.textPrimary
                    placeholderTextColor: MissionTheme.textTertiary
                    selectByMouse: true
                    leftPadding: Spacing.paddingMedium
                    rightPadding: Spacing.paddingMedium
                    Keys.onEscapePressed: {
                        root.searchText = ""
                        searchField.focus = true
                    }
                    background: Rectangle {
                        radius: Radii.input
                        color: MissionTheme.surface
                        border.width: searchField.activeFocus ? 2 : 1
                        border.color: searchField.activeFocus ? MissionTheme.focusRing : MissionTheme.outline
                    }
                    Accessible.role: Accessible.EditableText
                    Accessible.name: qsTr("Search languages")
                    Accessible.description: qsTr("Type to filter the language list")
                }

                // ── Language list (with empty-search overlay) ──
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 176

                    ListView {
                        id: languageList
                        objectName: "languageList"
                        anchors.fill: parent
                        clip: true
                        model: root.filteredLanguages
                        spacing: Spacing.gapTiny
                        // When the empty-search overlay is shown the list has
                        // nothing to offer, so it drops out of the Tab chain.
                        activeFocusOnTab: !root.emptySearchVisible
                        keyNavigationWraps: true
                        highlightFollowsCurrentItem: true
                        ScrollIndicator.vertical: ScrollIndicator {}
                        onCountChanged: {
                            if (languageList.count > 0 && languageList.currentIndex < 0)
                                languageList.currentIndex = 0
                        }
                        Keys.onReturnPressed: root.selectLanguage(languageList.currentIndex)
                        Keys.onSpacePressed: root.selectLanguage(languageList.currentIndex)
                        Accessible.role: Accessible.List
                        Accessible.name: qsTr("Languages")

                        delegate: Rectangle {
                            id: languageDelegate
                            required property var modelData
                            required property int index

                            // When the list is reached via Tab, focus lands on
                            // the currentItem delegate — not on the ListView
                            // itself — so the delegate carries the objectName
                            // used by the keyboard-focus test.
                            objectName: "languageItem" + index
                            width: languageList.width
                            height: Spacing.minimumTouchTarget
                            radius: Radii.input
                            color: {
                                if (root.selectedLanguage === modelData)
                                    return MissionTheme.darkMode ? MissionTheme.primary
                                                                 : MissionTheme.primaryContainer
                                if (languageList.currentIndex === index && languageList.activeFocus)
                                    return MissionTheme.surfaceVariant
                                if (languageDelegateMouse.containsMouse)
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
                                visible: languageList.currentIndex === index &&
                                         languageList.activeFocus
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
                                    font.weight: root.selectedLanguage === modelData
                                                 ? Typography.weightSemibold : Typography.weightRegular
                                    color: root.selectedLanguage === modelData
                                         ? (MissionTheme.darkMode ? MissionTheme.contentOnPrimary
                                                                 : MissionTheme.contentOnPrimaryContainer)
                                         : MissionTheme.textPrimary
                                }

                                Label {
                                    text: modelData.code
                                    font.pixelSize: Typography.caption.size
                                    color: root.selectedLanguage === modelData
                                         ? (MissionTheme.darkMode ? MissionTheme.contentOnPrimary
                                                                 : MissionTheme.contentOnPrimaryContainer)
                                         : MissionTheme.textTertiary
                                }
                            }

                            MouseArea {
                                id: languageDelegateMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    languageList.currentIndex = index
                                    root.selectLanguage(index)
                                }
                            }

                            Accessible.role: Accessible.ListItem
                            Accessible.name: modelData.label + ", " + modelData.code
                            Accessible.selected: root.selectedLanguage === modelData
                        }
                    }

                    // Empty search state (Master UX: explanation + primary action)
                    Rectangle {
                        id: emptyState
                        anchors.fill: parent
                        visible: root.emptySearchVisible
                        radius: Radii.card
                        color: MissionTheme.surfaceVariant

                        Column {
                            anchors.centerIn: parent
                            width: parent.width - Spacing.paddingLarge * 2
                            spacing: Spacing.gapMedium

                            Label {
                                text: qsTr("No languages match your search")
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                font.pixelSize: Typography.subtitle.size
                                font.weight: Typography.subtitle.weight
                                color: MissionTheme.textPrimary
                                wrapMode: Text.Wrap
                            }

                            Label {
                                text: qsTr("Try a different language name or code, for example “en” or “日本語”.")
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                font.pixelSize: Typography.bodySmall.size
                                color: MissionTheme.textSecondary
                                wrapMode: Text.Wrap
                            }

                            MissionButton {
                                id: clearSearchButton
                                objectName: "languageClearSearch"
                                anchors.horizontalCenter: parent.horizontalCenter
                                variant: MissionButton.Variant.Secondary
                                text: qsTr("Clear search")
                                onClicked: {
                                    root.searchText = ""
                                    searchField.focus = true
                                }
                            }
                        }
                    }
                }

                // ── Region / variant picker (reference Screen 08 "Region") ──
                ColumnLayout {
                    id: regionSection
                    // Strict boolean: when the selected language has no
                    // `regions` property the expression must still yield a
                    // bool (an `undefined` would leave `visible` stuck at its
                    // previous value with a QWARN on this toolchain).
                    visible: root.selectedLanguage !== null &&
                             root.selectedLanguage.regions !== undefined &&
                             root.selectedLanguage.regions.length > 1
                    Layout.fillWidth: true
                    spacing: Spacing.gapSmall

                    Label {
                        text: qsTr("Region")
                        font.pixelSize: Typography.subtitle.size
                        font.weight: Typography.subtitle.weight
                        color: MissionTheme.textPrimary
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: Spacing.gapSmall

                        Repeater {
                            id: regionRows
                            model: root.selectedLanguage && root.selectedLanguage.regions !== undefined
                                   ? root.selectedLanguage.regions : []

                            delegate: Rectangle {
                                id: regionDelegate
                                required property var modelData
                                required property int index

                                objectName: "regionItem" + index
                                height: Spacing.minimumTouchTarget
                                width: regionLabel.implicitWidth + Spacing.paddingMedium * 2
                                radius: Radii.chip
                                color: index === root.selectedRegionIndex
                                     ? (MissionTheme.darkMode ? MissionTheme.primary
                                                             : MissionTheme.primaryContainer)
                                     : (regionMouse.containsMouse ? MissionTheme.surfaceVariant
                                                                 : MissionTheme.surface)
                                border.width: index === root.selectedRegionIndex ? 0 : 1
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
                                    visible: regionDelegate.activeFocus
                                }

                                Label {
                                    id: regionLabel
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    font.pixelSize: Typography.bodySmall.size
                                    font.weight: index === root.selectedRegionIndex
                                                 ? Typography.weightSemibold : Typography.weightRegular
                                    color: index === root.selectedRegionIndex
                                         ? (MissionTheme.darkMode ? MissionTheme.contentOnPrimary
                                                                 : MissionTheme.contentOnPrimaryContainer)
                                         : MissionTheme.textPrimary
                                }

                                MouseArea {
                                    id: regionMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: root.selectRegion(index)
                                }

                                Keys.onReturnPressed: root.selectRegion(index)
                                Keys.onSpacePressed: root.selectRegion(index)

                                Accessible.role: Accessible.RadioButton
                                Accessible.name: modelData.label
                                Accessible.checked: index === root.selectedRegionIndex
                            }
                        }
                    }
                }

                // ── Live selection feedback ──
                Label {
                    id: selectionCaption
                    Layout.fillWidth: true
                    visible: root.currentLocale.length > 0
                    text: root.currentRegion.length > 0
                        ? qsTr("Selected: %1 (%2) · %3").arg(root.currentLanguage)
                                                        .arg(root.currentRegion)
                                                        .arg(root.currentLocale)
                        : qsTr("Selected: %1 · %2").arg(root.currentLanguage).arg(root.currentLocale)
                    font.pixelSize: Typography.caption.size
                    color: MissionTheme.textTertiary
                    elide: Text.ElideRight
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
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
                        text: qsTr("Pick a language, then choose the region that matches your formatting preferences. The installer updates immediately so every later step appears in your language.")
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
                objectName: "languageBack"
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
                objectName: "languageContinue"
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
