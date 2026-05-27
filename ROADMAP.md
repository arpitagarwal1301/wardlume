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

## v1.5 — Reaction Modes
- [ ] Phase 2.5a: Intrusion reaction engine (extend CGEventTap intrusion handler)
- [ ] Phase 2.5b: Defensive submode — ward visible, themed reactions
  - [ ] Grumpy Old Man pack ("GET YOUR HANDS OFF MY COMPUTER!")
  - [ ] Gandalf pack ("YOU SHALL NOT PASS")
  - [ ] Scream cat
  - [ ] Silent professional (red flash only, no audio)
- [ ] Phase 2.5c: Bait-and-switch submode — fake "confidential" doc + reveal trap
  - [ ] Salary Trap pack
  - [ ] Confidential Memo pack
- [ ] Phase 2.5d: User upload UI for custom bait + reveal images
- [ ] Phase 2.5e: Optional front-cam capture on trigger (opt-in, local-only)
- [ ] 🎬 v1.5 SHIP — meme-driven launch wave

## v2 — The Ward Knows (sensor fusion)
- [ ] Phase 3a: Apple Watch BLE presence detection (Apple Continuity Protocol)
- [ ] Phase 3b: Vision framework face detection (auto-lock on no face)
- [ ] Phase 3c: Sensor fusion state machine
- [ ] 🎬 v2 SHIP — auto-presence unlock

## Future
- [ ] Voice unlock spells (SpeechAnalyzer hotword + voiceprint embedding)
- [ ] Hand-pose wand gestures (Vision hand pose tracking)
- [ ] Pensieve mode (sensitive-content redaction via Vision)
- [ ] Spell pack ecosystem (community-contributed lock/unlock animations)
- [ ] Heart-rate-gated unlock (watchOS companion)
- [ ] Sidecar trick (iPad as control surface while warded)
- [ ] Single-tap-to-prompt Touch ID (investigate menu bar tap pattern)
- [ ] Cave reveal unlock animation (Half-Blood Prince style)
- [ ] Patronus on unlock (user-chosen animal)

## Architectural Investments (any phase)
- [ ] Animation pack format (.protegopack equivalent for Wardlume)
- [ ] Spell forge CLI for creating packs
- [ ] Gallery site auto-generated from packs repo