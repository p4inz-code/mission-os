// Mission OS — Application Window Foundation
//
// Root application window component for all Mission OS applications.
// Wraps Kirigami.ApplicationWindow with Mission OS theme and tokens.
//
// Usage:
//   import org.mission.ui 1.0
//
//   MissionWindow {
//       title: "My App"
//       width: 1024
//       height: 768
//
//       contentItem: MissionPage {
//           // Application content here
//       }
//   }

// Mission OS — Application Window Foundation
//
// Root application window component for all Mission OS applications.
// Wraps Kirigami.ApplicationWindow with Mission OS theme and tokens.
//
// Usage:
//   import org.mission.ui 1.0
//
//   MissionWindow {
//       title: "My App"
//       width: 1024
//       height: 768
//
//       MissionPage {
//           // Application content here
//       }
//   }

import QtQuick
import QtQuick.Controls
import org.kde.kirigami 2.19 as Kirigami
import org.mission.ui 1.0

Kirigami.ApplicationWindow {
    id: root

    // ── Properties ─────────────────────────────────────────────────
    /// Application title
    property alias title: root.title

    /// The main content of the window
    default property alias data: root.contentItem

    // ── Window Defaults ────────────────────────────────────────────
    minimumWidth: 400
    minimumHeight: 300
    width: 1024
    height: 768

    // ── Theme Colors ───────────────────────────────────────────────
    background: Rectangle {
        color: MissionTheme.background
    }

    // ── Accessibility ──────────────────────────────────────────────
    Accessible.name: title
    Accessible.description: qsTr("Mission OS application window")
    Accessible.role: Accessible.Window
}
