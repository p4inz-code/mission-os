#ifndef MISSION_UI_VERSION_H
#define MISSION_UI_VERSION_H

/// @file
/// Version information for the mission-ui library.

/// Major version component.
#define MISSION_UI_VERSION_MAJOR 0
/// Minor version component.
#define MISSION_UI_VERSION_MINOR 1
/// Patch version component.
#define MISSION_UI_VERSION_PATCH 0

/// Full version as a string.
#define MISSION_UI_VERSION_STRING "0.1.0"

/// Library identifier.
#define MISSION_UI_IDENTIFIER "mission-ui"

/// Return the library version as a string.
const char* mission_ui_version(void);

#endif /* MISSION_UI_VERSION_H */
