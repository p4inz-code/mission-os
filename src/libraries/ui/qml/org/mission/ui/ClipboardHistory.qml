// Mission OS — Clipboard History (MOS-DES-007)
//
// Seventh screen of the Mission OS desktop family.
// Implements the source-defined Clipboard Manager structure
// (docs/design/03_SCREEN_REGISTRY.md MOS-DES-007 "Clipboard History" +
// §19 Global Overlays "Clipboard Manager",
// docs/reference/02_DESKTOP.md §Clipboard Manager,
// docs/reference/05_PRIVACY_CENTER.md §Clipboard Privacy):
//
//   Hosting: an overlay the host shows above the Desktop (registry §19
//   lists Clipboard Manager among the Global Overlays; the access point
//   is host-side, like the other family overlays). Place inside
//   MissionWindow (or MissionPage) content and anchor to fill, e.g.
//   MissionWindow { ClipboardHistory { anchors.fill: parent } }.
//   The component sizes to its implicit 1280x720 like Desktop.qml.
//
//   Clipboard Manager (02_DESKTOP.md): "Mission OS maintains clipboard
//   history. Features: searchable history, pin important entries, clear
//   history, auto-expire sensitive content, image support, text support.
//   Clipboard history may be disabled. Passwords copied from supported
//   applications should never be permanently stored."
//
//   Clipboard Privacy (05_PRIVACY_CENTER.md): options include disabling
//   history; users can clear clipboard history.
//
// Interpretation notes (documented — no authoritative source specifies
// further detail):
//   - The panel is anchored top-right (the established overlay
//     treatment shared with Notifications / Quick Settings / Calendar).
//   - The host drives the `entries` model; each entry is
//     { id, text?, image?, pinned?, sensitive?, time? }. The screen
//     never mutates the model (family contract — WorkspaceSwitcher /
//     Notifications / QuickSettings behave the same): activating an
//     entry emits entryActivated(id) and the host pastes it; toggling
//     the pin button emits pinToggled(id) and the host flips the model
//     entry; "Clear all" emits clearAllRequested.
//   - Searchable history (reference): the search field filters the
//     host model locally (label/text match, case-insensitive), the same
//     pattern as LanguageSelection's searchable catalog. The query is
//     the screen's own `searchText`; the host may read it.
//   - Image support (reference): entries carry an `image` payload in
//     the host model. No image preview assets ship in this library, so
//     an image entry renders a neutral "Image" type tag instead of a
//     preview (same substitution the family uses for avatars/icons) —
//     documented interpretation.
//   - Auto-expire sensitive content / "passwords should never be
//     permanently stored" (reference): auto-expiry is a host-side
//     retention behavior; the screen surfaces the host's `sensitive`
//     flag with a "Sensitive" tag + "(sensitive)" Accessible tag (color
//     is never the only indicator) and carries the password/privacy
//     note as a caption in the empty and disabled states.
//   - Pinned entries (reference "pin important entries"): the host's
//     `pinned` flag renders a "Pinned" tag + "(pinned)" Accessible tag
//     and the pin button reflects the state; ordering is the host's
//     (the model order is rendered as-is, like the notifications model).
//   - "Clipboard history may be disabled" (reference): when the host
//     sets `historyEnabled` false the panel shows a neutral hint and
//     hides the list (the same pattern as Notifications' Focus Mode
//     hint) — the host owns the privacy setting.
//   - Escape is deliberately unmapped (same contract as MOS-LCK-001..004
//     and MOS-DES-001/002/003/004/005/006): the panel must not dismiss
//     itself — the host owns overlay dismissal.
//   - Empty history and empty search degrade to neutral hints
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
    /// Clipboard history entries: [{ id, text?, image?, pinned?,
    /// sensitive?, time? }] — host-driven. id is what the signals
    /// carry; text/image/time are displayed; pinned/sensitive render
    /// as state tags (never mutated here — the host owns the model).
    property var entries: []

    /// Search query used to filter the history (searchable history —
    /// reference; filters label/text locally, case-insensitive)
    property string searchText: ""

    /// Whether clipboard history is enabled (reference: "Clipboard
    /// history may be disabled" — host-driven privacy setting). When
    /// false the list is hidden behind a hint.
    property bool historyEnabled: true

    /// Reduced motion (accessibility)
    property bool reducedMotion: false

    // ── Signals (host wiring) ──────────────────────────────────────
    /// User activated an entry (the host pastes/copies it back)
    signal entryActivated(string entryId)
    /// User toggled the pin on an entry (the host flips the model)
    signal pinToggled(string entryId)
    /// User chose "Clear all" (the host clears the history)
    signal clearAllRequested()

    // Escape is deliberately unmapped (see interpretation notes): the
    // panel must not dismiss itself. No Keys.onEscapePressed here.

    // ── Derived helpers ────────────────────────────────────────────
    /// Entries matching the current search query (text match,
    /// case-insensitive; empty query shows the whole history)
    readonly property var filteredEntries: {
        var q = root.searchText.trim().toLowerCase()
        if (q.length === 0)
            return root.entries
        return root.entries.filter(function(entry) {
            if (entry.text !== undefined &&
                String(entry.text).toLowerCase().indexOf(q) >= 0)
                return true
            return false
        })
    }

    /// True when the search yields no matches (drives the empty-search
    /// overlay)
    readonly property bool emptySearchVisible: root.searchText.trim().length > 0 &&
                                               root.filteredEntries.length === 0

    /// Number of entries in the host model — header Clear-all state
    readonly property int entryCount: root.entries.length

    /// Type tag for an entry: "Image" when the entry carries an image
    /// payload, "Text" otherwise (image/text support — reference)
    function typeLabel(entry) {
        if (entry !== null && entry !== undefined &&
            entry.image !== undefined && String(entry.image).length > 0)
            return qsTr("Image")
        return qsTr("Text")
    }

    /// Whether an entry is pinned (host state; false when absent)
    function isPinned(entry) {
        return entry !== null && entry !== undefined && entry.pinned === true
    }

    /// Whether an entry is flagged sensitive (host state; false when
    /// absent — auto-expiry is host-side retention)
    function isSensitive(entry) {
        return entry !== null && entry !== undefined && entry.sensitive === true
    }

    /// Accessible preview of an entry's content: the text (elided to a
    /// readable length) when present, else the type tag (the neutral
    /// surface for image entries, which ship no preview assets)
    function previewFor(entry) {
        if (entry !== null && entry !== undefined &&
            entry.text !== undefined && String(entry.text).length > 0) {
            var t = String(entry.text)
            return t.length > 80 ? t.substring(0, 80) + "\u2026" : t
        }
        return root.typeLabel(entry)
    }

    /// Move keyboard focus to an entry row (clamped, wraps)
    function focusEntry(index) {
        if (root.filteredEntries.length === 0)
            return
        var count = root.filteredEntries.length
        var target = ((index % count) + count) % count
        var item = entryRows.itemAt(target)
        if (item !== null)
            item.forceActiveFocus()
    }

    // ── Test hooks (used by tests/tst_clipboard_history.qml) ───────
    property alias backdropScrim: backdropScrim
    property alias historyPanel: historyPanel
    property alias titleLabel: titleLabel
    property alias clearAllButton: clearAllButton
    property alias searchField: searchField
    property alias entryRows: entryRows
    property alias disabledHint: disabledHint
    property alias emptyHint: emptyHint
    property alias noMatchesHint: noMatchesHint
    property alias clearSearchButton: clearSearchButton
    property alias privacyCaption: privacyCaption

    // ── Overlay backdrop (scrim over the desktop) ──────────────────
    // Fades in on presentation (reduced-motion aware): the scrim starts
    // transparent and Component.onCompleted animates it to full so the
    // panel never pops abruptly over the desktop.
    Rectangle {
        id: backdropScrim
        objectName: "clipboardScrim"
        anchors.fill: parent
        color: Colors.scrim
        opacity: 0.0
        Behavior on opacity {
            enabled: !root.reducedMotion
            animation: NumberAnimation { duration: Motion.fadeIn }
        }
    }

    // ══════════════════════════════════════════════════════════════
    // Clipboard History panel (registry §19 Global Overlay — the
    // top-right overlay treatment shared with Notifications)
    // ══════════════════════════════════════════════════════════════
    Rectangle {
        id: historyPanel
        objectName: "clipboardPanel"
        anchors {
            top: parent.top
            right: parent.right
            margins: Spacing.paddingLarge
        }
        // Panel trims to the window on narrow layouts
        width: Math.min(400, root.width - Spacing.paddingLarge * 2)
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

            // ── Header: title + Clear all ──
            RowLayout {
                width: parent.width
                spacing: Spacing.gapSmall

                Label {
                    id: titleLabel
                    objectName: "clipboardTitle"
                    Layout.fillWidth: true
                    text: qsTr("Clipboard History")
                    font.pixelSize: Typography.title.size
                    font.weight: Typography.title.weight
                    color: MissionTheme.textPrimary
                    elide: Text.ElideRight
                    Accessible.role: Accessible.Heading
                    Accessible.name: text
                }

                MissionButton {
                    id: clearAllButton
                    objectName: "clipboardClearAll"
                    variant: MissionButton.Variant.Tertiary
                    compact: true
                    text: qsTr("Clear all")
                    enabled: root.entryCount > 0
                    onClicked: root.clearAllRequested()
                    Accessible.description: qsTr("Clear the clipboard history")
                }
            }

            // ── Search field (searchable history — reference) ──
            TextField {
                id: searchField
                objectName: "clipboardSearch"
                width: parent.width
                visible: root.historyEnabled && root.entryCount > 0
                text: root.searchText
                onTextChanged: {
                    if (text !== root.searchText)
                        root.searchText = text
                }
                placeholderText: qsTr("Search clipboard history")
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
                Accessible.name: qsTr("Search clipboard history")
                Accessible.description: qsTr("Type to filter the clipboard history")
            }

            // ── History disabled hint (reference: may be disabled) ──
            Column {
                id: disabledHint
                objectName: "clipboardDisabled"
                visible: !root.historyEnabled
                width: parent.width
                spacing: Spacing.gapSmall

                Label {
                    width: parent.width
                    text: qsTr("Clipboard history is disabled")
                    font.pixelSize: Typography.body.size
                    font.weight: Typography.weightSemibold
                    color: MissionTheme.textPrimary
                    wrapMode: Text.WordWrap
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }

                Label {
                    width: parent.width
                    text: qsTr("Clipboard history may be re-enabled from the privacy settings.")
                    font.pixelSize: Typography.bodySmall.size
                    color: MissionTheme.textSecondary
                    wrapMode: Text.WordWrap
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }
            }

            // ── Entry list (scrolls when the list overflows) ──
            Flickable {
                id: scrollArea
                visible: root.historyEnabled && root.entryCount > 0
                width: parent.width
                height: Math.max(72, Math.min(400,
                                 root.height - Spacing.paddingLarge * 4 - 160))
                clip: true
                interactive: contentHeight > height
                contentHeight: listColumn.implicitHeight

                Column {
                    id: listColumn
                    width: parent.width
                    spacing: Spacing.gapSmall

                    Repeater {
                        id: entryRows
                        model: root.filteredEntries

                        delegate: Rectangle {
                            required property var modelData
                            required property int index

                            id: entryRow
                            objectName: "clipEntry" + index
                            width: parent.width
                            height: Math.max(Spacing.minimumTouchTarget,
                                             entryContent.implicitHeight +
                                             Spacing.paddingMedium * 2)
                            radius: Radii.card
                            color: entryRowMouse.containsMouse
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
                                visible: entryRow.activeFocus
                            }

                            // Row click = activate the entry (the host
                            // pastes it). Declared BEFORE the content so
                            // the interactive Pin button (declared later
                            // = on top) receives its own clicks.
                            MouseArea {
                                id: entryRowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    entryRow.forceActiveFocus()
                                    root.entryActivated(String(modelData.id))
                                }
                            }

                            Column {
                                id: entryContent
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    top: parent.top
                                }
                                anchors.leftMargin: Spacing.paddingMedium
                                anchors.rightMargin: Spacing.paddingMedium
                                anchors.topMargin: Spacing.paddingMedium
                                spacing: Spacing.gapTiny

                                // ── Meta line: type · state tags · time ·
                                //    pin action ──
                                RowLayout {
                                    width: parent.width
                                    spacing: Spacing.gapSmall

                                    // Type tag (Text / Image — reference
                                    // text + image support; no image
                                    // previews ship, so Image entries get
                                    // the tag as their neutral surface)
                                    Rectangle {
                                        id: typeTag
                                        Layout.preferredWidth: typeTagLabel.implicitWidth +
                                                               Spacing.paddingSmall * 2
                                        Layout.preferredHeight: Spacing.gapMedium
                                        radius: Radii.chip
                                        color: MissionTheme.surfaceVariant

                                        Label {
                                            id: typeTagLabel
                                            anchors.centerIn: parent
                                            text: root.typeLabel(modelData)
                                            font.pixelSize: Typography.caption.size
                                            color: MissionTheme.textSecondary
                                        }
                                    }

                                    // Sensitive tag (reference: auto-expire
                                    // sensitive content; text carries the
                                    // state so color is never the only
                                    // indicator)
                                    Rectangle {
                                        visible: root.isSensitive(modelData)
                                        Layout.preferredWidth: sensitiveTagLabel.implicitWidth +
                                                               Spacing.paddingSmall * 2
                                        Layout.preferredHeight: Spacing.gapMedium
                                        radius: Radii.chip
                                        color: Colors.errorContainer

                                        Label {
                                            id: sensitiveTagLabel
                                            anchors.centerIn: parent
                                            text: qsTr("Sensitive")
                                            font.pixelSize: Typography.caption.size
                                            color: Colors.contentOnErrorContainer
                                        }
                                    }

                                    // Pinned tag (reference: pin important
                                    // entries)
                                    Rectangle {
                                        visible: root.isPinned(modelData)
                                        Layout.preferredWidth: pinnedTagLabel.implicitWidth +
                                                               Spacing.paddingSmall * 2
                                        Layout.preferredHeight: Spacing.gapMedium
                                        radius: Radii.chip
                                        color: MissionTheme.primaryContainer

                                        Label {
                                            id: pinnedTagLabel
                                            anchors.centerIn: parent
                                            text: qsTr("Pinned")
                                            font.pixelSize: Typography.caption.size
                                            color: MissionTheme.contentOnPrimaryContainer
                                        }
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        text: modelData.time !== undefined
                                              ? String(modelData.time) : ""
                                        font.pixelSize: Typography.caption.size
                                        color: MissionTheme.textTertiary
                                        elide: Text.ElideRight
                                        horizontalAlignment: Text.AlignRight
                                    }

                                    // Pin action (the host flips the model;
                                    // the screen never mutates it)
                                    MissionButton {
                                        objectName: "clipPin" + index
                                        variant: MissionButton.Variant.Tertiary
                                        compact: true
                                        text: root.isPinned(modelData)
                                              ? qsTr("Pinned") : qsTr("Pin")
                                        onClicked: root.pinToggled(String(modelData.id))
                                        Accessible.name: root.isPinned(modelData)
                                                        ? qsTr("Pinned") : qsTr("Pin")
                                        Accessible.description: root.isPinned(modelData)
                                                                ? qsTr("Unpin this entry")
                                                                : qsTr("Pin this entry")
                                    }
                                }

                                // ── Content preview (text support; Image
                                //    entries get a neutral placeholder) ──
                                Label {
                                    width: parent.width
                                    visible: modelData.text !== undefined &&
                                             String(modelData.text).length > 0
                                    text: modelData.text !== undefined
                                          ? String(modelData.text) : ""
                                    font.pixelSize: Typography.bodySmall.size
                                    color: MissionTheme.textPrimary
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }

                                Label {
                                    width: parent.width
                                    // Image entries carry no preview in
                                    // this library (no image assets ship)
                                    visible: modelData.image !== undefined &&
                                             String(modelData.image).length > 0
                                    text: qsTr("Image content — preview not available")
                                    font.pixelSize: Typography.caption.size
                                    color: MissionTheme.textTertiary
                                    elide: Text.ElideRight
                                }
                            }

                            // Keyboard-first: Up/Down move between rows,
                            // Enter/Space activate (the Pin button gets
                            // focus via Tab)
                            Keys.onUpPressed: root.focusEntry(index - 1)
                            Keys.onDownPressed: root.focusEntry(index + 1)
                            Keys.onLeftPressed: root.focusEntry(index - 1)
                            Keys.onRightPressed: root.focusEntry(index + 1)
                            Keys.onReturnPressed:
                                root.entryActivated(String(modelData.id))
                            Keys.onSpacePressed:
                                root.entryActivated(String(modelData.id))

                            Accessible.role: Accessible.Button
                            Accessible.name: {
                                // Carry the copied content (elided) so a
                                // screen reader announces what the entry
                                // actually holds — not just its type.
                                var base = root.previewFor(modelData)
                                var hasText = modelData.text !== undefined &&
                                              String(modelData.text).length > 0
                                var name = hasText
                                           ? qsTr("%1, %2").arg(base)
                                                          .arg(root.typeLabel(modelData))
                                           : base
                                if (root.isPinned(modelData))
                                    name += qsTr(", pinned")
                                if (root.isSensitive(modelData))
                                    name += qsTr(", sensitive")
                                return name
                            }
                        }
                    }

                    // ── Empty search overlay (explanation + action) ──
                    Column {
                        id: noMatchesHint
                        objectName: "clipboardNoMatches"
                        visible: root.emptySearchVisible
                        width: parent.width
                        spacing: Spacing.gapMedium

                        Label {
                            width: parent.width
                            text: qsTr("No clipboard entries match “%1”")
                                .arg(root.searchText.trim())
                            font.pixelSize: Typography.body.size
                            font.weight: Typography.weightSemibold
                            color: MissionTheme.textPrimary
                            wrapMode: Text.WordWrap
                            Accessible.role: Accessible.StaticText
                            Accessible.name: text
                        }

                        MissionButton {
                            id: clearSearchButton
                            objectName: "clipboardClearSearch"
                            variant: MissionButton.Variant.Secondary
                            text: qsTr("Clear search")
                            onClicked: {
                                root.searchText = ""
                                searchField.focus = true
                            }
                            Accessible.description: qsTr("Clear the search query")
                        }
                    }
                }
            }

            // ── Empty state (defensive + privacy note) ──
            Column {
                id: emptyHint
                objectName: "clipboardEmpty"
                visible: root.historyEnabled && root.entryCount === 0
                width: parent.width
                spacing: Spacing.gapSmall

                Label {
                    width: parent.width
                    text: qsTr("Clipboard history is empty")
                    font.pixelSize: Typography.body.size
                    font.weight: Typography.weightSemibold
                    color: MissionTheme.textPrimary
                    wrapMode: Text.WordWrap
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }

                Label {
                    width: parent.width
                    text: qsTr("Copied text and images will appear here as you copy them.")
                    font.pixelSize: Typography.bodySmall.size
                    color: MissionTheme.textSecondary
                    wrapMode: Text.WordWrap
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }
            }

            // ── Privacy footer (reference: passwords are never
            //    permanently stored) — always visible on this screen ──
            Label {
                id: privacyCaption
                objectName: "clipboardPrivacy"
                width: parent.width
                text: qsTr("Passwords copied from supported applications are never permanently stored")
                font.pixelSize: Typography.caption.size
                color: MissionTheme.textTertiary
                wrapMode: Text.WordWrap
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }
        }
    }

    // ── Initial focus (keyboard-first) ─────────────────────────────
    // The root claims focus so keyboard users land in the overlay
    // immediately, and the search field is focused as soon as the panel
    // appears (searchable history — reference; desktop §Keyboard
    // Navigation).
    focus: true

    Component.onCompleted: {
        backdropScrim.opacity = 1.0
        searchField.forceActiveFocus()
    }
}
