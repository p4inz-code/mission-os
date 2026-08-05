// Mission OS — MissionMenuItem
//
// Theme-styled menu item for Mission OS popup menus (language selector,
// power menu, …). Follows the MissionButton component pattern: a
// standalone component file inside the org.mission.ui module so the
// toolchain's QML compiler (qmlcachegen) can compile it — the previous
// inline `component MissionMenuItem: MenuItem { … }` declaration is
// rejected as a syntax error by the Ubuntu Qt 6.10 toolchain.
//
// Design-system compliance:
//   - Tokens only (Colors, Typography, Spacing, Radii, MissionTheme)
//   - Light + dark theme aware via MissionTheme
//   - Highlighted state (selected/active menu entry) uses primary
//     container tokens; hover uses surfaceVariant
//
// Usage:
//   import org.mission.ui 1.0
//
//   Menu {
//       MissionMenuItem {
//           text: qsTr("Shutdown")
//           onTriggered: shutdown()
//       }
//   }

import QtQuick
import QtQuick.Controls
import org.mission.ui 1.0

MenuItem {
    id: root

    font.pixelSize: Typography.body.size
    contentItem: Label {
        text: parent.text
        color: parent.highlighted
             ? (MissionTheme.darkMode ? MissionTheme.contentOnPrimary
                                     : MissionTheme.contentOnPrimaryContainer)
             : MissionTheme.textPrimary
        font.pixelSize: Typography.body.size
        elide: Text.ElideRight
    }
    background: Rectangle {
        radius: Radii.input
        color: parent.highlighted
             ? (MissionTheme.darkMode ? MissionTheme.primary : MissionTheme.primaryContainer)
             : (parent.hovered ? MissionTheme.surfaceVariant : "transparent")
    }
}
