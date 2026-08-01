// Mission OS — Page / Surface Foundation
//
// Basic page container for Mission OS application content.
// Provides consistent padding, background, and scrolling.
//
// Usage:
//   MissionPage {
//       ColumnLayout {
//           // Page content
//       }
//   }

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.mission.ui 1.0

FocusScope {
    id: root

    // ── Properties ─────────────────────────────────────────────────
    /// Page title (optional)
    property string pageTitle: ""

    /// Page icon name (optional, for future use)
    property string pageIcon: ""

    /// Whether to show a page header with title
    property bool showHeader: pageTitle.length > 0

    /// The main content of the page
    default property alias data: contentArea.data

    /// Padding around the page content
    property int padding: Spacing.paddingPage

    /// Whether the page scrolls
    property bool scrollable: false

    // ── Layout ─────────────────────────────────────────────────────
    implicitWidth: 640
    implicitHeight: 480

    // ── Background ─────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: MissionTheme.background
    }

    // ── Page Header ────────────────────────────────────────────────
    Rectangle {
        id: header
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        height: showHeader ? Spacing.headerHeight : 0
        visible: showHeader
        color: MissionTheme.surface

        Label {
            anchors {
                left: parent.left
                leftMargin: Spacing.paddingMedium
                verticalCenter: parent.verticalCenter
            }
            text: pageTitle
            font.pixelSize: Typography.title.size
            font.weight: Typography.title.weight
            color: MissionTheme.textPrimary
            elide: Text.ElideRight
        }

        // Bottom border
        Rectangle {
            anchors {
                bottom: parent.bottom
                left: parent.left
                right: parent.right
            }
            height: 1
            color: MissionTheme.outline
        }
    }

    // ── Content Area ───────────────────────────────────────────────
    Flickable {
        id: flickable
        anchors {
            top: showHeader ? header.bottom : parent.top
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        contentHeight: contentArea.height + padding * 2
        clip: true
        interactive: scrollable
        ScrollIndicator.vertical: ScrollIndicator { visible: root.scrollable }

        Column {
            id: contentArea
            x: padding
            y: padding
            width: parent.width - padding * 2
            spacing: Spacing.gapLarge
        }
    }

    // ── Accessibility ──────────────────────────────────────────────
    Accessible.name: pageTitle.length > 0 ? pageTitle : qsTr("Page")
    Accessible.description: qsTr("Mission OS page content area")
    Accessible.role: Accessible.Pane
}
