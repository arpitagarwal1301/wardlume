# Changelog

Downloads for every version are on the [Releases](https://github.com/arpitagarwal1301/wardlume/releases) page. Update with `brew upgrade --cask wardlume`.

## v1.7.2 — Cleaner Settings and menu · 2026-09-27
- 🧭 **Settings reorganized:** Overview · Lock & unlock · Automation · Displays & gestures · Intruder reactions · Advanced.
- 🔢 **"How Wardlume works"** on Overview: Lock → Step away → Unlock, with your own shortcuts.
- ✏️ **Clearer shortcut editing:** edit and reset buttons with tooltips.
- ⚠️ Emergency exit and **Reset all** now live in **Advanced**.
- 📋 **Menu bar:** shows your own activate shortcut, has a quick Auto-ward toggle and **Check for Updates…**, and only shows permissions setup when something's missing.

## v1.7.1 — New download home · 2026-09-27
- Wardlume now lives at **[wardlume](https://github.com/arpitagarwal1301/wardlume)**. **Check updates**, **Privacy**, and **Terms** in the app point here.
- No other changes. Your settings and permissions carry over.

## v1.7.0 — Apple Watch unlock · 2026-09-26
- ⌚ **Tap to unlock with Apple Watch.** Tap any key or the trackpad while warded, then double-press your watch's side button.
- 🔐 **The unlock shortcut accepts your watch too:** Touch ID, Apple Watch, or password.
- 🧭 **Apple Watch card in Settings → Overview**, with status, setup steps, and **Send test to watch**. Requests name your Mac.

## v1.6.0 — Launch at login & auto-ward when idle · 2026-09-26
- 🚀 **Launch at login:** starts quietly in the menu bar. On by default, and your choice is respected if you turn it off.
- ⏱️ **Auto-ward when idle:** casts the ward after 1–15 minutes without input, after a 10-second cancelable countdown. Off by default.

## v1.5.0 — Multi-monitor ward & security fixes · 2026-09-26
- 🖥️ The ward appears on the **display you activate it from**. Other monitors stay visible but locked, or can be blacked out.
- 🔌 **Security:** unplugging a monitor no longer unlocks your Mac.
- ⚙️ **Security:** Settings can no longer be clicked through the ward.
- ✋ Trackpad gestures (Mission Control, Spaces, Launchpad) are now really blocked, and the ward follows Space switches.

## v1.4.0 — Keep Mac awake while warded · 2026-09-26
- ☕ **Keep Mac awake:** the display and system don't idle-sleep while warded. On by default.
- 🪟 **Fixed:** the one-time screen-capture prompt no longer hides behind the ward.

## v1.3.0 — Seamless permissions & first-launch onboarding · 2026-07-02
- 🧭 **Guided setup** for all three permissions in one window, powered by [PermissionPilot](https://github.com/arpitagarwal1301/PermissionPilot).
- Opening Wardlume now shows setup (if something's missing) or Settings → Overview.
- **Permissions Setup…** in the menu bar re-runs the wizard at any time.

## v1.2.0 — Settings revamp, configurable hotkeys & emergency exit · 2026-06-21
- New dark **Settings** window: Overview · Pack & assets · Shortcuts · Behavior.
- **Configurable** activate and unlock shortcuts.
- Optional **emergency-exit** key (off by default).
- Wizard and Grumpy Old Man reaction packs are back.
- Includes the v1.1.0 hardening: ward watchdog, a locked menu bar, black-out of other displays, sleep/wake safety, and blocking of media keys.

## v1.0.1 — Global activation hotkey + polish · 2026-05-29
- **⌘⇧L works from anywhere**, even while you're focused in another app.
- Quick pack switching from the menu bar, and an on-screen unlock hint.

## v1.0.0 — First public release · 2026-05-28
- Animated glass ward over the live desktop, input lock, and Touch ID unlock.
- Reaction packs (Silent Professional, Grumpy Old Man, Wizard) and custom image and sound slots.
