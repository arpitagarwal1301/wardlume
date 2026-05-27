import Cocoa
import SwiftUI
import MetalKit
import CoreGraphics
import ScreenCaptureKit

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSMenuDelegate {
    var statusBarItem: NSStatusItem?
    var overlayWindow: NSWindow?
    var toggleMenuItem: NSMenuItem?
    var unlockMenuItem: NSMenuItem?

    /// Owns the SCStream lifecycle. Created when the ward activates, torn down
    /// when it deactivates. Nil when the ward is off.
    var captureManager: DesktopCaptureManager?

    /// Phase 2a: owns the CGEventTap lifecycle. Created once at launch and held
    /// for the app's lifetime. install() is called when the ward activates;
    /// uninstall() is called when it deactivates. The object itself persists
    /// so reactionWindowID tracking works even when ward is inactive (for
    /// triggerForPreview() in settings UI).
    var inputLockManager: InputLockManager?

    /// Phase 2.5a: owns the reaction overlay lifecycle. Created once at launch
    /// and held for the app's lifetime so its cooldown clock survives
    /// activate/deactivate cycles (never reset to nil on ward toggle).
    var reactionManager: ReactionManager?

    /// Phase 2.5c: owns the preferences window lifecycle. Created on first
    /// openPreferences() call and reused for subsequent opens.
    var preferencesWindow: NSWindow?

    /// Phase 4b: base image overlay rendered above the Metal shader when the
    /// active pack (or user override) provides a base image. nil when no base
    /// image is present — the Metal shader renders directly.
    private var baseImageView: NSImageView?

    // -------------------------------------------------------------------------
    // MARK: — Application launch
    // -------------------------------------------------------------------------

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("WARDLUME: applicationDidFinishLaunching called!")

        // --- Screen Recording permission gate --------------------------------
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()

            let alert = NSAlert()
            alert.messageText     = "Screen Recording Access Required"
            alert.informativeText = """
                Wardlume renders live desktop refraction and needs Screen \
                Recording permission.

                If a system dialog appeared, click Allow. Otherwise:
                System Settings → Privacy & Security → Screen Recording → \
                enable Wardlume.

                Relaunch Wardlume after granting access.
                """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Quit")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let url = URL(string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
                NSWorkspace.shared.open(url)
            }
            NSApp.terminate(nil)
            return
        }

        // --- Status bar ------------------------------------------------------
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusBarItem?.button {
            button.image = NSImage(systemSymbolName: "lock.shield",
                                   accessibilityDescription: "Wardlume")
        }

        let menu = NSMenu()
        menu.delegate = self

        toggleMenuItem = NSMenuItem(title: "Activate Ward",
                                    action: #selector(toggleWard),
                                    keyEquivalent: "")
        toggleMenuItem?.target = self
        menu.addItem(toggleMenuItem!)

        menu.addItem(NSMenuItem.separator())

        let preferencesItem = NSMenuItem(title: "Preferences...",
                                         action: #selector(openPreferences),
                                         keyEquivalent: ",")
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        menu.addItem(NSMenuItem.separator())

        unlockMenuItem = NSMenuItem(title: "Unlock with Touch ID...",
                                    action: #selector(unlockWithBiometrics),
                                    keyEquivalent: "")
        unlockMenuItem?.target = self
        unlockMenuItem?.isEnabled = false  // Disabled until ward is active
        menu.addItem(unlockMenuItem!)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit",
                                  action: #selector(quitApp),
                                  keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        // ── DEBUG-only: "Test Lock (10s)" ─────────────────────────────────────
        // Installs the CGEventTap for 10 seconds WITHOUT creating the shader
        // overlay window, so you can safely verify:
        //   • Cmd+Shift+W fires and uninstalls the tap immediately (scenario 2)
        //   • The status-bar menu stays fully accessible (scenarios 3 & 4)
        // Uses a dummy NSWindow as wardWindow (no CGWindowID collision with any
        // real window since it is never made visible).
#if DEBUG
        menu.addItem(NSMenuItem.separator())
        let testItem = NSMenuItem(title: "Test Lock (10s)",
                                  action: #selector(testLock),
                                  keyEquivalent: "")
        testItem.target = self
        menu.addItem(testItem)
