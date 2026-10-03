# Wardlume Privacy

**Short version: everything stays on your Mac. Wardlume has no servers, no analytics, and no accounts.**

Wardlume is a local macOS menu-bar app. It does not collect, store, or transmit any personal data. There is no backend to send data to.

## What Wardlume accesses, and why

| Capability | Why it's used | Where the data goes |
|---|---|---|
| **Screen Recording** | Renders the live desktop as a refracted glass shield while the ward is active (via ScreenCaptureKit). At launch it also takes one 2×2-pixel throwaway capture, so macOS asks for consent before the ward is ever up. | On-screen only. Frames go straight to the GPU, are drawn to the overlay in real time, and are never saved, recorded, or transmitted. The app has no internet access (see [Network](#network)). |
| **Camera** (optional, **off by default**) | **Intruder photo:** if you turn it on, Wardlume takes one photo with your Mac's camera when an unlock attempt fails while the ward is up (wrong Touch ID until macOS gives up, wrong password, or Touch ID lockout). Never when someone just cancels, never at any other time. macOS always lights the camera indicator while it runs. | Stays on your Mac, inside Wardlume's sandboxed container (not your Pictures folder). Viewable only in Settings after you unlock, deleted automatically after 7, 30 or 90 days (your choice), or when you tap **Delete all**. Never uploaded: the app has no internet access. |
| **Accessibility** | Installs the input event tap that locks the keyboard, mouse, and trackpad while the ward is active. | Stays on-device. Input events are blocked, not logged or sent anywhere. |
| **Input Monitoring** | Detects intrusion attempts so the ward can show a reaction. | Stays on-device. Used only to trigger the on-screen reaction. |
| **Idle time** (no permission required) | When *Auto-ward when idle* is on, reads how long it has been since the last keyboard or mouse input (a single number of seconds) and whether another app is keeping the display awake. | Stays on-device. Used only to decide when to show the auto-ward countdown; never logged or sent anywhere. |
| **Keep awake** (no permission required) | Holds a power assertion so the display and system don't idle-sleep while the ward is active. Toggle in Settings → Automation. | Nothing is collected. The assertion is a local request to macOS, released when the ward ends. |

## Intruder photos

Off unless you turn it on, in **Settings → Intruder photo**, the menu bar, **Overview → Permissions**, or by allowing the optional Camera row in the setup wizard.
- macOS asks for camera access only then.
- **Limits:** at most one photo every 10 seconds, and 10 per lock.
- **Notice:** the ward shows "Failed unlocks are photographed" by default. Some places expect people to be told before they're photographed, so leave the notice on unless you're sure.
- **Storage:** photos are plain JPEG files in Wardlume's container (`~/Library/Containers/com.agarwal.wardlume.Wardlume/Data/Library/Application Support/Wardlume/IntruderPhotos`), which macOS protects from other apps.
- **Your copies:** **Export…** copies them to a folder you pick.

## Your custom assets

When you add a cover image, reaction image, or sound in Preferences, Wardlume copies that file into its **sandboxed Application Support** directory. The original files you drop are never modified, and your assets are never uploaded anywhere. Removing an asset deletes only Wardlume's in-sandbox copy.

## Settings

Your preferences (active pack, hotkeys, cooldown, etc.) are stored locally in macOS `UserDefaults`, inside Wardlume's sandbox container. They never leave your Mac.

## Network

**The Wardlume app can't reach the internet. macOS enforces this, not just a promise.** Wardlume runs in Apple's App Sandbox *without* a network entitlement, so macOS refuses any connection it tries to make. That's the same app that holds Screen Recording, so your screen has no way out.

**Updates are the one exception, and they're handled by a separate process.** Starting with v1.7.4, Wardlume updates itself with [Sparkle](https://sparkle-project.org), the open-source updater most Mac apps use:
- Sparkle's **downloader** runs in its *own* sandbox, with network access and nothing else. It only fetches the update feed (`wardlume.github.io/appcast.xml`) and, once you choose to install, the signed update from Wardlume's public GitHub releases.
- **Nothing about you or your Mac is sent.** It's a plain download of a public file.
- **Every update is signed** with the developer's key and verified before it's installed.
- **Nothing happens until you agree.** Wardlume asks once whether to check for updates automatically, and you can change that any time in **Settings → Advanced → Updates**.

Otherwise, your browser opens only when *you* click a link (Privacy, Terms, or Support).

## Verify it yourself

You don't have to take our word for it. In Terminal, run:

```bash
codesign -d --entitlements - /Applications/Wardlume.app
```

You'll see `com.apple.security.app-sandbox`, `com.apple.security.screen-recording`, and `com.apple.security.device.camera` (present so Intruder photo *can* be turned on; macOS still asks you first), and **no** `com.apple.security.network.client` or `network.server`. Without those, macOS blocks every connection the app attempts. Settings → Overview → **Privacy & trust** reads the same entitlements live and shows the result.

To check the updater too:

```bash
codesign -d --entitlements - /Applications/Wardlume.app/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc
```

It shows only `app-sandbox` and `network.client`.

A network monitor such as **[LuLu](https://objective-see.org/products/lulu.html)** (free, open source) or **Little Snitch** will confirm this in practice:
- Wardlume itself never connects.
- Sparkle's downloader appears only when it checks for or downloads an update.
- Little Snitch also shows Wardlume's built-in network policy, which explains each of those connections.

## Contact

Questions? Open an issue at <https://github.com/arpitagarwal1301/wardlume/issues>.
