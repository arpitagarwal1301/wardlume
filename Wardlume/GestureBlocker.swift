//  GestureBlocker.swift
//  Wardlume
//
//  Temporarily disables macOS system trackpad gestures (Mission Control,
//  Spaces, Launchpad, Show Desktop, App Exposé) while the ward is active
//  by writing to the user's trackpad and Dock preference domains.
//
//  Lifecycle:
//    activate()          — call after CGEventTap is successfully installed.
//    deactivate()        — call at the top of deactivateWard().
//    recoverIfNeeded()   — call early in applicationDidFinishLaunching to
//                          self-heal after a crash that left gestures disabled.
//
//  Crash safety:
//    Before modifying any preference key, activate() writes a backup plist to
//    Application Support/Wardlume/gesture_backup.plist. deactivate() restores
//    from that backup then deletes it. recoverIfNeeded() does the same on
//    launch if the file still exists (crash during a ward session).

import Foundation
import CoreFoundation

final class GestureBlocker {

    // MARK: — Singleton

    static let shared = GestureBlocker()
    private init() {}

    // MARK: — Preference domains and keys

    /// Keys shared by the built-in and Bluetooth trackpad domains.
    private let trackpadKeys: [String] = [
        "TrackpadFourFingerHorizSwipeGesture",   // Spaces 4-finger swipe
        "TrackpadFourFingerVertSwipeGesture",    // Mission Control / App Exposé 4-finger
        "TrackpadThreeFingerVertSwipeGesture",   // Mission Control 3-finger
        "TrackpadThreeFingerHorizSwipeGesture",  // App Exposé 3-finger
        "TrackpadFiveFingerPinchGesture",        // Launchpad
        "TrackpadFourFingerPinchGesture",        // Launchpad (4-finger variant)
    ]

    private let trackpadDomains: [String] = [
        "com.apple.AppleMultitouchTrackpad",
        "com.apple.driver.AppleBluetoothMultitouch.trackpad",
    ]

    /// Keys in the Dock domain that enable/disable gesture recognition.
    private let dockBoolKeys: [String] = [
        "showMissionControlGestureEnabled",
        "showDesktopGestureEnabled",
        "showLaunchpadGestureEnabled",
    ]

    private let dockDomain = "com.apple.dock"

    // MARK: — Backup file path

    private var backupURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Wardlume", isDirectory: true)
        return dir.appendingPathComponent("gesture_backup.plist")
    }

    // MARK: — State

    private var isActive = false

    // MARK: — Public API

    /// Reads current gesture preferences, backs them up, then disables all system
    /// gestures. Call after the CGEventTap is confirmed installed.
    func activate() {
        guard !isActive else { return }

        let backup = readCurrentValues()
        guard writeBackup(backup) else {
            // If we can't write the backup safely we refuse to mutate preferences —
            // better to leave gestures enabled than risk orphaning them on a crash.
            print("Wardlume [GestureBlocker]: could not write backup — gestures NOT disabled.")
            return
        }

        disableGestures()
        isActive = true
        print("Wardlume [GestureBlocker]: system gestures disabled.")
    }

    /// Restores gesture preferences to the values saved at activate() time.
    /// Safe to call even when not active (idempotent).
    func deactivate() {
        guard isActive else { return }
        restoreFromBackup()
        isActive = false
    }

    /// Called at app launch. If a backup plist exists from a previous session
    /// (meaning the app crashed while the ward was active), restore preferences
    /// and delete the file so the user's gestures are re-enabled immediately.
    func recoverIfNeeded() {
        guard FileManager.default.fileExists(atPath: backupURL.path) else { return }
        print("Wardlume [GestureBlocker]: stale backup found — recovering gesture settings from crash.")
        restoreFromBackup()
        // Mark as inactive so a subsequent activate() works correctly.
        isActive = false
    }

    // MARK: — Private helpers

    /// Returns a flat dictionary of all gesture preference key→value pairs as
    /// they exist right now in the user's preferences.
    private func readCurrentValues() -> [String: Any] {
        var backup: [String: Any] = [:]

        for domain in trackpadDomains {
            CFPreferencesSynchronize(
                domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            for key in trackpadKeys {
                if let value = CFPreferencesCopyAppValue(key as CFString, domain as CFString) {
                    backup["\(domain)|\(key)"] = value
                }
            }
        }

        CFPreferencesSynchronize(
            dockDomain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        for key in dockBoolKeys {
            if let value = CFPreferencesCopyAppValue(key as CFString, dockDomain as CFString) {
                backup["\(dockDomain)|\(key)"] = value
            }
        }

        return backup
    }

    /// Writes the backup dictionary to the plist file. Returns false on any error.
    @discardableResult
    private func writeBackup(_ dict: [String: Any]) -> Bool {
        do {
            let dir = backupURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(
                fromPropertyList: dict, format: .binary, options: 0)
            // Atomic write via temp file.
            let tmp = backupURL.appendingPathExtension("tmp")
            try data.write(to: tmp, options: .atomic)
            _ = try? FileManager.default.replaceItemAt(backupURL, withItemAt: tmp)
            return true
        } catch {
            print("Wardlume [GestureBlocker]: backup write failed — \(error)")
            return false
        }
    }

    /// Writes 0 (integer) to all trackpad gesture keys and false (bool) to all
    /// Dock gesture keys, then synchronizes both domains.
    private func disableGestures() {
        let zero = 0 as CFNumber
        for domain in trackpadDomains {
            for key in trackpadKeys {
                CFPreferencesSetAppValue(key as CFString, zero, domain as CFString)
            }
            CFPreferencesSynchronize(
                domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        }

        let falseVal = false as CFBoolean
        for key in dockBoolKeys {
            CFPreferencesSetAppValue(key as CFString, falseVal, dockDomain as CFString)
        }
        CFPreferencesSynchronize(
            dockDomain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    /// Reads the backup plist and restores every saved key to its original value,
    /// then deletes the backup file.
    private func restoreFromBackup() {
        guard let data = try? Data(contentsOf: backupURL),
              let dict = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil) as? [String: Any] else {
            print("Wardlume [GestureBlocker]: backup missing or unreadable — cannot restore.")
            try? FileManager.default.removeItem(at: backupURL)
            return
        }

        for (compositeKey, value) in dict {
            // compositeKey format: "domain|key"
            let parts = compositeKey.split(separator: "|", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let domain = String(parts[0])
            let key    = String(parts[1])
            CFPreferencesSetAppValue(key as CFString, value as CFTypeRef, domain as CFString)
        }

        // Synchronize all touched domains.
        for domain in trackpadDomains {
            CFPreferencesSynchronize(
                domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        }
        CFPreferencesSynchronize(
            dockDomain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)

        try? FileManager.default.removeItem(at: backupURL)
        print("Wardlume [GestureBlocker]: gesture settings restored.")
    }
}
