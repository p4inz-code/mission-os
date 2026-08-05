#ifndef MISSION_UI_PLUGIN_H
#define MISSION_UI_PLUGIN_H

/// @file
/// QML plugin entry point for the org.mission.ui module.
///
/// Registers the mission-ui design tokens and theme foundation
/// with the Qt Quick runtime so QML imports resolve correctly.

#include <QQmlEngineExtensionPlugin>

// NOTE: the Qt 6 pattern omits FILE "qmldir" from Q_PLUGIN_METADATA:
// qt6_add_qml_module() generates and wires the module's qmldir itself,
// and moc cannot resolve a relative "qmldir" reference in the Qt 6.10
// build-tree layout (build fails with 'Plugin Metadata file "qmldir"
// does not exist'). The generated qmldir in the module output directory
// declares the plugin, so discovery is unaffected.
class MissionUiPlugin : public QQmlEngineExtensionPlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID "org.qt-project.Qt.QQmlEngineExtensionInterface")
};

#endif // MISSION_UI_PLUGIN_H
