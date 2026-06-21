# Wardlume Roadmap

## Shipped

### v1.2.0 — Settings revamp, configurable hotkeys & emergency exit
- [x] **Dark sidebar Settings window** — a System-Settings-style layout (Overview · Pack & assets · Shortcuts · Behavior) replacing the old single-Form preferences; forced dark with a teal theme
- [x] **Configurable hotkeys** — remap the activate (global ⌘⇧L) and unlock (⌘⇧U) shortcuts with an in-app recorder; persisted, validated, and re-registered live
- [x] **Emergency-exit panic key** — optional, OFF by default, no-auth hotkey (default ⌘⇧W) that instantly drops the ward; handled in the event tap so it works while warded
- [x] **Wizard & Grumpy Old Man packs restored** — both character packs (and their bundled assets) are back alongside Silent Professional
- [x] **Overview pane** — live ward status, a permission checklist with one-tap Enable, and Touch ID guidance
- [x] **Reaction & ward fixes** — the reaction overlay and the Touch ID / password prompt now render above the ward (previously hidden behind `CGShieldingWindowLevel`); reactions are suppressed during authentication and for a short grace period after activation
- [x] App icon, README banner, Privacy/Terms pages, and a Support (GitHub Sponsors) link

### v1.1.0 — Security hardening & pack simplification
- [x] **Cmd+Shift+W keep-on-top watchdog** — detects the macOS window-management side-effect that pushed the ward to the back; re-raises the overlay up to 3× and falls back to the real macOS lock screen (`SACLockScreenImmediate`) if it can't recover
- [x] **Menu-bar strip no longer pass-through** — clicks in the top strip now run the same Wardlume-owner check as the rest of the screen, so the Apple menu (Restart/Shut Down/Log Out), Control Center, and other apps' status items can't be used while warded (only our own status item passes)
- [x] **Multi-display blackout** — every non-primary display is covered by an opaque, input-consuming overlay during ward (previously secondary monitors kept showing the live desktop)
- [x] **Fail-closed activation** — `install()` now reports success; if the event tap can't arm (e.g. permission revoked mid-launch), the ward tears down and alerts instead of showing a locked-looking but interactive screen
- [x] **Sleep/wake teardown** — ward deactivates on system/screen sleep so it can't wake into a dead-tap "looks locked, isn't" state
- [x] **Capture-loss teardown** — if Screen Recording is revoked mid-session the ward deactivates instead of freezing on a stale frame
- [x] **Wider input interception** — event mask now also covers system-defined (media/brightness/volume) and tablet/stylus events; tap-timeout now consumes the triggering event instead of leaking it
- [x] **Asset import validation** — user-dropped files are verified decodable (image)/playable (audio) and copied atomically (temp → validate → swap), so a corrupt/renamed file is rejected and a failed copy can't destroy the existing slot
- [x] **Biometric unlock debounce** — rapid ⌘⇧U presses no longer stack SecurityAgent prompts
- [x] **Reaction packs reduced to Silent Professional** — the Grumpy Old Man and Wizard character packs were removed; a user reaction-image override no longer silently converts the minimal pack into a full-screen image

### v1.0.1 — Usability polish
- [x] Global activation hotkey (⌘⇧L) — toggle the ward from anywhere, even while focused in another app (Carbon RegisterEventHotKey, consumed so it doesn't leak to the foreground app)
- [x] Quick pack switching from the menu bar dropdown (no need to open Preferences)
- [x] On-screen unlock hint — fades in a few seconds after activation, shown for all packs
- [x] Corner indicator repositioned above the unlock hint (silentProfessional), synced red intrusion flash across both
- [x] Menu reordered so Quit is last; shortcut hidden on "Deactivate Ward" to avoid showing a non-functional keyEquivalent while warded

### v1.0.0 — First public release
- [x] All v0.2.x features stabilized and released as v1.0.0
- [x] Initial DMG distribution via GitHub Releases
- [x] Marks the product's first stable public release
- [ ] Homebrew tap for `brew install --cask wardlume` (in progress)

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

### v1.1+ — TBD
Possible directions:
- Community pack format (folder-based packs for sharing on GitHub)
- Sensor fusion (Apple Watch proximity unlock)
- Trap mode polish
- PermissionPilot onboarding wizard — replace the first-launch alert with a permissions onboarding wizard built on the in-house [PermissionPilot](https://github.com/arpitagarwal1301/PermissionPilot) Swift package (good-to-have; needs a sandbox-compatibility spike first, since the package targets non-sandboxed apps)

Open for community input — see issues labeled `roadmap-discussion`.

## Deferred
- Apple Silicon binary release
- Notarization + App Store distribution
- Camera capture of intruders (community contribution preferred)