# Mission OS Wallpaper Assets

This directory contains the default Mission OS wallpaper assets.

## Required Files

For the Nightly ISO, the following file is shipped (installed by
`build-nightly.sh` into `/usr/share/wallpapers/mission-os/`):

- `contents/images/3840x2160.svg` — Default desktop wallpaper (3840x2160 SVG)
  - Dark graphite/slate gradient background
  - Subtle Mission OS logo watermark (bottom-right corner)
  - Restrained violet/cool-blue accent stripe or geometric element
  - No text, no cyberpunk elements, no green-terminal aesthetic

Optional future assets (not currently shipped):

- `mission-os-light.png` — Light variant (future)
- `mission-os-vertical.png` — Mobile/tablet variant (future)

## Design Guidelines

1. **Color Palette:** Dark graphite (#131519 as base) with restrained violet accent
2. **No Text:** Wallpapers should not include version numbers or labels
3. **No Branding Overlay:** The wallpaper should be a clean visual backdrop
4. **Subtle:** Avoid gradients that are distracting or cause readability issues
5. **Minimal:** Follow the Apple/Linear/Proton design philosophy

## Source Files

SVG source files should be stored alongside PNG renders for reproducibility.

## Generation

For Nightly builds without custom artwork, a solid-color background
(#131519 — Mission OS dark graphite) is used as fallback.
