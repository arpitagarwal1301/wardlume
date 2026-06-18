# Wardlume — Safety Notes

## Escape Hatches (every user must know these)

Two reliable ways to deactivate the ward, in priority order:

1. **Cmd+Shift+U** — Trigger Touch ID prompt.
   Handled inside the CGEventTap callback. Opens the native macOS Touch ID sheet
   via LocalAuthentication. Falls back to password if biometric is locked out or
   unavailable. Repeated rapid presses are debounced so they can't stack multiple
   prompts.

2. **Cmd+Option+Esc** — Force Quit Wardlume.
   macOS-reserved shortcut that no third-party app can intercept. Use this
   if the Touch ID path fails. Sleep (closing the lid) is also a guaranteed
   exit — sleep tears down event taps, and Wardlume explicitly deactivates
   the ward on sleep/screen-sleep so it can never wake into a "looks locked but
   isn't" state.

> **Note:** Cmd+Shift+W is intentionally NOT an escape hatch. It is consumed
> silently like any other blocked keystroke while the ward is active. Use
> Cmd+Shift+U or Cmd+Option+Esc instead.

## What Wardlume Cannot Intercept (by design)

- Cmd+Option+Esc (force quit)
- Power button press
- Touch ID sensor (LocalAuthentication renders above intercept points via SecurityAgent)
- Wardlume's own menu bar icon (whitelisted — see Whitelist Architecture)
- Cmd+Shift+W (intentionally passed through as a blocked keystroke, not an escape)

These are NOT bugs — they are guaranteed escape paths macOS protects, plus an intentional
design decision to prevent accidental ward dismissal via window-management shortcuts.

As of v1.1.0, system-defined media keys (brightness, volume, play/pause) and
tablet/stylus events ARE included in the tap's event mask and consumed while the
ward is active — previously they passed through. Truly OS-reserved keys (the
ones above) still cannot be intercepted by any user-space app.

## Required Permissions

| Permission | Purpose |
|---|---|
| Screen Recording | Capture and refract the live desktop |
| Accessibility | Install the input event tap |
| Input Monitoring | Detect intrusion attempts |

All three must be granted in System Settings → Privacy & Security.
After granting permissions for the first time, Wardlume must be **quit and
relaunched** for the new state to take effect.

### User-Selected File Access (added in v0.2.0)

Wardlume requests the `com.apple.security.files.user-selected.read-write` sandbox entitlement. This grants temporary access ONLY to files the user explicitly drags into the three asset slots in Preferences (Base Image, Reaction Image, Audio). It does NOT grant arbitrary filesystem access.

Dropped files are validated (extension allowlist, 10MB size cap, and — as of v1.1.0 — that the file is a genuinely decodable image / playable audio file) and copied into the app's sandboxed Application Support directory. The copy is atomic: the file is written to a temp name, validated, and only then swapped into the slot, so a failed or rejected import can never destroy the asset already there. The source files on disk are never modified. Clicking ✕ on a slot deletes the in-sandbox copy only.

## Unlock Methods

| Path | Trigger | Status in v1 |
|---|---|---|
| Cmd+Shift+U + Touch ID | Hotkey | ✅ Working |
| Touch ID via menu bar dropdown | Click "Unlock with Touch ID..." | ⚠️ Known issue (see below) |
| Deactivate Ward via menu bar dropdown | Click "Deactivate Ward" | ⚠️ Known issue (see below) |

## Known Limitations in v1

### Menu bar dropdown items do not fire while ward is active

When the ward is active and the user clicks an item in the Wardlume menu bar
dropdown ("Deactivate Ward", "Unlock with Touch ID...", "Quit"), the click
produces a brief visual highlight but the item's action never fires.

Root cause is under investigation. The CGEventTap correctly whitelists the
dropdown panel (Wardlume-owned window, not the ward overlay), so events
reach the menu — but something in the interaction between the ward window's
level (`.screenSaver`) and NSMenu's tracking runloop prevents the action
selector from being invoked.

