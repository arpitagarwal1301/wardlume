# Wardlume

> Cast a watching ward over your Mac. See your AI agents work. Intruders cannot.

Wardlume is a macOS menu bar app that overlays your desktop with an animated magical glass shader and locks keyboard, mouse, and trackpad input while the ward is active — so you can leave your machine visible (and running AI coding agents, watched from across the room) without anyone being able to touch it.

**Status:** in development. v1 not yet shipped. See [ROADMAP.md](ROADMAP.md) for progress.

## How it works

While the ward is active:
- A real-time Metal shader renders enchanted glass over your live desktop (refraction, flowing auroral border, drifting motes, faint floating sigils)
- All keyboard, mouse, and trackpad input is intercepted and silently discarded
- An intrusion pulse fires (border brightness spike) when someone tries to interact
- The desktop and AI agent output remain fully visible underneath — you can monitor from across the room

When you return, unlock with Touch ID or a keyboard hotkey, and the ward dissolves.

## Current state (pre-v1)

- ✅ Magical animated shader over live desktop (ScreenCaptureKit + Metal)
- ✅ Input locking via CGEventTap (keyboard, mouse, trackpad gestures)
- ✅ Touch ID unlock + password fallback
- ✅ Cmd+Shift+W (escape) and Cmd+Shift+U (Touch ID prompt) hotkeys
- 🚧 Settings/preferences UI
- 🚧 Polished onboarding for first-run permission requests

## Requirements

- macOS Tahoe 26 or later (older versions untested)
- Apple Silicon recommended (Intel may run with degraded performance)
- Touch ID hardware optional (password fallback supported)

Three permissions are requested on first launch:
- **Screen Recording** — to capture and refract the live desktop
- **Accessibility** — to install the input event tap
- **Input Monitoring** — to detect intrusion attempts

See [SAFETY_NOTES.md](SAFETY_NOTES.md) for escape hatches and known limitations.

## Building

This is a native macOS app. Requires Xcode 16 or later.

```bash
git clone https://github.com/arpitagarwal1301/wardlume.git
cd wardlume
open Wardlume.xcodeproj
```

Then ⌘R in Xcode.

## Contributing

Wardlume is open source under the MIT License. Contributions welcome.

A particularly good starter issue: see the dropdown action firing bug in our [issues list](../../issues) — diagnosis is well-documented and the fix should be self-contained.

## License

MIT — see [LICENSE](LICENSE).

---

Built with 🪄 by Arpit Agarwal. Inspired by every Mac running AI agents at coffee shops worldwide.
