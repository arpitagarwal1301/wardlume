# Wardlume Safety Guide

Wardlume locks your Mac's input at a low level, so it's worth knowing how to get out and what it does (and doesn't) protect against.

## Ways out, always

| Way out | How |
|---|---|
| **Apple Watch** | Tap any key or the trackpad → double-press your watch's side button *(when watch unlock is set up)* |
| **Touch ID** | Press your unlock shortcut (**⌘⇧U** by default) → finger on the sensor |
| **Password** | Press your unlock shortcut → *Use Password…* |
| **Force Quit** | **⌘⌥Esc** → select Wardlume → Force Quit. macOS reserves this shortcut, so no app can block it. Quitting Wardlume ends the ward. |
| **Sleep** | Closing the lid (or any system sleep) ends the ward. Wardlume never lets a lock survive sleep. |
| **Emergency exit** *(optional)* | Enable it in **Settings → Shortcuts**. Your chosen shortcut drops the ward **with no authentication**, so anyone at the keyboard can use it. Leave it off unless you want a guaranteed escape. |

Touch ID always works, even if you mis-configure a custom shortcut.

## What the ward blocks

- **Keyboard, mouse, trackpad, scrolling, and stylus input** on **every** monitor, whichever app has focus. Only your unlock shortcut (and the emergency exit, if enabled) is recognized.
- **Trackpad gestures:** Mission Control, Spaces, Launchpad, and similar swipes.
- **Media and brightness keys.**
- **The menu bar:** the Apple menu (Restart, Shut Down, Log Out), Control Center, and other apps' menu-bar icons.
- **Wardlume's own Settings:** hidden while warded and not clickable through the glass.

## What it can't block (by design)

These are protected by macOS itself and are deliberately left as ways out:

- **⌘⌥Esc** (Force Quit)
- **The power button**
- **The Touch ID sensor** (it's how you unlock)

## Good to know

- **Your screen stays visible.** That's the point, so anyone can watch your agent work. Choose **Settings → Behavior → Other monitors → Black out** if you'd rather other monitors go dark.
- **Unplugging a monitor never unlocks.** The ward moves to a remaining display, usually your laptop screen, and input stays locked.
- **Your Mac stays awake while warded** (Settings → Behavior), so the display's sleep timer doesn't end the ward. Closing the lid still does.
- **Auto-ward always shows a 10-second countdown first.** Moving the mouse or pressing a key cancels it. It never triggers while a video or presentation keeps the screen awake, or when the screen is locked.
- **Apple Watch requests are rate-limited**, and a touch only ever asks your **watch**, never Touch ID or the password, so a stranger can't use up your Touch ID attempts. If you're nearby when someone touches your Mac, your watch buzzes; only your wrist can approve.
- **Wardlume never unlocks just because your watch or phone is nearby.** You always approve deliberately.

## Known limitations

- While warded, clicking items in Wardlume's **menu-bar dropdown** doesn't run them. Use your unlock shortcut or Apple Watch instead.
- Only the **current macOS Space** is shown behind the glass. Other Spaces can't be displayed by any app.
