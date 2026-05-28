# Wardlume Roadmap

## Shipped

### v0.1.0 — Foundation (MIT-licensed open source release)
- [x] Animated Metal glass shader overlay
- [x] ScreenCaptureKit live desktop integration
- [x] CGEventTap input lock (keyboard + mouse + trackpad gestures)
- [x] Cmd+Shift+W escape hotkey
- [x] Touch ID / Cmd+Shift+U unlock
- [x] Menu bar app with permission flows

### v0.2.0 — Bait-and-Switch Reactions
- [x] Multi-pack reaction engine (silentProfessional, grumpyOldMan, wizard built-ins)
- [x] Settings UI: pack picker, audio toggle, cooldown duration
- [x] **Bait-and-switch model**: base image + reaction image swap on intrusion
- [x] **User asset slots**: drag-drop base image, reaction image, audio to customize active pack
- [x] Live audio preview in Preferences
- [x] Sandbox entitlement for user-selected file access
- [x] Input lock z-order regression fixes

### v0.2.1 — Default Pack Assets
- [x] Grumpy Old Man pack ships with bundled base image, reaction image, and audio
- [x] Wizard pack ships with bundled base image, reaction image, and audio
- [x] Fixed Xcode 15+ synchronized folder behavior via `explicitFolders` so bundled assets resolve correctly

### v0.2.2 — Minimal Shader Mode
- [x] Added `ShaderStyle` enum to `ReactionPack` (`.full` | `.minimal`)
- [x] silentProfessional now renders sober refracted glass over the live desktop — no rainbow border, sigils, motes, or chromatic aberration
- [x] Grumpy Old Man and Wizard unchanged (full theatrical shader)
- [x] Metal shader branches on `minimalMode` uniform at desktop sampling and final composition

### v0.2.3 — Corner Watching Indicator
- [x] silentProfessional displays a small pill-shaped indicator in the bottom-right corner during ward
- [x] eye.fill SF Symbol on dark backdrop, gentle breathing animation (4s cycle)
- [x] Flashes red briefly on input intrusion
- [x] Visible without dominating — signals "ward is active" without competing with terminal content
- [x] silentProfessional now has a distinct visual identity (minimal shader + corner indicator) separate from character-driven packs

## In Progress

### v0.3.0 — TBD
Possible directions:
- Community pack format (folder-based packs for sharing on GitHub)
- Sensor fusion (Apple Watch proximity unlock)
- Trap mode polish

Open for community input — see issues labeled `roadmap-discussion`.

## Deferred
- Apple Silicon binary release
- Notarization + App Store distribution
- Camera capture of intruders (community contribution preferred)