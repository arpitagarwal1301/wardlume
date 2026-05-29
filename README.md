# Wardlume

> Cast a watching ward over your Mac. See your AI agents work. Intruders cannot.

[![Build Status](https://img.shields.io/github/actions/workflow/status/arpitagarwal1301/wardlume/build.yml?branch=main&style=flat-square)](https://github.com/arpitagarwal1301/wardlume/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](LICENSE)
[![Platform: macOS Tahoe 26+](https://img.shields.io/badge/platform-macOS%20Tahoe%2026+-lightgrey.svg?style=flat-square)](https://developer.apple.com/macos/)

![Wardlume Hero](https://github.com/arpitagarwal1301/wardlume/blob/main/.github/assets/wardlume-hero.gif)

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
- ✨ **Bait-and-Switch Reaction Model** *(v0.2.0+)*: Each reaction pack defines a base image (shown continuously during ward) and a reaction image (flashes on intrusion). Combined with custom asset slots, this lets users build personalized intrusion theater without writing code.
- ✨ **Minimal Shader Mode** *(v0.2.2)*: The default Silent Professional pack uses a sober refraction-only shader — no rainbow border, sigils, or motes. A calm productivity shield that keeps your terminal readable underneath.
- ✨ **Corner Watching Indicator** *(v0.2.3)*: Silent Professional shows a small pill-shaped indicator with a watching eye in the bottom-right corner during ward — a quiet “yes, the ward is active” signal that flashes red on input intrusion.
- ✨ **Global Activation Hotkey** *(v1.0.1)*: Press ⌘⇧L from anywhere — even while focused in your IDE — to activate or deactivate the ward instantly. No need to click the menu bar.
- ✨ **Quick Pack Switching** *(v1.0.1)*: Switch between Silent Professional, Grumpy Old Man, and Wizard directly from the menu bar dropdown, without opening Preferences.

## Reaction Packs

Wardlume ships with three built-in reaction packs that respond differently when input is detected during ward:

- **Silent Professional** — The default. Sober refracted glass over your live desktop, with a small watching-eye indicator in the corner. No characters, no theatrics — designed for users who want to monitor their terminal mid-AI-session without being tempted to touch.
- **Grumpy Old Man** — Character pack. Shows an old man watching your desktop continuously; an angry reaction image flashes on input intrusion. Audio plays.
- **Wizard** — Character pack. Shows a wizard scene; a wizard reaction flashes on intrusion. Audio plays.

Switch packs in Preferences (Cmd+,).

## Custom Assets

Each reaction pack has three asset slots you can override:

- **Base image** — shown continuously while ward is active (replaces the Metal shader for that activation)
- **Reaction image** — flashes briefly when someone touches input
- **Audio** — plays alongside the reaction image

You can override any of these by dragging a file into the corresponding slot in Preferences (Cmd+,). Your uploads apply to whichever pack is selected — mix and match across packs without creating “custom packs” you have to manage.

Supported formats:
- Images: PNG, JPEG, HEIC, GIF (max 10MB)
- Audio: MP3, M4A, WAV (max 10MB)

Click ✕ on any slot to revert to the active pack’s bundled default.

<!-- TODO: add screenshots: Preferences UI with three slots, silentProfessional ward with corner indicator, Grumpy/Wizard ward states -->

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
3. **Activate the Ward**: Press **⌘⇧L** from anywhere, or click the menu bar icon and select **Activate Ward**. You can also pick a reaction pack from the menu first (Silent Professional, Grumpy Old Man, or Wizard).
4. **Walk Away**: Your desktop is now under an animated glass overlay. Keyboard, mouse, and trackpad are locked. Anyone passing by can watch the screen but cannot interact with it. After a few seconds, an on-screen hint appears showing how to unlock.
5. **Return and Unlock**: Rest your finger on the Touch ID sensor, or press **⌘⇧U** to bring up biometric authentication. Press **⌘⇧L** to toggle the ward off directly. Once authenticated, the ward dissolves and input control is restored instantly.

## Installation and Building

### Install (recommended)

1. Download `Wardlume-1.0.1.dmg` from the [latest release](https://github.com/arpitagarwal1301/wardlume/releases/latest)
2. Open the DMG and drag **Wardlume** into your Applications folder

#### First launch — opening an unsigned app

Wardlume is open source and isn't signed with a paid Apple Developer certificate, so on first launch macOS shows a warning that it *"could not verify Wardlume is free of malware."* This is expected for apps distributed outside the App Store — you can read every line of what Wardlume does in this repository.

**To open it (macOS Sequoia 15 / Tahoe 26):**

1. Double-click Wardlume. When the warning appears, click **Done** — *not* "Move to Bin".
2. Open **System Settings → Privacy & Security**.
3. Scroll down to the **Security** section.
4. You'll see *"Wardlume was blocked to protect your Mac."* Click **Open Anyway**.
5. Authenticate with Touch ID or your password, then click **Open Anyway** once more.

Wardlume opens normally on every launch after this.

**If the "Open Anyway" button doesn't appear**, open Terminal and run:

```bash
xattr -dr com.apple.quarantine /Applications/Wardlume.app
```

Then double-click Wardlume — it opens normally.

### Build from Source

#### Requirements

- **macOS Tahoe 26.0+** or later (older macOS versions are not tested or supported)
- **Apple Silicon Mac** (M1/M2/M3/M4 or later recommended; Intel-based systems
  may experience degraded performance)
- **Xcode 16.0+** with command line tools installed

#### Building and Running

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

Once compiled, Xcode will place the built `Wardlume.app` bundle in your build folder.
You can run it directly from there, or copy the built bundle to your system
`/Applications` folder for convenient launching and long-term usage.

## Permissions

Wardlume needs three macOS permissions. On first ward activation it prompts for them:

- **Screen Recording** — renders the live desktop refraction (uses ScreenCaptureKit to capture the desktop frame buffer; no screen data is ever saved or transmitted)
- **Accessibility** — locks keyboard, mouse, and trackpad
- **Input Monitoring** — detects intrusion attempts

> [!IMPORTANT]
> macOS security policies dictate that after granting these permissions in
> **System Settings → Privacy & Security**, you must completely **quit and
> relaunch** Wardlume for the permissions to take effect.
>
> If the ward activates but input isn't locked, Accessibility or Input Monitoring usually wasn't granted — check those two and relaunch.

For full details on safety mechanisms, local fallbacks, and security boundaries, read [SAFETY_NOTES.md](SAFETY_NOTES.md).

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

Wardlume uses semantic versioning. Current latest: **v1.0.0**.

**Shipped:**
- **v1.0.1** — Global activation hotkey (⌘⇧L), quick pack switching from the menu, on-screen unlock hint, UI polish
- **v1.0.0** — First public release. Full feature set: animated Metal overlay, input lock, Touch ID unlock, three reaction packs, bait-and-switch model, custom asset slots
- **v0.2.3** and earlier — Development line (see [ROADMAP.md](ROADMAP.md) for full history)

**Next:**
- **v1.1+** — Direction TBD. Possible: community pack format, Apple Watch proximity unlock, configurable hotkeys, multi-pack rotation, additional reaction triggers. Open for community input — see issues labeled `roadmap-discussion` or open a GitHub Discussion.

Read the detailed roadmap and milestone breakdown in [ROADMAP.md](ROADMAP.md).

## Contributing

Wardlume is open source, and we welcome contributions from the community.
Whether you are debugging low-level AppKit behaviors, writing custom shaders, or
proposing new features, your help is appreciated.

### Getting Started

- **Issues and Discussions**: Browse existing topics or open a new one in the [Issues](../../issues) section.
- **Pack Asset Contributions**: Designers welcome to contribute base/reaction image sets for existing or new packs. Reaction packs with strong visual identities help showcase what bait-and-switch can do.
- **v0.3.0 Direction**: Open question on what ships next. Community pack format? Sensor fusion? Multi-pack rotation? Weigh in via GitHub Discussions.

## License

Wardlume is released under the MIT License. See [LICENSE](LICENSE) for details.

---

Built with 🪄 by Arpit Agarwal. Inspired by every Mac running AI agents at coffee
shops worldwide.