**Workaround:** use the keyboard hotkeys (Cmd+Shift+W or Cmd+Shift+U).
Both are fully functional.

This is a v1.x fix candidate — community contributions welcome.

### Mission Control and Spaces gestures are blocked

As of this version, Wardlume temporarily disables system trackpad gestures
(Mission Control, Spaces, Launchpad, Show Desktop, App Exposé) while the ward
is active via `GestureBlocker`. The original preference values are restored
exactly on deactivation.

Crash safety: before modifying any key, GestureBlocker writes a backup plist to
`Application Support/Wardlume/gesture_backup.plist`. On next launch,
`recoverIfNeeded()` checks for this file and restores gestures immediately if
found — ensuring gestures are never permanently disabled even after a crash.

**Overlay window level:** The ward overlay now runs at `CGShieldingWindowLevel`
(same level as the macOS screensaver), which is above Spotlight, Notification
Center, and standard screen-saver-level windows. This is consistent with
best-practice implementations (e.g. Lockpaw).

### Multi-display behavior

The session-wide event tap blocks keyboard and pointer input across **all**
displays. As of v1.1.0, every non-primary display is also covered by an opaque
blackout window during ward, so no monitor is left showing the live desktop.
The animated Metal ward itself still renders only on the primary display; the
others go black. (Capture resolution is also derived from the primary display.)

### Capture-loss and activation failure are fail-closed

- If Screen Recording permission is revoked mid-session (the capture stream
  stops), the ward **deactivates and alerts** rather than freezing on a stale
  frame while input stays locked.
- If the input tap fails to install at activation (e.g. Accessibility / Input
  Monitoring was just revoked), the half-built ward is **torn down with an
  alert** instead of leaving a locked-looking but fully interactive screen.

## Whitelist Architecture

The CGEventTap whitelist allows clicks through only if they land in a
Wardlume-owned window that is NOT one of our full-screen overlays. This covers:
- The status item and its NSMenu dropdown panel
- Any NSAlert dialogs
- Any future settings/preferences windows

Implementation: iterates `CGWindowListCopyWindowInfo` in z-order, skips past our
own full-screen overlays (the ward, the reaction overlay, and the secondary-
display blackouts — all consumed, never whitelisted), and passes the event
through only if the first non-overlay window at that point is Wardlume-owned.

Importantly, this same ownership check now runs for clicks in the **menu-bar
strip** too. Previously the top strip was passed through wholesale so the status
icon stayed clickable — but that also let an intruder click the Apple menu
(Restart / Shut Down / Log Out), Control Center, or another app's status item
while warded. Now only clicks that actually land on a Wardlume window in the
strip pass through; everything else in the menu bar is consumed.

## Architecture Decisions Driven by Safety

- CGEventTap runs at `.cgSessionEventTap` location with `.headInsertEventTap`
  placement — earliest interception point that still respects OS-level
  shortcuts.
- Cmd+Shift+W and Cmd+Shift+U are both handled inside the event tap callback
  (not via NSEvent.addGlobalMonitorForEvents), because global NSEvent monitors
  are implemented as listen-only CGEventTaps and cannot observe events our
  head-insert read-write tap consumes.
- Touch ID is triggered only by explicit user intent (hotkey or menu click).
  Never on ward activation. Never on intrusion attempts. Intrusion attempts
  fire only the visual border-pulse — they cannot exhaust biometric attempts
  or spam authentication prompts.
- Permissions are checked at every ward activation, not just at launch,
  so the user is re-prompted if they revoke permissions mid-session.
- Trackpad gestures consumed via NSEvent.addLocalMonitorForEvents (the
  CGEventTap event mask does not include gesture types — they are NSEvent-only).
- The event mask covers keyboard, all pointer types, scroll, system-defined
  (media/brightness/volume) and tablet/stylus events. If macOS disables the tap
  for being slow, the triggering event is consumed (not passed through) before
  the tap is re-enabled, so no single input leaks during the gap.