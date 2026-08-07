// Mission OS — Search (MOS-DES-005)
//
// Fifth screen of the Mission OS desktop family.
// Implements the source-defined Search overlay structure
// (docs/design/03_SCREEN_REGISTRY.md MOS-DES-005 "Search",
// docs/wireframes/03_DESKTOP.md region + state "Search Overlay" /
// "Search Active", docs/design/07_DESKTOP_LAYOUT.md §8,
// docs/design/02_NAVIGATION_MODEL.md §6, docs/reference/02_DESKTOP.md
// §Universal Search, docs/design/04_USER_FLOWS.md #11 Search,
// docs/design/05_COMPONENT_LIBRARY.md §Search Components):
//
//   Hosting: an overlay the host shows above the Desktop (MOS-DES-001
//   routes here via searchRequested and highlights its Search button
//   while overlayState == "search"). Place inside MissionWindow (or
//   MissionPage) content and anchor to fill, e.g.
//   MissionWindow { Search { anchors.fill: parent } }.
//   The component sizes to its implicit 1280x720 like Desktop.qml.
//
//   Desktop Layout (07_DESKTOP_LAYOUT.md §8): "Search opens centered
//   on screen. Supports: applications, files, settings, commands,
//   documents." — so unlike the top-right panels (MOS-DES-003/004)
//   this panel is anchored to the center of the screen.
//
//   Navigation Model (§6): "Global Search provides access to:
//   Applications, Files, Settings, Documents, Commands, Recent Items,
//   Help, Calculator, Unit Conversion. Search opens instantly from
//   anywhere."
//
//   Universal Search (02_DESKTOP.md): "The desktop search system
//   indexes: installed applications, files, folders, settings,
//   commands, documentation, calculator expressions, unit conversions,
//   recent documents. Search results should be ranked by relevance and
//   user activity. Searching local content should never require an
//   Internet connection."
//
//   User Flow (#11): users may search for Apps, Files, Settings,
//   Commands, Documents, Help. "Results update live." — the host
//   supplies the `results` model; this screen renders whatever the
//   host provides (family contract — WorkspaceSwitcher/Notifications/
//   QuickSettings behave the same).
//
//   Component Library (§Search Components): Search provides live
//   suggestions, recent searches, categories, keyboard navigation,
//   filters. `recentSearches` (host-driven strings) renders as chips
//   while the query is empty; result entries carry an optional
//   `category` tag; keyboard navigation is Up/Down/Enter/Space on the
//   results; filters are host-side model operations (documented
//   interpretation — this screen renders the filtered model the host
//   provides, exactly like the notifications model).
//
// Interpretation notes (documented — no authoritative source specifies
// further detail):
//   - The panel is anchored centered per 07_DESKTOP_LAYOUT §8 and
//     floats over a token scrim (the same overlay treatment as
//     MOS-DES-002/003/004) so it never obscures the desktop.
//   - The host drives `results`; each entry is { id, title, subtitle?,
//     category? }. The screen never mutates the model — activation
//     emits resultActivated(id) and the host decides what to launch/
//     open. Ranking by relevance/activity (reference) is a host-side
//     property of the model order.
//   - `query` is the query text the user types into the field. "Results
//     update live" (04_USER_FLOWS #11) is the host reading `query`
//     (e.g. onQueryChanged) and supplying the matching `results` — the
//     same read-only property contract as LanguageSelection.searchText.
//   - `recentSearches` is a host-driven list of strings rendered as
//     chips while the query is empty; clicking one emits
//     recentSearchActivated(text) and the host re-runs the search
//     (documented interpretation of the Component Library's "recent
//     searches").
//   - "Searching local content should never require an Internet
//     connection" (02_DESKTOP.md Universal Search) is carried as a
//     caption in the empty state so the offline/privacy property stays
//     visible to the user.
//   - Escape is deliberately unmapped (same contract as MOS-LCK-001..004
//     and MOS-DES-001/002/003/004): the overlay must not dismiss itself
//     — the host owns overlay dismissal. (The installer family's
//     search-field Escape-clears-text behavior does not apply to the
//     desktop overlay family, which leaves Escape entirely to the host.)
//   - Empty results and an empty query degrade to neutral hints
//     (defensive).
//
// Design-system compliance:
//   - Tokens only (Colors, Typography, Spacing, Radii, Motion, MissionTheme)
//   - Light + dark themes via MissionTheme (driven by host)
//   - Keyboard navigation with visible focus states; 44px minimum
//     touch targets (Spacing.minimumTouchTarget)
//   - WCAG AA-oriented contrast, reduced-motion aware
//   - Responsive reflow per docs/design/14_RESPONSIVE_RULES.md
//     (the panel trims to the window width on narrow layouts)

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.mission.ui 1.0

