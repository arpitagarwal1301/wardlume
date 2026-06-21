# Wardlume Privacy

**Short version: everything stays on your Mac. Wardlume has no servers, no analytics, and no accounts.**

Wardlume is a local macOS menu-bar app. It does not collect, store, or transmit any personal data. There is no backend to send data to.

## What Wardlume accesses, and why

| Capability | Why it's used | Where the data goes |
|---|---|---|
| **Screen Recording** | Renders the live desktop as a refracted glass shield while the ward is active (via ScreenCaptureKit). | On-screen only. Frames are drawn to the overlay in real time and never saved, recorded, or transmitted. |
| **Accessibility** | Installs the input event tap that locks the keyboard, mouse, and trackpad while the ward is active. | Stays on-device. Input events are blocked, not logged or sent anywhere. |
| **Input Monitoring** | Detects intrusion attempts so the ward can show a reaction. | Stays on-device. Used only to trigger the on-screen reaction. |

## Your custom assets

When you add a cover image, reaction image, or sound in Preferences, Wardlume copies that file into its **sandboxed Application Support** directory. The original files you drop are never modified, and your assets are never uploaded anywhere. Removing an asset deletes only Wardlume's in-sandbox copy.

## Settings

Your preferences (active pack, hotkeys, cooldown, etc.) are stored locally in macOS `UserDefaults`, inside Wardlume's sandbox container. They never leave your Mac.

## Network

Wardlume makes **no network requests** during normal operation. The only time your browser opens is when *you* click a link (Check updates, Privacy, Terms, or Support), which opens the corresponding public web page.

## Contact

Questions? Open an issue at <https://github.com/arpitagarwal1301/wardlume>.
