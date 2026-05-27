# Wardlume Roadmap

## v1 — The Magical Ward
- [x] Phase 1a: Menu bar + transparent overlay window
- [x] Phase 1b: Enchanted glass shader with flowing border, motes, sigils, iridescence
- [x] Phase 1c: ScreenCaptureKit live desktop integration (real refraction on real pixels)
- [x] Phase 2a: Input locking via CGEventTap (keyboard + mouse + gestures)
- [x] Phase 2b: Touch ID unlock + Cmd+Shift+U hotkey + dropdown whitelist
- [ ] Phase 2c: Settings/Preferences UI (sliders for shader params, accessibility toggles)
- [ ] Onboarding flow polish (permission ceremony, themed)
- [ ] README + screenshots + demo GIF
- [ ] 🎬 v1 SHIP

## v1.x — Polish (community contributions welcome)
- [ ] Menu bar dropdown items don't fire while ward is active — see SAFETY_NOTES
- [ ] "Unlock with Touch ID..." accessible without keyboard
- [ ] NSWindow makeKeyWindow warning at activation (cosmetic console noise)
- [ ] Investigate `_NSDetectedLayoutRecursion` warning when reaction overlay
      first appears (logged once per session, no functional impact, likely
      resolves itself when placeholder NSView is replaced with real pack
      content in Phase 2.5b)

## v1.5 — Defensive Reaction Modes

The ward is visible. When an intruder touches the keyboard or trackpad,
a themed reaction fires instead of (or in addition to) the intrusion pulse.
Reactions are punitive only — they do not prompt for password. The user
unlocks via the existing paths (Touch ID, Cmd+Shift+U, Cmd+Shift+W).

- [ ] Phase 2.5a: Hardcoded reaction engine
  - Intercept input via existing CGEventTap intrusion handler
  - Detect intrusion → trigger active reaction (full-screen overlay + optional audio)
  - Configurable cooldown between reactions (default 5s)
  - Auto-reset to ward state after 15s
- [ ] Phase 2.5b: Three built-in reaction packs
  - Grumpy Old Man (yelling image + audio)
  - Gandalf ("YOU SHALL NOT PASS" + audio)
  - Silent Professional (red frame flash, no audio)
- [ ] Phase 2.5c: Settings additions
  - Pack picker (which reaction is active)
  - Audio toggle (default off)
  - Cooldown slider (1s / 3s / 5s / 10s)
- [ ] 🎬 v1.5 SHIP

## v1.6 — Bait-and-Switch Trap Mode

A separate top-level mode. Ward overlay is NOT visible. A user-chosen
"bait" document is shown fullscreen, inviting curiosity. On any input
attempt, a "reveal" image/video fires, then bait returns.

- [ ] Phase 2.6a: Mode toggle in menu bar — "Ward" vs "Trap"
- [ ] Phase 2.6b: Reaction engine refactored to support bait+reveal pairs
- [ ] Phase 2.6c: Settings — upload custom bait/reveal assets
- [ ] Phase 2.6d: Two built-in bait packs
  - Salary Trap (fake confidential salary doc → ghost reveal)
  - Confidential Memo (fake "do not open" memo → screamer reveal)
- [ ] 🎬 v1.6 SHIP

## v2 — Pack Engine + Sensor Fusion (when there is real user demand)

- [ ] Public pack format (JSON manifest + assets folder)
- [ ] Community pack contribution flow
- [ ] Apple Watch BLE presence detection
- [ ] Vision framework face detection
- [ ] Sensor fusion auto-lock/unlock state machine

## Future (community contributions welcome)

- [ ] Front-cam capture on trigger (requires privacy-careful design)
- [ ] Voice unlock spells (SpeechAnalyzer + voiceprint)
- [ ] Hand-pose wand gestures
- [ ] Pensieve mode (sensitive content auto-redaction)
- [ ] Heart-rate-gated unlock via watchOS companion

## Architectural Investments (any phase)
- [ ] Animation pack format (.protegopack equivalent for Wardlume)
- [ ] Spell forge CLI for creating packs
- [ ] Gallery site auto-generated from packs repo