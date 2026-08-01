# Mission OS — Top-Level CMake
#
# This is the CMake entry point for C++ components.
# Rust components are managed via Cargo.
#
# Relationship:
#   CMake handles: mission-ui, future applications (QML/C++)
#   Cargo handles: mission-core, mission-crypto, future services (Rust)
#
# The Makefile orchestrates both build systems.

cmake_minimum_required(VERSION 3.20)

project(mission-os
    VERSION 0.1.0
    DESCRIPTION "Mission OS — Portable, Privacy-First Operating System"
    LANGUAGES CXX
)

# ── Options ─────────────────────────────────────────────────────────
option(BUILD_SHARED_LIBS "Build shared libraries" ON)
option(BUILD_TESTING "Build tests" ON)

# ── C++ Standard ────────────────────────────────────────────────────
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# ── Global properties ───────────────────────────────────────────────
set(CMAKE_INSTALL_PREFIX "/usr" CACHE STRING "Install prefix")
set(CMAKE_INSTALL_LIBDIR "${CMAKE_INSTALL_PREFIX}/lib" CACHE STRING "Library directory")
set(CMAKE_INSTALL_INCLUDEDIR "${CMAKE_INSTALL_PREFIX}/include" CACHE STRING "Include directory")

# ── Subdirectories ──────────────────────────────────────────────────
add_subdirectory(src/libraries/ui)

# ── Install root CMake config ───────────────────────────────────────
# (placeholder for future packaging support)