#endif

#if DEBUG
        // ── Pack selector (Phase 2.5b — removed in Phase 2.5c) ────────────────
        // These DEBUG menu items are replaced by the Preferences window.
        // Wrapped in #if DEBUG to delete in release builds.
        menu.addItem(NSMenuItem.separator())

        let grumpyItem = NSMenuItem(title: "Set Pack: Grumpy Old Man",
                                    action: #selector(debugSetPackGrumpy),
                                    keyEquivalent: "")
        grumpyItem.target = self
        menu.addItem(grumpyItem)

        let wizardItem = NSMenuItem(title: "Set Pack: Wizard",
                                    action: #selector(debugSetPackWizard),
                                    keyEquivalent: "")
        wizardItem.target = self
        menu.addItem(wizardItem)

        let silentItem = NSMenuItem(title: "Set Pack: Silent Professional",
                                    action: #selector(debugSetPackSilent),
                                    keyEquivalent: "")
        silentItem.target = self
        menu.addItem(silentItem)
#endif

        statusBarItem?.menu = menu

        // Phase 4a: initialize user asset slots from disk.
        // Accessing .shared triggers init() which calls scan().
        _ = UserAssetManager.shared

        // Phase 2a: instantiate the input lock manager at launch.
        // Held for the app lifetime; install() is called when ward activates.
        inputLockManager = InputLockManager()

        // Phase 2.5a: instantiate the reaction engine at launch.
        // Held for the app lifetime; see property declaration above.
        reactionManager = ReactionManager()

        // Wire up the reaction manager to the input lock manager so reaction
        // window IDs can be tracked (prevents reaction overlay from being
        // whitelisted and leaking input to background apps).
        reactionManager?.inputLockManager = inputLockManager
    }

    // -------------------------------------------------------------------------
    // MARK: — Ward toggle
    // -------------------------------------------------------------------------

    @objc func toggleWard() {
        if let window = overlayWindow {
            // --- Deactivate: stop input lock → stop capture → close window ---
            inputLockManager?.uninstall()

            // Dismiss any live reaction overlay immediately. Must happen before
            // window.close() so no stale overlay outlives the ward session.
            reactionManager?.dismissReaction()

            // Phase 4b: remove base image view and resume Metal rendering
            baseImageView?.removeFromSuperview()
            baseImageView = nil
            if let metalView = window.contentView as? MetalOverlayView {
                metalView.isPaused = false  // ready for next activation
            }

            captureManager?.stopCapture()
            captureManager = nil

            window.close()
            overlayWindow         = nil
            toggleMenuItem?.title = "Activate Ward"
            unlockMenuItem?.isEnabled = false

        } else {
            // --- Phase 2a: check Accessibility + Input Monitoring before locking.
            if !InputLockManager.permissionsReady() {
                InputLockManager.requestPermissions()

                let alert = NSAlert()
                alert.messageText     = "Accessibility & Input Monitoring Required"
                alert.informativeText = """
                    Wardlume needs Accessibility and Input Monitoring \
                    permission to lock keyboard and mouse while the ward \
                    is active.

                    If a system dialog appeared, click Allow. Otherwise \
                    open System Settings:
                    • Privacy & Security → Accessibility → enable Wardlume
                    • Privacy & Security → Input Monitoring → enable Wardlume

                    Relaunch Wardlume after granting both permissions.
                    """
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Open Privacy Settings")
                alert.addButton(withTitle: "Cancel")

                if alert.runModal() == .alertFirstButtonReturn {
                    let url = URL(string:
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                    NSWorkspace.shared.open(url)
                }
                return
            }

            // --- Activate: create window, start capture, install input lock --
            let screenFrame = NSScreen.main?.frame ?? .zero

            let window = NSWindow(
                contentRect: screenFrame,
                styleMask:   [.borderless],
                backing:     .buffered,
                defer:       false)

            window.isReleasedWhenClosed = false
            window.level                = .screenSaver
            window.isOpaque             = true
            window.backgroundColor      = .black
            window.hasShadow            = false

            let metalView = MetalOverlayView(frame: screenFrame)
            window.contentView = metalView

            window.ignoresMouseEvents = true
            window.makeKeyAndOrderFront(nil)

            overlayWindow         = window
            toggleMenuItem?.title = "Deactivate Ward"
            unlockMenuItem?.isEnabled = true

            // Phase 4b: layer base image above the Metal shader if one is resolved.
            let activePack = reactionManager?.activePack ?? .silentProfessional
            if let baseURL = ReactionPack.resolvedBaseImageURL(for: activePack),
               let image = NSImage(contentsOf: baseURL) {
                let imageView = NSImageView(frame: metalView.bounds)
                imageView.imageScaling = .scaleAxesIndependently
                imageView.image = image
                imageView.autoresizingMask = [.width, .height]
                metalView.addSubview(imageView)
                baseImageView = imageView
                // Pause Metal rendering while occluded by opaque base image
                metalView.isPaused = true
                print("Wardlume [AppDelegate]: base image rendered, Metal paused")
            } else {
                baseImageView = nil
                metalView.isPaused = false
                print("Wardlume [AppDelegate]: no base image, Metal shader active")
            }

            // Start desktop capture.
            guard let device = metalView.device else { return }
            let capture = DesktopCaptureManager(device: device, view: metalView)
            captureManager = capture
            capture.startCapture(excludingWindow: window)

            // Install the CGEventTap.
            // wardWindow is passed explicitly so the callback can exclude the
            // overlay surface from the Wardlume-window whitelist — events that
            // land on the ward overlay itself must still be consumed.
            guard let lock = inputLockManager else { return }
            lock.install(view: metalView, wardWindow: window)

            // Escape hatch: Cmd+Shift+W deactivates the ward from anywhere.
            // The callback fires inside handleEvent() — before any consume
            // decision — so it works even though the tap blocks all other keys.
            lock.onEscapeHotkey = { [weak self] in self?.toggleWard() }

            // Touch ID unlock: Cmd+Shift+U triggers biometric authentication.
            // Handled inside the CGEventTap callback (not via NSEvent.addGlobalMonitorForEvents)
            // because global NSEvent monitors are listen-only taps that never see events
            // our head-insert read-write tap consumes. See InputLockManager.swift lines 84-90.
            lock.onUnlockHotkey = { [weak self] in self?.unlockWithBiometrics() }

            // Phase 2.5a: wire intrusion events to the reaction engine.
            // ReactionManager.trigger() enforces its own cooldown — this fires
            // on every consumed event regardless of the border-pulse debounce.
            lock.onIntrusion = { [weak self] in self?.reactionManager?.trigger() }
        }
    }

    // -------------------------------------------------------------------------
    // MARK: — Touch ID Unlock
    // -------------------------------------------------------------------------

    @objc func unlockWithBiometrics() {
        BiometricUnlockManager.shared.evaluateUnlock(
            reason: "Authenticate to deactivate the Wardlume ward."
        ) { [weak self] success, _ in
            guard let self, success, self.overlayWindow != nil else { return }
            self.toggleWard()
        }
    }

    // -------------------------------------------------------------------------
    // MARK: — Preferences Window
    // -------------------------------------------------------------------------

    @objc func openPreferences() {
        if let window = preferencesWindow {
            // Window exists: bring to front
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            // Create new window
            guard let reactionManager = reactionManager else { return }
            let contentView = PreferencesView(reactionManager: reactionManager)
            let hostingController = NSHostingController(rootView: contentView)
            
            // Let the hosting controller communicate SwiftUI's intrinsic size to the window
            hostingController.sizingOptions = [.intrinsicContentSize]
            
            // Use contentViewController initializer so window sizes itself to content
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Wardlume Preferences"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            
            // Set initial content size hint (larger than minimum for breathing room)
            window.setContentSize(NSSize(width: 520, height: 450))
            
            // Minimum window frame size (includes ~28pt title bar, ensures 480×400 content area)
            window.minSize = NSSize(width: 480, height: 428)
            
            window.center()
            window.isReleasedWhenClosed = false
            window.delegate = self
            
            preferencesWindow = window
            window.makeKeyAndOrderFront(nil)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: — Menu Item Validation
    // -------------------------------------------------------------------------

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        // Explicitly validate all menu items we handle.
        // Without this, AppKit's default validation can disable items unexpectedly.
        switch menuItem.action {
        case #selector(toggleWard),
             #selector(unlockWithBiometrics),
             #selector(openPreferences),
             #selector(quitApp):
            return true
        #if DEBUG
        case #selector(testLock),
             #selector(debugSetPackGrumpy),
             #selector(debugSetPackWizard),
             #selector(debugSetPackSilent):
            return true
        #endif
        default:
            return false
        }
    }

    // -------------------------------------------------------------------------
    // MARK: — Menu Delegate
    // -------------------------------------------------------------------------

    func menuWillOpen(_ menu: NSMenu) {
        // Temporarily lower the ward so the dropdown can receive input.
        // The ward is normally at .screenSaver (1000) to block all desktop
        // interaction. When our menu opens, lower it to .popUpMenu (101) so
        // the menu panel (which is also at ~101) can receive mouse events.
        // Without this, the system's hit-testing routes clicks to the ward
        // window (highest level) instead of the menu, even though the menu
        // renders visually on top.
        overlayWindow?.level = .popUpMenu
    }

    func menuDidClose(_ menu: NSMenu) {
        // Restore the security level. Handle the case where the ward was
        // deactivated via Cmd+Shift+W while the menu was open (overlayWindow
        // would be nil) — in that case, there's nothing to restore.
        overlayWindow?.level = .screenSaver
    }

    // -------------------------------------------------------------------------
    // MARK: — Quit
    // -------------------------------------------------------------------------

    @objc func quitApp() {
        inputLockManager?.uninstall()
        reactionManager?.dismissReaction()  // clear any live overlay before exit
        captureManager?.stopCapture()
        NSApp.terminate(nil)
    }

    // -------------------------------------------------------------------------
    // MARK: — DEBUG: Test Lock (10s)
    // -------------------------------------------------------------------------

#if DEBUG
    /// Installs the CGEventTap for 10 seconds without creating the shader overlay
    /// window. Use this to verify:
    ///   1. Cmd+Shift+W fires immediately (escape hotkey works).
    ///   2. The status-bar menu and its items remain clickable (whitelist works).
    ///   3. Typing in other apps is blocked for the duration.
    @objc func testLock() {
        guard overlayWindow == nil,
              InputLockManager.permissionsReady(),
              let lock = inputLockManager else { return }

        // Use a dummy (never-shown) NSWindow as the wardWindow so its windowNumber
        // is a valid but harmless CGWindowID for the whitelist exclusion check.
        let dummy = NSWindow()
        lock.install(view: MetalOverlayView(frame: .zero), wardWindow: dummy)

        lock.onEscapeHotkey = { [weak self] in
            self?.inputLockManager?.uninstall()
            print("Wardlume [DEBUG]: Cmd+Shift+W fired — test tap uninstalled.")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, self.overlayWindow == nil else { return }
            self.inputLockManager?.uninstall()
            print("Wardlume [DEBUG]: 10 s elapsed — test tap uninstalled.")
        }

        print("Wardlume [DEBUG]: test tap active for 10 s. " +
              "Try Cmd+Shift+W, the status-bar menu, and typing in other apps.")
    }

    // ── Pack selector helpers ─────────────────────────────────────────────────
    // Temporary until Phase 2.5c adds the settings UI picker.
    // Each method sets activePackID; the next trigger() picks up the change.

    @objc func debugSetPackGrumpy() {
        reactionManager?.activePackID = ReactionPack.grumpyOldMan.id
        print("Wardlume [DEBUG]: active pack → grumpyOldMan")
    }

    @objc func debugSetPackWizard() {
        reactionManager?.activePackID = ReactionPack.wizard.id
        print("Wardlume [DEBUG]: active pack → wizard")
    }

    @objc func debugSetPackSilent() {
        reactionManager?.activePackID = ReactionPack.silentProfessional.id
        print("Wardlume [DEBUG]: active pack → silentProfessional")
    }
#endif
}

// -------------------------------------------------------------------------
// MARK: — NSWindowDelegate
// -------------------------------------------------------------------------

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === preferencesWindow {
            preferencesWindow = nil
        }
    }
}
