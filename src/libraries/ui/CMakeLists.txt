# mission-ui — Mission OS UI Component Library
#
# This library provides reusable QML components, design tokens,
# theme support, and accessibility wrappers for all Mission OS
# applications.
#
# Stack: Qt 6, KDE Kirigami, KDE Frameworks
#
# Module: org.mission.ui (QML import)

cmake_minimum_required(VERSION 3.20)

project(mission-ui
    VERSION 0.1.0
    DESCRIPTION "Mission OS UI Component Library"
    LANGUAGES CXX
)

# ── Options ─────────────────────────────────────────────────────────
option(BUILD_SHARED_LIBS "Build shared libraries" ON)
option(BUILD_MISSION_UI_QML "Build QML module" ON)

# ── C++ Standard ────────────────────────────────────────────────────
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# ── Qt 6 Discovery ──────────────────────────────────────────────────
find_package(Qt6 REQUIRED COMPONENTS
    Core
    Qml
    Quick
    QuickControls2
    Svg
)

# ── KDE Frameworks Discovery ────────────────────────────────────────
find_package(KF6 REQUIRED COMPONENTS
    Kirigami
    CoreAddons
    I18n
)

# ── Sources ─────────────────────────────────────────────────────────
set(MISSION_UI_SOURCES
    src/version.cpp
    src/missionuiplugin.cpp
)

set(MISSION_UI_HEADERS
    include/mission/version.h
    include/mission/missionuiplugin.h
)

# ── QML Module ──────────────────────────────────────────────────────
set(MISSION_UI_QML_FILES
    qml/org/mission/ui/qmldir
    qml/org/mission/ui/MissionTheme.qml
    qml/org/mission/ui/Colors.qml
    qml/org/mission/ui/Typography.qml
    qml/org/mission/ui/Spacing.qml
    qml/org/mission/ui/Radii.qml
    qml/org/mission/ui/Elevation.qml
    qml/org/mission/ui/Motion.qml
    qml/org/mission/ui/MissionWindow.qml
    qml/org/mission/ui/MissionPage.qml
)

# ── QML Resources ───────────────────────────────────────────────────
qt6_add_qml_module(mission-ui
    URI org.mission.ui
    VERSION 0.1
    QML_FILES ${MISSION_UI_QML_FILES}
    NO_RESOURCE_TARGET_PATH
)

# ── Library Target ──────────────────────────────────────────────────
target_sources(mission-ui
    PRIVATE
        ${MISSION_UI_SOURCES}
        ${MISSION_UI_HEADERS}
)

target_include_directories(mission-ui
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:include/mission>
)

# ── Link Dependencies ───────────────────────────────────────────────
target_link_libraries(mission-ui
    PUBLIC
        Qt6::Core
        Qt6::Qml
        Qt6::Quick
        Qt6::QuickControls2
    PRIVATE
        KF6::Kirigami
        KF6::CoreAddons
        KF6::I18n
)

# Version definitions for the library target
target_compile_definitions(mission-ui
    PRIVATE
        MISSION_UI_VERSION_MAJOR=${PROJECT_VERSION_MAJOR}
        MISSION_UI_VERSION_MINOR=${PROJECT_VERSION_MINOR}
        MISSION_UI_VERSION_PATCH=${PROJECT_VERSION_PATCH}
        MISSION_UI_VERSION_STRING="${PROJECT_VERSION}"
)

# ── Smoke Test (CI Verification) ──────────────────────────────────
# Static-verify that QML module imports resolve correctly.
# Requires qmlsc (Qt 6 QML compiler) in the build environment.
set(MISSION_UI_SMOKE_TEST
    ${CMAKE_CURRENT_SOURCE_DIR}/qml/org/mission/ui/SmokeTest.qml
)

if(Qt6QmlTools_FOUND)
    qt6_qml_type_registration(mission-ui
        URI org.mission.ui
        CLASSNAME MissionUiPlugin
    )
    qt6_generate_qmltypes(mission-ui
        URI org.mission.ui
        CLASSNAME MissionUiPlugin
    )
endif()

# ── Install ─────────────────────────────────────────────────────────
install(TARGETS mission-ui
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
)

install(FILES ${MISSION_UI_HEADERS}
    DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/mission
)
