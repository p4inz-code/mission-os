/* === This file is part of Mission OS — Calamares branding ===
 *
 *   SPDX-License-Identifier: GPL-3.0-or-later
 *
 *   Mission OS installation slideshow. Shown while the installer
 *   performs the slow execution steps (partitioning, filesystem,
 *   package installation, cleanup).
 */

import QtQuick 2.0;
import calamares.slideshow 1.0;

Presentation
{
    id: presentation

    function nextSlide() {
        presentation.goToNextSlide();
    }

    Timer {
        id: advanceTimer
        interval: 8000
        running: presentation.activatedInCalamares
        repeat: true
        onTriggered: nextSlide()
    }

    Slide {
        centeredText: qsTr("Mission OS\n\n" +
            "Installing Mission OS. This will only take a few minutes.")
    }

    Slide {
        centeredText: qsTr("Privacy First\n\n" +
            "Your data stays on your device. Mission OS ships with privacy controls enabled by default.")
    }

    Slide {
        centeredText: qsTr("Secure by Default\n\n" +
            "Hardened services, policykit-based access control, and a minimal attack surface.")
    }

    Slide {
        centeredText: qsTr("Recovery Ready\n\n" +
            "Mission Recovery Center keeps your system safe and restorable.")
    }

    Slide {
        centeredText: qsTr("Almost Done\n\n" +
            "Finalizing your installation and cleaning up the installer environment.")
    }
}
