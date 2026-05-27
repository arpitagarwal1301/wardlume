# Wardlume

> Cast a watching ward over your Mac. See your AI agents work. Intruders cannot.

[![Build Status](https://img.shields.io/github/actions/workflow/status/arpitagarwal1301/wardlume/build.yml?branch=main&style=flat-square)](https://github.com/arpitagarwal1301/wardlume/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](LICENSE)
[![Platform: macOS Tahoe 26+](https://img.shields.io/badge/platform-macOS%20Tahoe%2026+-lightgrey.svg?style=flat-square)](https://developer.apple.com/macos/)

![Wardlume Hero](https://raw.githubusercontent.com/arpitagarwal1301/wardlume/main/.github/assets/wardlume-hero.gif)

With the rise of autonomous AI coding agents like Claude Code and Cursor,
developers frequently leave their machines running complex, long-running tasks
that they want to monitor. However, stepping away from your Mac presents a
frustrating trade-off: lock your screen and lose all visibility into the
agent's progress, or leave it unlocked and invite physical tampering.
Wardlume resolves this by locking all keyboard, mouse, and trackpad inputs
while keeping your screen completely visible under an animated glass overlay.
The result is a magical ward that secures your workstation from physical
intrusion while allowing you or anyone in the room to watch the agent build
in real time.

## What's Working

- ✨ **Animated Metal Glass Shader**: Renders an enchanted glass refraction
  layer directly over your live desktop pixels using a custom Metal fragment
  shader. The visuals feature a flowing auroral border, drifting light motes,
  and faint floating sigils to indicate that the machine is warded.
- ✨ **Input Interception via CGEventTap**: Hard-locks keyboard, mouse, and
  trackpad click/scroll inputs at the macOS session event tap level. This
  swallows unauthorized input events before they reach active application
  windows.
- ✨ **Touch ID Integration**: Out-of-the-box biometric unlock using Apple's
  LocalAuthentication framework, providing instant ward deactivation when you
  touch the sensor, and automatically falling back to your user password if
  Touch ID is locked out or unavailable.
- ✨ **Universal Escape Hotkey**: Immediate ward deactivation via the
  `Cmd+Shift+W` keyboard combination. This shortcut is routed directly inside
  the low-level event tap callback for high reliability, even if the main
  window loses system focus.
- ✨ **Touch ID Prompt Hotkey**: A dedicated `Cmd+Shift+U` hotkey to manually
  summon the biometric authentication prompt at any time while the ward is
  active, bypassing the need to interact with the menu bar.
- ✨ **Accessibility Support**: Automatically respects the macOS "Reduce Motion"
  system preference. When enabled, the application adjusts visual animations
  and scales down shader frame rates to maintain system performance and user
  comfort.
- ✨ **Visual Intrusion Pulse**: Triggers an instantaneous, high-contrast
  auroral border pulse whenever an unauthorized keypress or click attempt is
  detected. This warns intruders off without displaying password boxes or
  interrupting the running agent.

## Quick Demo

You can see the ward in action in the hero demonstration at the top of this
document, which illustrates the flowing auroral border, live desktop pixel
refraction, and intrusion pulses.

For a demonstration of the Touch ID unlock flow and the smooth dissolution of the
ward, see the placeholder layout below. A complete walkthrough GIF illustrating
this process will be added here in the future:

<!-- Touch ID Unlock Demo GIF Placeholder -->
<!-- ![Wardlume Touch ID Unlock Flow](https://raw.githubusercontent.com/arpitagarwal1301/wardlume/main/.github/assets/wardlume-unlock.gif) -->

## How to Use

1. **Launch the App**: Open Wardlume from your Applications folder. The app runs
   quietly in your macOS menu bar.
2. **Configure Settings (Optional)**: Adjust shader parameters or hotkeys via the
   menu bar dropdown prior to activation.
3. **Activate the Ward**: Click the menu bar icon and select **Activate Ward**,
   or trigger it via your configured activation hotkey.
4. **Walk Away**: Your desktop is now obscured by an animated glass refraction
   layer. Keyboard, mouse, and trackpad gestures are locked. Anyone passing by
   can view the screen but cannot interact with it.
5. **Return and Unlock**: Rest your finger on the Touch ID sensor, or press
   `Cmd+Shift+U` to bring up the system authentication sheet. Alternatively,
   use the global escape hotkey `Cmd+Shift+W` to prompt for password unlock.
   Once authenticated, the ward dissolves and input control is instantly restored.

## Installation and Building

Wardlume is currently in pre-release development. To use the application, you must
clone the repository and compile it from source using Xcode.

### Requirements

- **macOS Tahoe 26.0+** or later (older macOS versions are not tested or supported)
- **Apple Silicon Mac** (M1/M2/M3/M4 or later recommended; Intel-based systems
  may experience degraded performance)
- **Xcode 16.0+** with command line tools installed

### Building from Source

To build and run Wardlume locally, execute the following commands in your terminal:

```bash
git clone https://github.com/arpitagarwal1301/wardlume.git
cd wardlume
open Wardlume.xcodeproj
```

Once Xcode opens:
1. Select the `Wardlume` scheme from the scheme selector dropdown in the workspace
   toolbar.
2. Choose your active macOS machine (My Mac) as the run destination.
3. Press `Cmd+R` (or select **Product → Run** from the menu) to compile and launch
   the application.

### Running the App

Once compiled, Xcode will place the built `Wardlume.app` bundle in your build folder.
You can run it directly from there, or copy the built bundle to your system
`/Applications` folder for convenient launching and long-term usage.

## Permissions

To successfully intercept events and record the screen for the refraction shader,
Wardlume requires three system-level permissions. Without these, the application
cannot protect your desktop:

- **Screen Recording**: Required by ScreenCaptureKit to capture the desktop frame
  buffer. The app uses these pixels locally to feed the Metal fragment shader for
  real-time refraction; no screen data is ever saved or transmitted.
- **Accessibility**: Required to establish the low-level `CGEventTap` which blocks
  keyboard and mouse inputs.
- **Input Monitoring**: Required to detect intrusion attempts (such as keypresses
  or mouse clicks) while the ward is active, which triggers the visual pulse
  animation.

> [!IMPORTANT]
> macOS security policies dictate that after granting these permissions in
> **System Settings → Privacy & Security**, you must completely **quit and
> relaunch** Wardlume for the permissions to take effect.
>
> For full details on safety mechanisms, local fallbacks, and security boundaries,
> read [SAFETY_NOTES.md](SAFETY_NOTES.md).

## Architecture

Wardlume is built on Swift, SwiftUI, AppKit, Metal, and native macOS system APIs
to achieve high performance and low-level control.

```
                  +-----------------------------------+
                  |        Wardlume Menu Bar          |
                  +-----------------+-----------------+
                                    |
                           Activates Ward Window
                                    |
                                    v
                  +-----------------------------------+
                  |         ScreenSaver Window        |
                  |     (Overlay at highest level)    |
                  +-------+-------------------+-------+
                          |                   |
               Renders live refraction        Captures screen pixels
                          |                   |
                          v                   v
                  +---------------+   +---------------+
                  |  Metal Shader |   |   Screen-     |
                  |   Refraction  |<--|  CaptureKit   |
                  +---------------+   +---------------+
                          ^
                          | Triggers Intrusion Pulse
                          |
                  +---------------+
                  |  CGEventTap   | <-- Intercepts keyboard & mouse
                  +---------------+
```

### Menu Bar Interface & Overlay Window
The application runs as a SwiftUI-based menu bar extra. When activated, it spawns
a full-screen AppKit `NSWindow` configured with a window level set to
`.screenSaver` to sit on top of all application windows. The window is
borderless, covers all active screens, and is set to ignore mouse events during
lock except for catching inputs to trigger intrusion indicators.

### Desktop Capture & Metal Refraction
- **ScreenCaptureKit**: Captures the live desktop texture with zero-copy efficiency,
  providing an `IOSurface` backing. This avoids high CPU usage and ensures low
  power consumption while running.
- **Metal Shader Pipeline**: When a screen capture stream begins, SCStream sends
  frame samples containing an `IOSurface` reference. We bind this surface to a
  MTLTexture in Metal, passing it to our shader. Our fragment shader does a
  viewport-relative UV lookup, applying a small offset based on a noise function
  to simulate a refractive glass pane. It also renders chromatic aberration, auroral
  border animations, iridescent flows, drifting motes, and faint floating sigils.

### Input Interception
- **CGEventTap**: An event tap is installed at the `.cgSessionEventTap` location
  using the `.headInsertEventTap` placement. This intercepts all mouse clicks,
  movements, and key presses before they reach other applications, checking
  against a strict process ID (PID) whitelist. Any click target landing inside a
  whitelisted window (like our menu dropdown or the Touch ID alert overlay) is
  allowed to pass through, while all others are intercepted and discarded.
- **NSEvent Local Monitor**: Intercepts trackpad swipe gestures (e.g., three- or
  four-finger swiping) which bypass standard event taps because gesture routing
  occurs directly in the macOS WindowServer.
- **LocalAuthentication**: Standard API for Touch ID biometric verification. The
  Touch ID dialog is managed by the macOS `SecurityAgent`, running in a secure,
  privileged layer that overrides Wardlume's event interception.

## Roadmap

Our development path is split into major milestones focused on customization,
defense patterns, and automation:

- **v1.0 (Current)**: Solidify core locking, performance optimizations for
  ScreenCaptureKit, and permissions polish.
- **v1.5 (Reaction Modes)**: Introducing themed intrusion responses. When an
  unauthorized user attempts to interact with your Mac, the ward can trigger
  various defensive reactions:
  - *Grumpy Old Man*: Displays angry text alerts and sound effects.
  - *Gandalf*: Shows a magical shield flash with the quote "You shall not pass!".
  - *Bait-and-Switch*: Displays a fake "confidential document" overlay that,
    when clicked, flashes a red warning and logs the intrusion attempt.
- **v2.0 (Sensor Fusion)**: Auto-warding and presence-based locking utilizing
  Apple Watch BLE signals and local face detection using the Vision framework.

Read the detailed roadmap and milestone breakdown in [ROADMAP.md](ROADMAP.md).

## Contributing

Wardlume is open source, and we welcome contributions from the community.
Whether you are debugging low-level AppKit behaviors, writing custom shaders, or
proposing new features, your help is appreciated.

### Getting Started

- **Good First Issue**: Fix the menu dropdown action firing bug. When the ward
  overlay is active, clicking items in the menu bar dropdown registers visually
  but fails to execute. Read the detailed analysis and root cause in
  [SAFETY_NOTES.md](SAFETY_NOTES.md#menu-bar-dropdown-items-do-not-fire-while-ward-is-active)
  to start.
- **Issues and Discussions**: Browse existing topics or open a new one in the
  [Issues](../../issues) section.
- **Custom Packs**: If you are interested in designing custom unlock animations or
  reaction packs for v1.5, we welcome early ideas and shader prototypes in
  GitHub Discussions.

## License

Wardlume is released under the MIT License. See [LICENSE](LICENSE) for details.

---

Built with 🪄 by Arpit Agarwal. Inspired by every Mac running AI agents at coffee
shops worldwide.
