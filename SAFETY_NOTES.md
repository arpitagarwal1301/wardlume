# Wardlume — Safety Notes

## Escape Hatches (every user must know these)

Three reliable ways to deactivate the ward, in priority order:

1. **Cmd+Shift+W** — Global escape hotkey.
   Handled inside the CGEventTap callback. Works regardless of biometric
   availability or window state. This is the guaranteed escape and always
   takes priority.

2. **Cmd+Shift+U** — Trigger Touch ID prompt.
   Handled inside the CGEventTap callback alongside Cmd+Shift+W. Opens the
   native macOS Touch ID sheet via LocalAuthentication. Falls back to
   password if biometric is locked out or unavailable.

3. **Cmd+Option+Esc** — Force Quit Wardlume.
   macOS-reserved shortcut that no third-party app can intercept. Use this
   if any other escape path fails. Sleep (closing the lid) is also a guaranteed
   exit — sleep tears down event taps.

## What Wardlume Cannot Intercept (by design)

- Cmd+Option+Esc (force quit)
- Power button press
- Touch ID sensor (LocalAuthentication renders above intercept points via SecurityAgent)
- Hardware media keys reserved by macOS (brightness, volume, etc.)
- Wardlume's own menu bar icon (whitelisted top of screen)

These are NOT bugs — they are guaranteed escape paths macOS protects.

## Required Permissions

| Permission | Purpose |
|---|---|
| Screen Recording | Capture and refract the live desktop |
| Accessibility | Install the input event tap |
| Input Monitoring | Detect intrusion attempts |

All three must be granted in System Settings → Privacy & Security.
After granting permissions for the first time, Wardlume must be **quit and
relaunched** for the new state to take effect.

## Unlock Methods

| Path | Trigger | Status in v1 |
|---|---|---|
| Cmd+Shift+W | Hotkey | ✅ Working |
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

### Mission Control and Spaces gestures cannot be blocked

macOS handles three-finger Mission Control swipes, four-finger Spaces
swipes, and other system-level trackpad gestures at the WindowServer
level, above any third-party intercept point. No user-space app can
fully block these without private APIs.

For maximum lockdown, manually disable trackpad gestures in
**System Settings → Trackpad → More Gestures** before activating the ward.

App-level gestures (pinch, rotate, swipe within an app) ARE blocked via
NSEvent local monitor while the ward is active.

## Whitelist Architecture

The CGEventTap whitelist allows clicks through if they land in a
Wardlume-owned window that is NOT the ward overlay. This covers:
- The NSMenu dropdown panel
- Any NSAlert dialogs
- Any future settings/preferences windows

Implementation: iterates `CGWindowListCopyWindowInfo` in z-order, skips past
the ward overlay (which sits on top), and whitelists the first subsequent
window with matching PID and a different window ID.

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