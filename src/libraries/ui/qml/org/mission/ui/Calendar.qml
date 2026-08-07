// Mission OS — Calendar (MOS-DES-006)
//
// Sixth screen of the Mission OS desktop family.
// Implements the source-defined Calendar structure
// (docs/design/03_SCREEN_REGISTRY.md MOS-DES-006 "Calendar",
// docs/reference/02_DESKTOP.md §Taskbar + §Widget System,
// docs/design/05_COMPONENT_LIBRARY.md §Inputs "Date Picker"):
//
//   Hosting: an overlay the host shows above the Desktop (02_DESKTOP.md
//   lists Calendar among the taskbar functions, alongside the Clock —
//   the access point is host-side, like the other family overlays).
//   Place inside MissionWindow (or MissionPage) content and anchor to
//   fill, e.g.  MissionWindow { Calendar { anchors.fill: parent } }.
//   The component sizes to its implicit 1280x720 like Desktop.qml.
//
//   Taskbar (02_DESKTOP.md): "Functions include: Pinned applications,
//   Running applications, Window previews, Workspace indicator,
//   Notification badge, Clock, Calendar, Network, Audio, Battery,
//   Accessibility shortcut." — the Calendar screen is the surface the
//   taskbar Calendar function opens, the same way Quick Settings /
//   Notifications open their taskbar functions.
//
//   Widget System (02_DESKTOP.md): "Widgets provide glanceable
//   information. Supported widgets include: Clock, Calendar, ..." —
//   this screen is the glanceable month view: the current month grid,
//   today marked, and month navigation.
//
//   Component Library (§Inputs — Date Picker): the calendar-style
//   selection contract — the user picks a day and the screen emits the
//   choice. The screen therefore renders the month grid as a
//   selectable date surface: clicking / Enter / Space on a day emits
//   dateSelected(isoDate).
//
// Interpretation notes (documented — no authoritative source specifies
// further detail):
//   - The panel is anchored top-right (the same overlay treatment as
//     the Notifications / Quick Settings panels, which are also
//     taskbar-accessed) and floats over a token scrim so it never
//     obscures the desktop.
//   - The displayed month is `currentDate` (defaults to today) and is
//     host-pinnable exactly like the Desktop clock (clockTimeText /
//     clockRunning contract): the host may pin it and the screen keeps
//     it current while the user navigates. Previous / Next month
//     buttons move the anchor; no signal is needed for navigation —
//     it is pure view state on `currentDate`.
//   - `selectedDate` is the ISO date (yyyy-MM-dd) the user most
//     recently picked; the screen writes it and emits dateSelected
//     together. The host decides what a picked date does (e.g. open an
//     agenda); no events/appointments model is specified anywhere in
//     the repository, so none is invented.
//   - The week starts on Sunday (matching the installer default
//     English/United States locale); weekday header labels are
//     localized via Qt.formatDate. Leading/trailing days from the
//     adjacent months are shown dimmed (standard month-grid treatment)
//     so the grid always forms complete weeks.
//   - Today is marked with a primary dot + border and "(today)" in the
//     Accessible name; the selected day gets the primary fill +
//     "(selected)" tag — color is never the only indicator.
//   - Escape is deliberately unmapped (same contract as MOS-LCK-001..004
//     and MOS-DES-001/002/003/004/005): the overlay must not dismiss
//     itself — the host owns overlay dismissal.
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
    /// Month anchor whose calendar grid is displayed (host-pinnable,
    /// like the Desktop clock; defaults to today)
    property date currentDate: new Date()

    /// ISO date (yyyy-MM-dd) the user most recently picked — "" until
    /// the first selection (host-readable; written with dateSelected)
    property string selectedDate: ""

    /// Reduced motion (accessibility)
    property bool reducedMotion: false

    // ── Signals (host wiring) ──────────────────────────────────────
    /// User picked a day in the grid (the Date Picker contract — the
    /// host decides what the picked date does)
    signal dateSelected(string isoDate)

    // Escape is deliberately unmapped (see interpretation notes): the
    // overlay must not dismiss itself. No Keys.onEscapePressed here.

    // ── Derived helpers ────────────────────────────────────────────
    /// ISO date string for a year/month/day (zero-padded)
    function isoDate(year, month, day) {
        var mm = ("0" + (month + 1)).slice(-2)
        var dd = ("0" + day).slice(-2)
        return String(year) + "-" + mm + "-" + dd
    }

    /// Month title for the header, e.g. "August 2026" (localized)
    readonly property string monthTitle: Qt.formatDate(root.currentDate, "MMMM yyyy")

    /// Localized short weekday header labels, Sunday-first (matches
    /// the en_US installer default): built from known Sunday dates so
    /// the names follow the system locale without hardcoding
    readonly property var weekdayLabels: {
        var labels = []
        for (var i = 0; i < 7; ++i)
            labels.push(Qt.formatDate(new Date(2026, 0, 4 + i), "ddd"))
        return labels
    }

    /// 42-cell month grid (6 weeks × 7 days, Sunday-first). Each cell:
    /// { day, iso, label, inMonth, isToday }. Re-evaluates when the
    /// month anchor changes.
    readonly property var dayCells: {
        var year = root.currentDate.getFullYear()
        var month = root.currentDate.getMonth()
        var offset = new Date(year, month, 1).getDay() // 0 = Sunday
        var now = new Date()
        now.setHours(0, 0, 0, 0)
        var todayIso = root.isoDate(now.getFullYear(), now.getMonth(), now.getDate())
        var cells = []
        for (var i = 0; i < 42; ++i) {
            var cellDate = new Date(year, month, 1 - offset + i)
            var iso = root.isoDate(cellDate.getFullYear(),
                                   cellDate.getMonth(), cellDate.getDate())
            cells.push({
                day: cellDate.getDate(),
                iso: iso,
                label: Qt.formatDate(cellDate, "dddd, MMMM d, yyyy"),
                inMonth: cellDate.getMonth() === month,
                isToday: iso === todayIso
            })
        }
        return cells
    }

    /// Index of the today cell within dayCells (never -1 for the
    /// current month; defensive fallback to 15)
    readonly property int todayCellIndex: {
        for (var i = 0; i < root.dayCells.length; ++i) {
            if (root.dayCells[i].isToday)
                return i
        }
        return 15
    }

    /// Move keyboard focus to a day cell (clamped, wraps)
    function focusDay(index) {
        var count = root.dayCells.length
        var target = ((index % count) + count) % count
        var item = dayRepeater.itemAt(target)
        if (item !== null)
            item.forceActiveFocus()
    }

    /// Pick a day: record it and emit the Date Picker contract signal
    function selectDay(index) {
        var cell = root.dayCells[index]
        if (cell === undefined || cell === null)
            return
        root.selectedDate = cell.iso
        root.dateSelected(cell.iso)
    }

    // ── Test hooks (used by tests/tst_calendar.qml) ────────────────
    property alias backdropScrim: backdropScrim
    property alias calendarPanel: calendarPanel
    property alias monthLabel: monthLabel
    property alias prevButton: prevButton
    property alias nextButton: nextButton
    property alias dayRepeater: dayRepeater
    property alias selectionCaption: selectionCaption

    // ── Overlay backdrop (scrim over the desktop) ──────────────────
    // Fades in on presentation (reduced-motion aware): the scrim starts
    // transparent and Component.onCompleted animates it to full so the
    // panel never pops abruptly over the desktop.
    Rectangle {
        id: backdropScrim
        objectName: "calendarScrim"
        anchors.fill: parent
        color: Colors.scrim
        opacity: 0.0
        Behavior on opacity {
            enabled: !root.reducedMotion
            animation: NumberAnimation { duration: Motion.fadeIn }
        }
    }

    // ══════════════════════════════════════════════════════════════
    // Calendar panel (taskbar Calendar function — the top-right
    // overlay treatment shared with Notifications / Quick Settings)
    // ══════════════════════════════════════════════════════════════
    Rectangle {
        id: calendarPanel
        objectName: "calendarPanel"
        anchors {
            top: parent.top
            right: parent.right
            margins: Spacing.paddingLarge
        }
        // Panel trims to the window on narrow layouts
        width: Math.min(380, root.width - Spacing.paddingLarge * 2)
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

            // ── Header: month navigation + title ──
            RowLayout {
                width: parent.width
                spacing: Spacing.gapSmall

                MissionButton {
                    id: prevButton
                    objectName: "calendarPrev"
                    variant: MissionButton.Variant.Secondary
                    compact: true
                    text: qsTr("Prev")
                    onClicked: {
                        var d = root.currentDate
                        root.currentDate = new Date(d.getFullYear(), d.getMonth() - 1, 1)
                    }
                    Accessible.name: qsTr("Previous month")
                    Accessible.description: qsTr("Show the previous month")
                }

                Label {
                    id: monthLabel
                    objectName: "calendarMonth"
                    Layout.fillWidth: true
                    text: root.monthTitle
                    font.pixelSize: Typography.subtitle.size
                    font.weight: Typography.subtitle.weight
                    color: MissionTheme.textPrimary
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    Accessible.role: Accessible.Heading
                    Accessible.name: text
                }

                MissionButton {
                    id: nextButton
                    objectName: "calendarNext"
                    variant: MissionButton.Variant.Secondary
                    compact: true
                    text: qsTr("Next")
                    onClicked: {
                        var d = root.currentDate
                        root.currentDate = new Date(d.getFullYear(), d.getMonth() + 1, 1)
                    }
                    Accessible.name: qsTr("Next month")
                    Accessible.description: qsTr("Show the next month")
                }
            }

            // ── Weekday header (localized, Sunday-first) ──
            Row {
                id: weekdayRow
                width: parent.width
                spacing: dayGrid.columnSpacing

                Repeater {
                    model: root.weekdayLabels

                    delegate: Label {
                        required property var modelData
                        required property int index

                        objectName: "calendarWeekday" + index
                        width: (weekdayRow.width - dayGrid.columnSpacing * 6) / 7
                        horizontalAlignment: Text.AlignHCenter
                        text: String(modelData)
                        font.pixelSize: Typography.caption.size
                        color: MissionTheme.textSecondary
                        Accessible.role: Accessible.StaticText
                        Accessible.name: text
                    }
                }
            }

            // ── Month grid (42 cells; 6 complete weeks) ──
            Grid {
                id: dayGrid
                width: parent.width
                columns: 7
                columnSpacing: Spacing.gapTiny
                rowSpacing: Spacing.gapTiny

                Repeater {
                    id: dayRepeater
                    model: root.dayCells

                    delegate: Rectangle {
                        required property var modelData
                        required property int index

                        id: dayCell
                        objectName: "calendarDay" + index
                        width: (dayGrid.width - dayGrid.columnSpacing * 6) / 7
                        height: Spacing.minimumTouchTarget
                        radius: Radii.input
                        color: {
                            if (root.selectedDate === modelData.iso)
                                return MissionTheme.darkMode ? MissionTheme.primary
                                                             : MissionTheme.primaryContainer
                            if (dayCellMouse.containsMouse)
                                return MissionTheme.surfaceVariant
                            return "transparent"
                        }
                        border.width: root.selectedDate === modelData.iso
                                     ? 0 : 1
                        border.color: root.selectedDate === modelData.iso
                                      ? "transparent"
                                      : (modelData.isToday ? MissionTheme.primary
                                                          : MissionTheme.outlineVariant)
                        activeFocusOnTab: true

                        Behavior on color {
                            enabled: !root.reducedMotion
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
                            visible: dayCell.activeFocus
                        }

                        // Day number (dimmed outside the month)
                        Label {
                            anchors.centerIn: parent
                            text: String(modelData.day)
                            font.pixelSize: Typography.bodySmall.size
                            font.weight: modelData.isToday
                                         ? Typography.weightSemibold
                                         : Typography.weightRegular
                            color: root.selectedDate === modelData.iso
                                   ? (MissionTheme.darkMode ? MissionTheme.contentOnPrimary
                                                           : MissionTheme.contentOnPrimaryContainer)
                                   : (modelData.inMonth ? MissionTheme.textPrimary
                                                        : MissionTheme.textTertiary)
                        }

                        // Today dot (color is never the only indicator —
                        // the Accessible name carries "(today)")
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 4
                            width: 4
                            height: 4
                            radius: 2
                            // Only shown when today is NOT selected (the
                            // selected fill already marks it), so the dot
                            // is always the plain primary marker
                            visible: modelData.isToday &&
                                     root.selectedDate !== modelData.iso
                            color: MissionTheme.primary
                        }

                        MouseArea {
                            id: dayCellMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                dayCell.forceActiveFocus()
                                root.selectDay(index)
                            }
                        }

                        // Keyboard-first: arrows move across the 7-day
                        // grid (Left/Right ±1, Up/Down ±7, wrapping);
                        // Enter/Space pick the focused day
                        Keys.onLeftPressed: root.focusDay(index - 1)
                        Keys.onRightPressed: root.focusDay(index + 1)
                        Keys.onUpPressed: root.focusDay(index - 7)
                        Keys.onDownPressed: root.focusDay(index + 7)
                        Keys.onReturnPressed: root.selectDay(index)
                        Keys.onSpacePressed: root.selectDay(index)

                        Accessible.role: Accessible.Button
                        Accessible.name: {
                            var name = String(modelData.label)
                            if (modelData.isToday)
                                name += qsTr(", today")
                            if (root.selectedDate === modelData.iso)
                                name += qsTr(", selected")
                            return name
                        }
                    }
                }
            }

            // ── Selection caption (defensive; the Date Picker contract
            //    gives the picked date a visible, announced home) ──
            Label {
                id: selectionCaption
                objectName: "calendarSelection"
                visible: root.selectedDate.length > 0
                width: parent.width
                text: qsTr("Selected: %1").arg(root.selectedDate)
                font.pixelSize: Typography.caption.size
                color: MissionTheme.textTertiary
                elide: Text.ElideRight
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }
        }
    }

    // ── Initial focus (keyboard-first) ─────────────────────────────
    // The root claims focus so keyboard users land in the overlay
    // immediately, and the today cell is focused as soon as the panel
    // appears so arrow + Enter works right away (desktop §Keyboard
    // Navigation — the Calendar is keyboard-operable).
    focus: true

    Component.onCompleted: {
        backdropScrim.opacity = 1.0
        root.focusDay(root.todayCellIndex)
    }
}
