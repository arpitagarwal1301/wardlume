import Cocoa
import SwiftUI
import MetalKit
import CoreGraphics
import ScreenCaptureKit
import Carbon.HIToolbox
import Darwin   // dlopen/dlsym for the macOS lock-screen fallback

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

    /// Phase 5a-p2: pill indicator NSView (dark backdrop + eye.fill icon), present
    /// only while the ward is active with a pack that has hasCornerIndicator = true
    /// and no base image is present. Nilled on deactivation. Lifecycle mirrors
    /// baseImageView.
    private var indicatorView: NSView?

    /// Unlock hint label shown during ward — fades in a few seconds after activation
    /// so users can always discover how to unlock. Shown for all packs.
    /// Torn down with the ward, mirroring indicatorView lifecycle.
    private var unlockHintView: NSView?

    /// Global ward activation hotkey (⌘⇧L). Registered once at launch via Carbon
    /// RegisterEventHotKey so the combo is consumed system-wide — it works while
    /// Wardlume is in the background and doesn’t leak to the foreground app.
    /// Held for the app’s lifetime; deinit unregisters automatically.
    private var activationHotkey: GlobalHotkey?

    /// Blackout overlay windows covering every NON-primary display while the ward
    /// is active. The Metal ward covers the primary display; these opaque-black
    /// windows cover the rest so secondary screens aren't left showing the live,
    /// un-warded desktop. Created on activate, closed on deactivate. Their window
    /// IDs are registered with InputLockManager so clicks on them are consumed
    /// (not whitelisted) — otherwise input would leak through to apps behind them.
    private var secondaryOverlayWindows: [NSWindow] = []

    /// Watchdog that keeps the ward window on top after activation. Detects if
    /// the ward window is displaced / minimized and re-raises it. After
    /// `maxWatchdogReraises` consecutive failed re-raises it escalates to the
    /// real macOS lock screen. nil while the ward is inactive.
    private var wardWatchdog: Timer?

    /// Count of consecutive watchdog ticks where the ward was found displaced and
    /// a re-raise was attempted. Reset to 0 as soon as the ward is verified back
    /// on top. Escalates to the system lock screen when it reaches the cap.
    private var watchdogReraiseCount = 0
    private let maxWatchdogReraises = 3

    /// True while a status-bar menu is open. menuWillOpen lowers the ward level to
    /// .popUpMenu so the dropdown is clickable; the watchdog must not fight that by
    /// re-raising / re-leveling the window during that window.
    private var menuIsOpen = false

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
                                    keyEquivalent: "l")
        toggleMenuItem?.keyEquivalentModifierMask = [.command, .shift]
        toggleMenuItem?.target = self
        menu.addItem(toggleMenuItem!)

        menu.addItem(NSMenuItem.separator())

        let preferencesItem = NSMenuItem(title: "Preferences...",
                                         action: #selector(openPreferences),
                                         keyEquivalent: ",")
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        unlockMenuItem = NSMenuItem(title: "Unlock with Touch ID (⌘⇧U)...",
                                    action: #selector(unlockWithBiometrics),
                                    keyEquivalent: "")
        unlockMenuItem?.target = self
        unlockMenuItem?.isEnabled = false  // Disabled until ward is active
        menu.addItem(unlockMenuItem!)

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

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit",
                                  action: #selector(quitApp),
                                  keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusBarItem?.menu = menu

        // Global activation hotkey: ⌘⇧L toggles the ward from anywhere, even when
        // Wardlume is not frontmost (e.g. while focused in an IDE). Uses Carbon so
        // the combo is consumed and doesn’t leak to the foreground app.
        // kVK_ANSI_L = 0x25. cmdKey | shiftKey from Carbon.HIToolbox.
        activationHotkey = GlobalHotkey(
            keyCode: UInt32(kVK_ANSI_L),
            modifiers: UInt32(cmdKey | shiftKey)
        ) { [weak self] in
            self?.toggleWard()
        }
        if activationHotkey == nil {
            print("Wardlume [App]: failed to register global activation hotkey ⌘⇧L")
        }

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

        // Crash recovery: if a previous ward session crashed while gestures were
        // disabled, GestureBlocker restores them here before anything else runs.
        GestureBlocker.shared.recoverIfNeeded()

        // macOS tears down CGEventTaps when the system sleeps. If we slept while
        // warded, on wake the overlay window could still be on screen while the
        // tap is dead — a screen that LOOKS locked but accepts all input. Tear
        // the ward down on sleep/screen-lock so it can never wake into that state.
        let wsCenter = NSWorkspace.shared.notificationCenter
        wsCenter.addObserver(self, selector: #selector(systemWillSleep),
                             name: NSWorkspace.willSleepNotification, object: nil)
        wsCenter.addObserver(self, selector: #selector(systemWillSleep),
                             name: NSWorkspace.screensDidSleepNotification, object: nil)
        // Belt-and-suspenders: if we ever wake still holding an overlay whose tap
        // is gone, tear down rather than present a fake lock.
        wsCenter.addObserver(self, selector: #selector(systemDidWake),
                             name: NSWorkspace.didWakeNotification, object: nil)
    }

    // -------------------------------------------------------------------------
    // MARK: — Sleep / wake teardown
    // -------------------------------------------------------------------------

    /// On system sleep / screen sleep, deactivate the ward. The CGEventTap is
    /// invalidated by the OS across sleep, so keeping the overlay up would leave
    /// a locked-looking but fully-interactive screen on wake.
    @objc private func systemWillSleep() {
        guard overlayWindow != nil else { return }
        print("Wardlume [AppDelegate]: system sleeping — tearing down ward to avoid a dead-tap lock on wake.")
        deactivateWard()
    }

    /// On wake, if we somehow still hold an overlay but the tap is no longer
    /// armed, tear the ward down — input would otherwise be unprotected behind it.
    @objc private func systemDidWake() {
        guard overlayWindow != nil else { return }
        if inputLockManager?.isLocked != true {
            print("Wardlume [AppDelegate]: woke with overlay up but tap dead — tearing down ward.")
            deactivateWard()
        }
    }

    // -------------------------------------------------------------------------
    // MARK: — Ward toggle
    // -------------------------------------------------------------------------

    @objc func toggleWard() {
        if overlayWindow != nil {
            deactivateWard()
        } else {
            activateWard()
        }
    }

    /// Tears down the ward: stop watchdog → uninstall tap → dismiss reaction →
    /// remove overlays (primary + secondary displays) → stop capture → reset menu.
    /// Idempotent and safe to call from any teardown path (hotkey, sleep, install
    /// failure, watchdog escalation, quit).
    private func deactivateWard() {
        guard let window = overlayWindow else { return }

        // Stop the keep-on-top watchdog first so it can't fight the teardown.
        stopWardWatchdog()

        // Restore system gesture settings blocked during the ward session.
        GestureBlocker.shared.deactivate()

        inputLockManager?.uninstall()

        // Dismiss any live reaction overlay immediately. Must happen before
        // window.close() so no stale overlay outlives the ward session.
        reactionManager?.dismissReaction()

        // Phase 4b: remove base image view and resume Metal rendering
        baseImageView?.removeFromSuperview()
        baseImageView = nil

        // Phase 5a-p2: stop breathing animation and remove corner indicator.
        indicatorView?.layer?.removeAllAnimations()
        indicatorView?.removeFromSuperview()
        indicatorView = nil

        // Tear down unlock hint.
        unlockHintView?.layer?.removeAllAnimations()
        unlockHintView?.removeFromSuperview()
        unlockHintView = nil

        if let metalView = window.contentView as? MetalOverlayView {
            metalView.isPaused = false  // ready for next activation
        }

        captureManager?.stopCapture()
        captureManager = nil

        // Close the secondary-display blackout windows.
        for w in secondaryOverlayWindows { w.close() }
        secondaryOverlayWindows.removeAll()

        window.close()
        overlayWindow         = nil
        toggleMenuItem?.title = "Activate Ward"
        toggleMenuItem?.keyEquivalent = "l"
        toggleMenuItem?.keyEquivalentModifierMask = [.command, .shift]
        unlockMenuItem?.isEnabled = false
    }

    /// Brings the ward up: permission gate → window(s) → capture → input lock.
    private func activateWard() {
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
                // Open the pane for whichever permission is actually missing.
                // If both are missing, open Accessibility first — after granting and
                // relaunching, the next activation attempt routes to Input Monitoring.
                let pane: String
                if !InputLockManager.accessibilityGranted() {
                    pane = "Privacy_Accessibility"
                } else {
                    pane = "Privacy_ListenEvent"   // Input Monitoring pane
                }
                if let url = URL(string:
                    "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
                    NSWorkspace.shared.open(url)
                }
            }
            return
        }

        // --- Activate: create window, start capture, install input lock --
        let primaryScreen = NSScreen.main ?? NSScreen.screens.first
        let screenFrame   = primaryScreen?.frame ?? .zero

        let window = NSWindow(
            contentRect: screenFrame,
            styleMask:   [.borderless],
            backing:     .buffered,
            defer:       false)

        window.isReleasedWhenClosed = false
        window.level                = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.isOpaque             = true
        window.backgroundColor      = .black
        window.hasShadow            = false

        let metalView = MetalOverlayView(frame: screenFrame)
        window.contentView = metalView

        window.ignoresMouseEvents = true
        window.makeKeyAndOrderFront(nil)

        overlayWindow         = window
        toggleMenuItem?.title = "Deactivate Ward"
        toggleMenuItem?.keyEquivalent = ""
        toggleMenuItem?.keyEquivalentModifierMask = []
        unlockMenuItem?.isEnabled = true

        // Cover every OTHER display with an opaque-black overlay so secondary
        // screens don't keep showing the live desktop. The session-wide event tap
        // already blocks keyboard input globally, but without these windows a
        // second monitor would still display un-warded content. We register each
        // window ID with the input lock so clicks on them are consumed, not
        // whitelisted (they are Wardlume windows but must behave like the ward).
        installSecondaryDisplayBlackouts(excluding: primaryScreen)

        // Phase 4b: layer base image above the Metal shader if one is resolved.
        let activePack = reactionManager?.activePack ?? .silentProfessional

        // Phase 5a: set shader mode based on pack's shaderStyle
        metalView.params.minimalMode = (activePack.shaderStyle == .minimal) ? 1.0 : 0.0

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

        // Phase 5a-p2: layer the pill indicator above Metal when the pack
        // requests it and no base image is present (Phase 4b takes precedence).
        if activePack.hasCornerIndicator && baseImageView == nil {
            let pillW:  CGFloat = 80
            let pillH:  CGFloat = 48

            // Horizontally centered, above the unlock hint with a tight gap.
            // Hint sits at y≈40 with height≈40pt, so its top edge ≈80pt.
            // Eye pill bottom edge at y=93 → ~13pt gap between the two pills.
            let pillX = (metalView.bounds.width - pillW) / 2
            let pillY: CGFloat = 93

            let pill = NSView(frame: CGRect(x: pillX, y: pillY,
                                           width: pillW, height: pillH))
            pill.wantsLayer = true
            pill.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
            pill.layer?.cornerRadius    = 14
            pill.layer?.borderWidth     = 1
            pill.layer?.borderColor     = NSColor.white.withAlphaComponent(0.15).cgColor
            pill.alphaValue = 0.85

            // eye.fill icon — 32pt light weight, white, centered in pill.
            let config = NSImage.SymbolConfiguration(pointSize: 32, weight: .light)
            if let symbol = NSImage(systemSymbolName: "eye.fill",
                                    accessibilityDescription: "Ward active")?
                               .withSymbolConfiguration(config) {
                let iconSize: CGFloat = 36
                let iv = NSImageView(frame: CGRect(
                    x: (pillW - iconSize) / 2,
                    y: (pillH - iconSize) / 2,
                    width:  iconSize,
                    height: iconSize))
                iv.image            = symbol
                iv.imageScaling     = .scaleProportionallyDown
                iv.contentTintColor = .white
                pill.addSubview(iv)
            }

            metalView.addSubview(pill)
            indicatorView = pill

            if let layer = pill.layer {
                startBreathingAnimation(on: layer)
            }
        }

        // Unlock hint — shown for ALL packs so users can always discover how to unlock.
        // Fades in after a short delay to preserve the initial "magic" moment.
        do {
            // Attributed hint: "Press " + "⌘⇧U" (17pt semibold) + " to unlock"
            // Mixing sizes inside one label so the shortcut symbols are clearly
            // legible without making the surrounding words feel oversized.
            let normalFont   = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
            let shortcutFont = NSFont.monospacedSystemFont(ofSize: 17, weight: .semibold)
            let normalAttrs:   [NSAttributedString.Key: Any] = [.font: normalFont,   .foregroundColor: NSColor.white]
            let shortcutAttrs: [NSAttributedString.Key: Any] = [.font: shortcutFont, .foregroundColor: NSColor.white]

            let attrStr = NSMutableAttributedString(string: "Press ", attributes: normalAttrs)
            attrStr.append(NSAttributedString(string: "⌘⇧U",        attributes: shortcutAttrs))
            attrStr.append(NSAttributedString(string: " to unlock", attributes: normalAttrs))

            let label = NSTextField(labelWithString: "")
            label.attributedStringValue = attrStr
            label.backgroundColor = .clear
            label.isBezeled = false
            label.isEditable = false
            label.alignment = .center
            label.sizeToFit()

            let padX: CGFloat = 16
            let padY: CGFloat = 10
            let pillW = label.frame.width + padX * 2
            let pillH = label.frame.height + padY * 2

            // Bottom-center, 40pt up from the bottom edge (Cocoa origin = bottom-left).
            let hintX = (metalView.bounds.width - pillW) / 2
            let hintY: CGFloat = 40

            let hint = NSView(frame: CGRect(x: hintX, y: hintY, width: pillW, height: pillH))
            hint.wantsLayer = true
            hint.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
            hint.layer?.cornerRadius = pillH / 2
            hint.layer?.borderWidth = 1
            hint.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor

            // Center the label inside the hint pill.
            label.frame = CGRect(x: padX, y: padY, width: label.frame.width, height: label.frame.height)
            hint.addSubview(label)

            // Start fully transparent, fade in after a delay.
            hint.alphaValue = 0.0
            metalView.addSubview(hint)
            unlockHintView = hint

            // Fade in after 4 seconds — preserves the initial aesthetic, then ensures
            // anyone lingering/confused sees the unlock instructions.
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
                guard let hint = self?.unlockHintView else { return }
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 1.0
                    hint.animator().alphaValue = 0.75
                }
            }
        }

        // Start desktop capture. If there is no Metal device we cannot lock
        // safely — abort the activation and tear the half-built ward down rather
        // than leave a window with no working shader on screen.
        guard let device = metalView.device else {
            print("Wardlume [AppDelegate]: no Metal device — aborting activation.")
            deactivateWard()
            return
        }
        let capture = DesktopCaptureManager(device: device, view: metalView)
        capture.captureDelegate = self
        captureManager = capture
        capture.startCapture(excludingWindow: window)

        // Install the CGEventTap.
        // wardWindow is passed explicitly so the callback can exclude the
        // overlay surface from the Wardlume-window whitelist — events that
        // land on the ward overlay itself must still be consumed.
        guard let lock = inputLockManager else {
            deactivateWard()
            return
        }

        // CRITICAL: if the tap fails to install (e.g. a permission was revoked
        // between the preflight check above and here), the overlay is already on
        // screen but input is NOT locked. Tear the ward down and warn the user
        // rather than present a locked-LOOKING but fully-interactive screen.
        guard lock.install(view: metalView, wardWindow: window) else {
            print("Wardlume [AppDelegate]: input lock failed to install — tearing down ward.")
            deactivateWard()
            let alert = NSAlert()
            alert.messageText     = "Ward Could Not Lock Input"
            alert.informativeText = """
                Wardlume could not install the input lock, so the ward was not \
                activated. This usually means Accessibility or Input Monitoring \
                permission was turned off.

                Re-enable Wardlume in System Settings → Privacy & Security, then \
                try again.
                """
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        // Touch ID unlock: Cmd+Shift+U triggers biometric authentication.
        // Handled inside the CGEventTap callback (not via NSEvent.addGlobalMonitorForEvents)
        // because global NSEvent monitors are listen-only taps that cannot observe
        // events our head-insert read-write tap consumes.
        lock.onUnlockHotkey = { [weak self] in self?.unlockWithBiometrics() }

        // Phase 2.5a: wire intrusion events to the reaction engine.
        // ReactionManager.trigger() enforces its own cooldown — this fires
        // on every consumed event regardless of the border-pulse debounce.
        // Phase 5a-p2: flash both pills in one CATransaction so Core Animation
        // schedules both layer.add calls on the same frame — perfectly synced glow.
        // Both flash methods guard on their own view; safe to call unconditionally.
        lock.onIntrusion = { [weak self] in
            guard let self else { return }
            self.reactionManager?.trigger()
            CATransaction.begin()
            self.flashIndicator()
            self.flashUnlockHint()
            CATransaction.commit()
        }

        // Block system trackpad gestures (Mission Control, Spaces, Launchpad, etc.)
        // for the duration of this ward session. Restored by deactivateWard() or
        // automatically on next launch via GestureBlocker.recoverIfNeeded().
        GestureBlocker.shared.activate()

        // Start the keep-on-top watchdog.
        startWardWatchdog()
    }

    // -------------------------------------------------------------------------
    // MARK: — Secondary-display blackout
    // -------------------------------------------------------------------------

    /// Covers every screen except `primaryScreen` with an opaque-black borderless
    /// window at CGShieldingWindowLevel, so secondary monitors don't keep displaying
    /// the live desktop while the ward is up. Each window's ID is registered with
    /// the input lock so clicks on it are consumed (not whitelisted).
    private func installSecondaryDisplayBlackouts(excluding primaryScreen: NSScreen?) {
        let shieldLevel = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        for screen in NSScreen.screens where screen != primaryScreen {
            let w = NSWindow(contentRect: screen.frame,
                             styleMask: [.borderless],
                             backing: .buffered,
                             defer: false)
            w.isReleasedWhenClosed = false
            w.level                = shieldLevel
            w.isOpaque             = true
            w.backgroundColor      = .black
            w.hasShadow            = false
            w.ignoresMouseEvents   = true
            w.makeKeyAndOrderFront(nil)
            inputLockManager?.registerSecondaryOverlay(CGWindowID(w.windowNumber))
            secondaryOverlayWindows.append(w)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: — Keep-on-top watchdog
    // -------------------------------------------------------------------------

    private func startWardWatchdog() {
        stopWardWatchdog()
        watchdogReraiseCount = 0
        // 0.5 s cadence: fast enough to re-raise within the window the user would
        // notice, slow enough to be negligible cost. Runs on the main run loop.
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.watchdogTick()
        }
        timer.tolerance = 0.1
        wardWatchdog = timer
    }

    private func stopWardWatchdog() {
        wardWatchdog?.invalidate()
        wardWatchdog = nil
        watchdogReraiseCount = 0
    }

    /// One watchdog cycle. If the ward window has been displaced, re-raise it.
    /// After `maxWatchdogReraises` consecutive failed recoveries, fall back to
    /// the real macOS lock screen.
    private func watchdogTick() {
        guard let window = overlayWindow else { stopWardWatchdog(); return }

        // Don't fight the menu: menuWillOpen intentionally lowers the level.
        if menuIsOpen { return }

        let shieldLevel = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        let displaced = window.isMiniaturized
            || !window.isVisible
            || window.level.rawValue < shieldLevel.rawValue

        guard displaced else {
            watchdogReraiseCount = 0
            return
        }

        if watchdogReraiseCount >= maxWatchdogReraises {
            print("Wardlume [AppDelegate]: ward kept being displaced after " +
                  "\(maxWatchdogReraises) re-raise attempts — falling back to macOS lock screen.")
            stopWardWatchdog()
            deactivateWard()
            Self.lockSystemScreen()
            return
        }

        watchdogReraiseCount += 1
        print("Wardlume [AppDelegate]: ward displaced (attempt \(watchdogReraiseCount)/\(maxWatchdogReraises)) — re-raising.")
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.level = shieldLevel
        window.orderFrontRegardless()
        for w in secondaryOverlayWindows {
            w.level = shieldLevel
            w.orderFrontRegardless()
        }
    }

    /// Invokes the real macOS lock screen (login window) via the private
    /// login.framework `SACLockScreenImmediate` symbol — the same call `pmset`
    /// and several open-source utilities use. Falls back to a Keychain-lock
    /// AppleScript-free no-op log if the symbol can't be resolved.
    private static func lockSystemScreen() {
        typealias LockFn = @convention(c) () -> Int32
        let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW)
        defer { if handle != nil { dlclose(handle) } }
        if let sym = dlsym(handle, "SACLockScreenImmediate") {
            let lock = unsafeBitCast(sym, to: LockFn.self)
            _ = lock()
            print("Wardlume [AppDelegate]: SACLockScreenImmediate invoked — macOS lock screen engaged.")
        } else {
            print("Wardlume [AppDelegate]: ⚠️ could not resolve SACLockScreenImmediate; system lock fallback unavailable.")
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
    // MARK: — Corner Indicator (Phase 5a-p2)
    // -------------------------------------------------------------------------

    /// Starts the 75%→95% opacity breathing animation on the given layer.
    /// Extracted so it can be called both at indicator creation and after a
    /// flash sequence completes without duplicating animation parameters.
    private func startBreathingAnimation(on layer: CALayer) {
        let breathe = CABasicAnimation(keyPath: "opacity")
        breathe.fromValue      = 0.55
        breathe.toValue        = 0.95
        breathe.duration       = 2.0         // 2 s rise + 2 s fall (autoreverses) = 4 s cycle
        breathe.autoreverses   = true
        breathe.repeatCount    = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(breathe, forKey: "wardBreathing")
    }

    /// Flashes the pill indicator backdrop to system-red on intrusion, then
    /// returns to the dark backdrop. Runs as a separate CABasicAnimation on
    /// the backgroundColor keyPath — the breathing opacity animation on the
    /// same layer continues undisturbed (different keyPaths don't conflict).
    ///
    /// Guard-exits immediately when indicatorView is nil (a pack without a corner
    /// indicator is active, or ward deactivated) so the onIntrusion closure needs
    /// no pack check.
    private func flashIndicator() {
        guard let layer = indicatorView?.layer else { return }

        let darkBG = NSColor.black.withAlphaComponent(0.6).cgColor
        let redBG  = NSColor.systemRed.withAlphaComponent(0.7).cgColor

        // 0.3 s to red, 0.3 s back = 0.6 s total. autoreverses handles the return.
        // Breathing opacity animation on the same layer is unaffected (different keyPath).
        let flash = CABasicAnimation(keyPath: "backgroundColor")
        flash.fromValue      = darkBG
        flash.toValue        = redBG
        flash.duration       = 0.3
        flash.autoreverses   = true
        flash.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(flash, forKey: "wardFlash")
    }

    /// Flashes the unlock hint backdrop red on intrusion, identical in structure
    /// to flashIndicator() — dark→red, 0.3s, autoreverses, easeInEaseOut — so
    /// both pills rise and fall in perfect unison when called inside the same
    /// CATransaction. Guard-exits if the hint isn't present yet (e.g., intrusion
    /// fires before the 4s fade-in) or if the ward has been deactivated.
    private func flashUnlockHint() {
        guard let layer = unlockHintView?.layer else { return }

        let darkBG = NSColor.black.withAlphaComponent(0.6).cgColor
        let redBG  = NSColor.systemRed.withAlphaComponent(0.7).cgColor

        // Identical to flashIndicator(): dark→red, 0.3s, autoreverses = 0.6s total.
        // Both pills animate on the same curve so the glow is frame-locked in sync.
        let flash = CABasicAnimation(keyPath: "backgroundColor")
        flash.fromValue      = darkBG
        flash.toValue        = redBG
        flash.duration       = 0.3
        flash.autoreverses   = true
        flash.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(flash, forKey: "hintFlash")
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
        case #selector(testLock):
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
        //
        // menuIsOpen tells the keep-on-top watchdog to stand down so it doesn't
        // immediately re-raise the ward to .screenSaver and steal the menu's clicks.
        menuIsOpen = true
        overlayWindow?.level = .popUpMenu
        for w in secondaryOverlayWindows { w.level = .popUpMenu }
    }

    func menuDidClose(_ menu: NSMenu) {
        // Restore the security level. Handle the case where the ward was
        // deactivated via Cmd+Shift+W while the menu was open (overlayWindow
        // would be nil) — in that case, there's nothing to restore.
        menuIsOpen = false
        overlayWindow?.level = .screenSaver
        for w in secondaryOverlayWindows { w.level = .screenSaver }
    }

    // -------------------------------------------------------------------------
    // MARK: — Quit
    // -------------------------------------------------------------------------

    @objc func quitApp() {
        // Full teardown (stops watchdog, uninstalls tap, closes all overlays).
        deactivateWard()
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

// -------------------------------------------------------------------------
// MARK: — DesktopCaptureManagerDelegate
// -------------------------------------------------------------------------

extension AppDelegate: DesktopCaptureManagerDelegate {
    /// The capture stream stopped unexpectedly while the ward was up (most likely
    /// Screen Recording permission was revoked). The input lock is independent of
    /// capture, so the overlay would otherwise freeze on its last frame with input
    /// still locked — a lockout behind a stale image. Tear the ward down so the
    /// user regains control, and tell them why.
    func desktopCaptureDidStop(_ manager: DesktopCaptureManager, error: Error?) {
        guard overlayWindow != nil, manager === captureManager else { return }
        print("Wardlume [AppDelegate]: capture stopped unexpectedly — tearing down ward.")
        deactivateWard()
        let alert = NSAlert()
        alert.messageText     = "Ward Deactivated"
        alert.informativeText = """
            Wardlume's screen capture stopped, so the ward was deactivated to \
            avoid leaving a frozen, locked-looking screen.

            This usually means Screen Recording permission was turned off. \
            Re-enable Wardlume in System Settings → Privacy & Security → Screen \
            Recording, then activate the ward again.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
