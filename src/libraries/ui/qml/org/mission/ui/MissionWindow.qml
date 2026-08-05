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
    // The window title is inherited from Kirigami.ApplicationWindow
    // (Window.title); a local `property alias title: root.title` would
    // be self-referential and fail on first instantiation, so there is
    // no title alias here.

    // Children declared inside MissionWindow attach through
    // Kirigami.ApplicationWindow's own default content property — a
    // local `default property alias data: root.contentItem` is not
    // possible because contentItem is read-only.

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
    // The Accessible attached property only attaches to objects
    // deriving from Item or Action — not to a Window — so window-level
    // Accessible.name/description/role are deliberately not declared
    // here (Qt emits a QWARN otherwise). Content-level accessibility
    // lives on the child components (MissionButton, MissionPage, …).
}
