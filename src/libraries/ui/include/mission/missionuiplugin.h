#ifndef MISSION_UI_PLUGIN_H
#define MISSION_UI_PLUGIN_H

/// @file
/// QML plugin entry point for the org.mission.ui module.
///
/// Registers the mission-ui design tokens and theme foundation
/// with the Qt Quick runtime so QML imports resolve correctly.

#include <QQmlEngineExtensionPlugin>

class MissionUiPlugin : public QQmlEngineExtensionPlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID "org.qt-project.Qt.QQmlEngineExtensionInterface" FILE "qmldir")
};

#endif // MISSION_UI_PLUGIN_H