FocusScope {
    id: root

    implicitWidth: 1280
    implicitHeight: 720

    // ── Public API ─────────────────────────────────────────────────
    /// Search results: [{ id, title, subtitle?, category? }] —
    /// host-driven. id is what resultActivated carries; title/subtitle
    /// are displayed; category renders as a tag chip when present.
    property var results: []

    /// Recent searches (host-driven strings; shown as chips while the
    /// query is empty — Component Library §Search Components)
    property var recentSearches: []

    /// Current query text (user-editable; the host reads it to supply
    /// live results — 04_USER_FLOWS #11)
    property string query: ""

    /// Reduced motion (accessibility)
    property bool reducedMotion: false

    // ── Signals (host wiring) ──────────────────────────────────────
    /// User activated a search result (the "Select App → Launch" step
    /// of User Flow #11; launching/opening is the host's job)
    signal resultActivated(string resultId)
    /// User activated a recent-search chip (the host re-runs the search)
    signal recentSearchActivated(string text)

    // Escape is deliberately unmapped (see interpretation notes): the
    // overlay must not dismiss itself. No Keys.onEscapePressed here.

    // ── Derived helpers ────────────────────────────────────────────
    /// Whether the user has typed a (non-whitespace) query
    readonly property bool hasQuery: root.query.trim().length > 0

    /// Number of results in the host model
    readonly property int resultCount: root.results.length

    /// Number of recent-search chips in the host model
    readonly property int recentCount: root.recentSearches.length

    /// Display label for a result entry's category (falls back to empty;
    /// the tag chip is hidden when there is no category)
    function categoryLabel(entry) {
        if (entry === null || entry === undefined)
            return ""
        var c = entry.category !== undefined ? String(entry.category) : ""
        return c
    }

    /// Move keyboard focus to a result row (clamped, wraps)
    function focusResult(index) {
        if (root.results.length === 0)
            return
        var count = root.results.length
        var target = ((index % count) + count) % count
        var item = resultRows.itemAt(target)
        if (item !== null)
            item.forceActiveFocus()
    }

    // ── Test hooks (used by tests/tst_search.qml) ──────────────────
    property alias backdropScrim: backdropScrim
    property alias searchPanel: searchPanel
    property alias titleLabel: titleLabel
    property alias searchField: searchField
    property alias recentChips: recentChips
    property alias resultRows: resultRows
    property alias noQueryHint: noQueryHint
    property alias noResultsHint: noResultsHint
    property alias noResultsLabel: noResultsLabel
    property alias clearButton: clearButton

    // ── Overlay backdrop (scrim over the desktop) ──────────────────
    // Fades in on presentation (reduced-motion aware): the scrim starts
    // transparent and Component.onCompleted animates it to full so the
    // panel never pops abruptly over the desktop.
    Rectangle {
        id: backdropScrim
        objectName: "searchScrim"
        anchors.fill: parent
        color: Colors.scrim
        opacity: 0.0
        Behavior on opacity {
            enabled: !root.reducedMotion
            animation: NumberAnimation { duration: Motion.fadeIn }
        }
    }

    // ══════════════════════════════════════════════════════════════
    // Search panel (07_DESKTOP_LAYOUT.md §8 — opens centered on screen)
    // ══════════════════════════════════════════════════════════════
    Rectangle {
        id: searchPanel
        objectName: "searchPanel"
        anchors.centerIn: parent
        // Panel trims to the window on narrow layouts
        width: Math.min(560, root.width - Spacing.paddingLarge * 2)
        // Content-driven height clamped to the window
        height: Math.min(panelColumn.height + Spacing.paddingLarge * 2,
                         root.height - Spacing.paddingLarge * 2)
        radius: Radii.dialog
        color: MissionTheme.surface
        border.color: MissionTheme.outline
        border.width: 1

        Column {
            id: panelColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
            }
            anchors.margins: Spacing.paddingLarge
            spacing: Spacing.gapMedium

            // ── Header: title ──
            Label {
                id: titleLabel
                objectName: "searchTitle"
                text: qsTr("Search")
                font.pixelSize: Typography.title.size
                font.weight: Typography.title.weight
                color: MissionTheme.textPrimary
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }

            // ── Query field (live query — host reads `query`) ──
            TextField {
                id: searchField
                objectName: "searchField"
                width: parent.width
                text: root.query
                onTextChanged: {
                    if (text !== root.query)
                        root.query = text
                }
                placeholderText: qsTr("Search apps, files, settings, commands")
                font.pixelSize: Typography.body.size
                color: MissionTheme.textPrimary
                placeholderTextColor: MissionTheme.textTertiary
                selectByMouse: true
                leftPadding: Spacing.paddingMedium
                rightPadding: Spacing.paddingMedium
                // Escape is deliberately unmapped for the overlay family
                // (see interpretation notes) — the host owns dismissal.
                background: Rectangle {
                    radius: Radii.input
                    color: MissionTheme.surface
                    border.width: searchField.activeFocus ? 2 : 1
                    border.color: searchField.activeFocus ? MissionTheme.focusRing
                                                          : MissionTheme.outline
                }
                Accessible.role: Accessible.EditableText
                Accessible.name: qsTr("Search")
                Accessible.description: qsTr("Type to search apps, files, settings, commands and documents")
            }

            // ── Recent searches (chips; visible while the query is
            //    empty — Component Library §Search Components) ──
            Column {
                id: recentSection
                width: parent.width
                visible: !root.hasQuery && root.recentCount > 0
                spacing: Spacing.gapSmall

                Label {
                    text: qsTr("Recent searches")
                    font.pixelSize: Typography.caption.size
                    color: MissionTheme.textSecondary
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }

                Flow {
                    width: parent.width
                    spacing: Spacing.gapSmall

                    Repeater {
                        id: recentChips
                        model: root.recentSearches

                        delegate: Rectangle {
                            required property var modelData
                            required property int index

                            id: recentChip
                            objectName: "searchRecent" + index
                            height: Spacing.minimumTouchTarget
                            width: recentLabel.implicitWidth + Spacing.paddingMedium * 2
                            radius: Radii.chip
                            color: recentChipMouse.containsMouse
                                   ? MissionTheme.surfaceVariant : MissionTheme.surface
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
                                radius: Radii.chip + 2
                                color: "transparent"
                                border.color: MissionTheme.focusRing
                                border.width: 2
                                visible: recentChip.activeFocus
                            }

                            Label {
                                id: recentLabel
                                anchors.centerIn: parent
                                text: String(modelData)
                                font.pixelSize: Typography.bodySmall.size
                                color: MissionTheme.textPrimary
                            }

                            MouseArea {
                                id: recentChipMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    recentChip.forceActiveFocus()
                                    root.recentSearchActivated(String(modelData))
                                }
                            }

                            Keys.onReturnPressed:
                                root.recentSearchActivated(String(modelData))
                            Keys.onSpacePressed:
                                root.recentSearchActivated(String(modelData))

                            Accessible.role: Accessible.Button
                            Accessible.name: String(modelData)
                            Accessible.description: qsTr("Run the search %1 again").arg(String(modelData))
                        }
                    }
                }
            }

            // ── Results list (scrolls when the list overflows) ──
            Flickable {
                id: scrollArea
                visible: root.hasQuery
                width: parent.width
                height: Math.max(96, Math.min(360,
                                 root.height - Spacing.paddingLarge * 4 - 160))
                clip: true
                interactive: contentHeight > height
                contentHeight: listColumn.implicitHeight

                Column {
                    id: listColumn
                    width: parent.width
                    spacing: Spacing.gapSmall

                    Repeater {
                        id: resultRows
                        model: root.results

                        delegate: Rectangle {
                            required property var modelData
                            required property int index

                            id: resultRow
                            objectName: "searchResult" + index
                            width: parent.width
                            height: Math.max(Spacing.minimumTouchTarget,
                                             resultContent.implicitHeight +
                                             Spacing.paddingMedium * 2)
                            radius: Radii.card
                            color: resultRowMouse.containsMouse
                                   ? MissionTheme.surfaceVariant : MissionTheme.surfaceDim
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
                                visible: resultRow.activeFocus
                            }

                            // Row click = activate the result ("Select →
                            // Launch" step of User Flow #11)
                            MouseArea {
                                id: resultRowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    resultRow.forceActiveFocus()
                                    root.resultActivated(String(modelData.id))
                                }
                            }

                            RowLayout {
                                id: resultContent
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    top: parent.top
                                }
                                anchors.leftMargin: Spacing.paddingMedium
                                anchors.rightMargin: Spacing.paddingMedium
                                anchors.topMargin: Spacing.paddingMedium
                                spacing: Spacing.gapMedium

                                // Category tag chip (Component Library:
                                // categories; text carries the label so
                                // color is never the only indicator)
                                Rectangle {
                                    id: categoryTag
                                    visible: root.categoryLabel(modelData).length > 0
                                    Layout.preferredWidth: categoryLabel.implicitWidth +
                                                           Spacing.paddingSmall * 2
                                    Layout.preferredHeight: Spacing.gapMedium
                                    radius: Radii.chip
                                    color: MissionTheme.surfaceVariant

                                    Label {
                                        id: categoryLabel
                                        anchors.centerIn: parent
                                        text: root.categoryLabel(modelData)
                                        font.pixelSize: Typography.caption.size
                                        color: MissionTheme.textSecondary
                                    }
                                }

                                Column {
                                    Layout.fillWidth: true
                                    spacing: Spacing.gapTiny

                                    Label {
                                        width: parent.width
                                        text: modelData.title !== undefined
                                              ? String(modelData.title) : ""
                                        font.pixelSize: Typography.body.size
                                        font.weight: Typography.weightSemibold
                                        color: MissionTheme.textPrimary
                                        elide: Text.ElideRight
                                    }

                                    Label {
                                        width: parent.width
                                        visible: modelData.subtitle !== undefined &&
                                                 String(modelData.subtitle).length > 0
                                        text: modelData.subtitle !== undefined
                                              ? String(modelData.subtitle) : ""
                                        font.pixelSize: Typography.bodySmall.size
                                        color: MissionTheme.textSecondary
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            // Keyboard-first: Up/Down (and Left/Right)
                            // move between rows, Enter/Space activate
                            Keys.onUpPressed: root.focusResult(index - 1)
                            Keys.onDownPressed: root.focusResult(index + 1)
                            Keys.onLeftPressed: root.focusResult(index - 1)
                            Keys.onRightPressed: root.focusResult(index + 1)
                            Keys.onReturnPressed:
                                root.resultActivated(String(modelData.id))
                            Keys.onSpacePressed:
                                root.resultActivated(String(modelData.id))

                            Accessible.role: Accessible.Button
                            Accessible.name: {
                                // Defensive: never emit "undefined" when a
                                // host entry omits title (family contract)
                                var t = modelData.title !== undefined
                                        ? String(modelData.title) : ""
                                var c = root.categoryLabel(modelData)
                                if (c.length > 0)
                                    return qsTr("%1, %2").arg(t).arg(c)
                                return t
                            }
                        }
                    }
                }
            }

            // ── Empty states (defensive; Component Library: every
            //    empty state includes an explanation + primary action) ──
            // No query yet — invite typing; the privacy caption is the
            // Universal Search offline property (02_DESKTOP.md)
            Column {
                id: noQueryHint
                objectName: "searchNoQuery"
                visible: !root.hasQuery && root.recentCount === 0
                width: parent.width
                spacing: Spacing.gapSmall

                Label {
                    width: parent.width
                    text: qsTr("Start typing to search apps, files, settings, commands and documents")
                    font.pixelSize: Typography.bodySmall.size
                    color: MissionTheme.textSecondary
                    wrapMode: Text.WordWrap
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }

                Label {
                    width: parent.width
                    text: qsTr("Searching local content never requires an Internet connection")
                    font.pixelSize: Typography.caption.size
                    color: MissionTheme.textTertiary
                    wrapMode: Text.WordWrap
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }
            }

            // Query with no matching results — explanation + Clear
            // (primary action, same pattern as the installer empty state)
            Column {
                id: noResultsHint
                objectName: "searchNoResults"
                visible: root.hasQuery && root.resultCount === 0
                width: parent.width
                spacing: Spacing.gapMedium

                Label {
                    id: noResultsLabel
                    width: parent.width
                    text: qsTr("No results for “%1”").arg(root.query.trim())
                    font.pixelSize: Typography.body.size
                    font.weight: Typography.weightSemibold
                    color: MissionTheme.textPrimary
                    wrapMode: Text.WordWrap
                    elide: Text.ElideRight
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }

                Label {
                    width: parent.width
                    text: qsTr("Try a different search term, or check the settings that control what is indexed.")
                    font.pixelSize: Typography.bodySmall.size
                    color: MissionTheme.textSecondary
                    wrapMode: Text.WordWrap
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }

                MissionButton {
                    id: clearButton
                    objectName: "searchClear"
                    variant: MissionButton.Variant.Secondary
                    text: qsTr("Clear search")
                    onClicked: {
                        root.query = ""
                        searchField.focus = true
                    }
                    Accessible.description: qsTr("Clear the search query")
                }
            }
        }
    }

    // ── Initial focus (keyboard-first) ─────────────────────────────
    // The root claims focus so keyboard users land in the overlay
    // immediately, and the query field is focused so typing works right
    // away ("Search opens instantly from anywhere" — 02_NAVIGATION_MODEL
    // §6; desktop §Keyboard Navigation).
    focus: true

    Component.onCompleted: {
        backdropScrim.opacity = 1.0
        searchField.forceActiveFocus()
    }
}
