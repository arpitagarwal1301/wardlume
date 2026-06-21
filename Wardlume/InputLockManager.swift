//  InputLockManager.swift
//  Wardlume
//
//  Phase 2a: Session-level CGEventTap that silently discards all keyboard,
//  mouse, and trackpad input while the ward is active.
//
//  Concurrency:
//    SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor makes this class implicitly
//    @MainActor. The CGEventTap callback (wardEventTapCallback) is a global
//    C function whose CFRunLoopSource is added to the main run loop, so the
//    callback fires synchronously on the main thread — the same thread as
//    @MainActor. Properties accessed from the callback carry nonisolated(unsafe)
//    to satisfy Swift 6 static analysis while relying on the run-loop thread
//    guarantee for actual safety.

import CoreGraphics
import ApplicationServices
import AppKit
import QuartzCore

// ---------------------------------------------------------------------------
// Global C-style callback required by CGEventTapCreate.
// Runs on the main run loop thread (same as @MainActor).
// ---------------------------------------------------------------------------
private func wardEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>?
{
    guard let refcon else { return Unmanaged.passRetained(event) }
    let mgr = Unmanaged<InputLockManager>.fromOpaque(refcon).takeUnretainedValue()
    return mgr.handleEvent(proxy: proxy, type: type, event: event)
}

// ---------------------------------------------------------------------------
// InputLockManager
// ---------------------------------------------------------------------------
final class InputLockManager: NSObject {

    // -------------------------------------------------------------------------
    // MARK: — Tap state
    // nonisolated(unsafe): accessed from the C callback on the main run loop
    // thread. The thread invariant makes this safe despite the unsafe annotation.
    // -------------------------------------------------------------------------
    nonisolated(unsafe) private var tapRef:            CFMachPort?
    nonisolated(unsafe) private var runLoopSource:     CFRunLoopSource?
    nonisolated(unsafe) private var lastIntrusionWall: CFTimeInterval = -.infinity
    nonisolated(unsafe) private var gestureMonitor:    Any?
    // Cached at install() time on the main thread; read in the callback.
    nonisolated(unsafe) private var menuBarThreshold:  CGFloat = 50

    // Configurable unlock combo, cached for the nonisolated callback. Set on the
    // main thread at install() and via setUnlockCombo() (mid-ward changes); read in
    // the callback on the same run loop, so the thread invariant keeps it safe.
    // Defaults preserve ⌘⇧U (keycode 32) until install() supplies the real combo.
    nonisolated(unsafe) private var unlockKeyCode: Int64 = 32
    nonisolated(unsafe) private var unlockFlags: CGEventFlags = [.maskCommand, .maskShift]

    // Optional emergency-exit ("panic") combo, default OFF. When enabled, matching
    // it in the callback drops the ward with NO authentication. Cached like the
    // unlock combo; set on the main thread, read on the run-loop thread.
    nonisolated(unsafe) private var panicEnabled: Bool = false
    nonisolated(unsafe) private var panicKeyCode: Int64 = 0
    nonisolated(unsafe) private var panicFlags: CGEventFlags = []

    // Set by AppDelegate via install(view:wardWindow:); accessed in the callback.
    nonisolated(unsafe) weak var metalView: MetalOverlayView?

    // -------------------------------------------------------------------------
    // MARK: — Whitelist state (Phase 2a fix)
    // Cached at install() time so the nonisolated callback can read them safely.
    // -------------------------------------------------------------------------

    /// CGWindowID of the ward overlay window.
    /// Events on this window are specifically NOT whitelisted — it's the surface
    /// we want blocked. All other Wardlume windows (menus, alerts, etc.) ARE
    /// whitelisted so our own UI remains reachable while the ward is active.
    nonisolated(unsafe) private var wardWindowID: CGWindowID = 0

    /// CGWindowID of the active reaction overlay window (if any).
    /// Set by ReactionManager when a reaction window is created/destroyed.
    /// Treated identically to wardWindowID in the whitelist iteration —
    /// events that fall on this window are consumed, not passed through.
    /// Updated on the main thread; nonisolated(unsafe) for callback access.
    nonisolated(unsafe) var reactionWindowID: CGWindowID?

    /// CGWindowIDs of the secondary-display blackout windows (one per non-primary
    /// screen). Like the ward overlay, these are Wardlume-owned windows that must
    /// be CONSUMED, not whitelisted — otherwise a click on a blacked-out second
    /// monitor would leak through to the app behind it. Set on activate, cleared
    /// on uninstall. Mutated on the main thread; read in the callback.
    nonisolated(unsafe) private var secondaryOverlayIDs: Set<CGWindowID> = []

    /// Wardlume's process ID, used to identify our windows via CGWindowListCopyWindowInfo
    /// without touching @MainActor-isolated NSApp.windows from a nonisolated context.
    nonisolated(unsafe) private var wardlumePID: pid_t = 0

    /// Screen height in AppKit points.
    /// Documented here for the coordinate-system record: a y-flip (screenHeight − quartzY)
    /// converts CGEvent.location (Quartz, y=0 at TOP) to AppKit (y=0 at BOTTOM).
    /// This flip is NOT used in the whitelist check because CGWindowListCopyWindowInfo
    /// returns bounds in Quartz coordinates — the same system as CGEvent.location —
    /// so quartzRect.contains(event.location) needs no conversion.
    nonisolated(unsafe) private var cachedScreenHeight: CGFloat = 800

    // -------------------------------------------------------------------------
    // MARK: — Unlock hotkey callback
    // -------------------------------------------------------------------------

    /// Called (on the main thread) when Cmd+Shift+U is intercepted.
    /// Set by AppDelegate to invoke BiometricUnlockManager.evaluateUnlock(...).
    ///
    /// Handled inside the CGEventTap callback (not via NSEvent.addGlobalMonitorForEvents)
    /// because global NSEvent monitors are implemented as listen-only taps and cannot
    /// observe events our head-insert read-write tap consumes.
    nonisolated(unsafe) var onUnlockHotkey: (() -> Void)?

    /// Called (on the main thread) when an input event is consumed as an intrusion.
    /// Set by AppDelegate to invoke ReactionManager.trigger().
    ///
    /// This fires AFTER the border-pulse debounce check but is NOT gated on that
    /// same debounce — ReactionManager owns its own cooldown. Both signals fire
    /// independently because they serve different purposes:
    ///   • Border pulse  → visual shader feedback for the ward *owner* (max 1 per 500 ms).
    ///   • onIntrusion   → punitive reaction overlay for the *intruder* (max 1 per cooldown).
    /// Conflating the two clocks would make changing one silently break the other.
    nonisolated(unsafe) var onIntrusion: (() -> Void)?

    /// Called (on the main thread) when the emergency-exit combo is matched while
    /// enabled. Set by AppDelegate to tear the ward down WITHOUT authentication.
    /// Independent of the intrusion/grace/auth gating — the panic key must always
    /// work the instant it's pressed.
    nonisolated(unsafe) var onPanic: (() -> Void)?

    // -------------------------------------------------------------------------
    // MARK: — Permission helpers
    // -------------------------------------------------------------------------

    /// True if the Accessibility TCC permission is already granted.
    static func accessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    /// True if the Input Monitoring TCC permission is already granted.
    /// CGPreflightListenEventAccess() is available on macOS 12+.
    static func inputMonitoringGranted() -> Bool {
        CGPreflightListenEventAccess()
    }

    /// True only when both permissions required by CGEventTap are granted.
    static func permissionsReady() -> Bool {
        accessibilityGranted() && inputMonitoringGranted()
    }

    /// Triggers the system dialogs / Settings panes for both permissions.
    /// Safe to call even when permissions are already granted (no-ops).
    static func requestPermissions() {
        if !accessibilityGranted() {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        }
        if !inputMonitoringGranted() {
            CGRequestListenEventAccess()
        }
    }

    // -------------------------------------------------------------------------
    // MARK: — Lifecycle (called from @MainActor context)
    // -------------------------------------------------------------------------

    /// Creates the CGEventTap, wraps it in a run-loop source, and enables it.
    /// Idempotent — safe to call multiple times.
    ///
    /// - Parameter wardWindow: The magical ward overlay window. Events landing
    ///   on this window are consumed (blocked). All other Wardlume windows are
    ///   whitelisted so menus, alerts, and future UI remain accessible.
    /// - Returns: `true` if the tap was created and enabled (input is now locked),
    ///   `false` if `CGEvent.tapCreate` failed (e.g. a TCC permission was revoked
    ///   between the preflight check and here). On `false` the caller MUST tear
    ///   down the ward overlay — otherwise a "locked-looking" screen would be left
    ///   on top of a fully interactive system.
    @discardableResult
    func install(view: MetalOverlayView, wardWindow: NSWindow, unlock: HotkeyCombo) -> Bool {
        guard tapRef == nil else { return true }
        metalView = view

        // Cache whitelist identifiers while on the main thread.
        wardWindowID       = CGWindowID(wardWindow.windowNumber)
        wardlumePID        = pid_t(ProcessInfo.processInfo.processIdentifier)
        cachedScreenHeight = NSScreen.main?.frame.height ?? 800
        unlockKeyCode      = Int64(unlock.keyCode)
        unlockFlags        = unlock.cgEventFlags

        // Cache the menu-bar strip height while we're on the main thread.
        // Quartz coordinates: y=0 at the top of the primary display, increasing
        // downward. The menu bar occupies approximately the top `thickness` pts.
        // An 8 pt buffer gives tolerance for mismatched coordinate rounding.
        menuBarThreshold = NSStatusBar.system.thickness + 8

        // Intercept all keyboard and pointer event classes.
        //
        // kCGEventTabletPointer / kCGEventTabletProximity (raw values 23 / 24) are
        // included so a paired stylus / drawing tablet cannot drive the system
        // while the ward is up — these are NOT covered by the mouse event types.
        // (CGEventType has no Swift case for them, so the raw values are used.)
        //
        // NSEventTypeSystemDefined (media / brightness / volume / play-pause keys)
        // is delivered as a Quartz event of type 14. We intercept it so an intruder
        // can't change volume/brightness or drive media playback through the lock.
        let kTabletPointer:   UInt32 = 23
        let kTabletProximity: UInt32 = 24
        let kSystemDefined:   UInt32 = 14
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)          |
            (1 << CGEventType.keyUp.rawValue)             |
            (1 << CGEventType.flagsChanged.rawValue)      |
            (1 << CGEventType.leftMouseDown.rawValue)     |
            (1 << CGEventType.leftMouseUp.rawValue)       |
            (1 << CGEventType.leftMouseDragged.rawValue)  |
            (1 << CGEventType.rightMouseDown.rawValue)    |
            (1 << CGEventType.rightMouseUp.rawValue)      |
            (1 << CGEventType.rightMouseDragged.rawValue) |
            (1 << CGEventType.mouseMoved.rawValue)        |
            (1 << CGEventType.otherMouseDown.rawValue)    |
            (1 << CGEventType.otherMouseUp.rawValue)      |
            (1 << CGEventType.otherMouseDragged.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue)        |
            (1 << kTabletPointer)                          |
            (1 << kTabletProximity)                        |
            (1 << kSystemDefined)

        // passUnretained: AppDelegate holds a strong reference to this object
        // for the entire lifetime of an active ward session.
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,          // session-wide — before any app sees the event
            place: .headInsertEventTap,        // inserted at the head of the tap list
            options: .defaultTap,              // read-write tap — can return nil to consume
            eventsOfInterest: mask,
            callback: wardEventTapCallback,
            userInfo: refcon)
        else {
            print("Wardlume [InputLockManager]: CGEventTapCreate failed. " +
                  "Accessibility or Input Monitoring permission may be missing.")
            metalView = nil   // we never armed; don't hold a stale view reference
            return false
        }
        tapRef = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        // Trackpad gesture events are NSEvent-only — CGEventTap doesn't see them.
        // Local monitor consumes gestures dispatched to our process.
        // Global monitor cannot consume (AppKit docs), only observe — see Known
        // Limitations in SAFETY_NOTES.md re: Mission Control and Spaces.
        let gestureMask: NSEvent.EventTypeMask = [
            .gesture, .magnify, .swipe, .rotate,
            .smartMagnify, .beginGesture, .endGesture,
            .directTouch
        ]
        gestureMonitor = NSEvent.addLocalMonitorForEvents(matching: gestureMask) { _ in
            return nil  // consume
        }

        print("Wardlume [InputLockManager]: event tap installed. " +
              "wardWindowID=\(wardWindowID) wardlumePID=\(wardlumePID)")
        return true
    }

    /// True if a tap is currently installed and armed. Used by AppDelegate's
    /// sleep/wake handling to detect a ward that *looks* active (overlay still on
    /// screen) but whose tap was torn down by the OS (e.g. on system sleep).
    var isLocked: Bool { tapRef != nil }

    /// Updates the unlock combo on a running tap (e.g. the user changed it in the
    /// Shortcuts pane while warded). Main-thread only — the callback reads these
    /// fields on the same run loop, so no locking is needed.
    func setUnlockCombo(_ combo: HotkeyCombo) {
        unlockKeyCode = Int64(combo.keyCode)
        unlockFlags   = combo.cgEventFlags
    }

    /// Updates the emergency-exit ("panic") combo and whether it's enabled.
    /// Main-thread only — the callback reads these on the same run loop.
    func setEmergencyExit(enabled: Bool, combo: HotkeyCombo) {
        panicEnabled = enabled
        panicKeyCode = Int64(combo.keyCode)
        panicFlags   = combo.cgEventFlags
    }

    /// Registers a secondary-display blackout window so the callback consumes
    /// clicks landing on it (treats it like the ward overlay) instead of
    /// whitelisting it as a generic Wardlume window. Call once per secondary
    /// window at activation. Cleared automatically by uninstall().
    func registerSecondaryOverlay(_ id: CGWindowID) {
        secondaryOverlayIDs.insert(id)
    }

    /// Disables and removes the CGEventTap. Idempotent — safe to call when
    /// no tap is installed. Input resumes normally after this call returns.
    func uninstall() {
        if let tap = tapRef {
            CGEvent.tapEnable(tap: tap, enable: false)
            tapRef = nil
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let monitor = gestureMonitor {
            NSEvent.removeMonitor(monitor)
            gestureMonitor = nil
        }
        secondaryOverlayIDs.removeAll()
        reactionWindowID = nil
        metalView = nil
        print("Wardlume [InputLockManager]: event tap uninstalled.")
    }

    // -------------------------------------------------------------------------
    // MARK: — Event handling
    // Called from wardEventTapCallback on the main run loop thread.
    // nonisolated: allows the non-actor C callback to invoke this method
    // without a Swift 6 actor-crossing error.
    // -------------------------------------------------------------------------

    nonisolated func handleEvent(proxy: CGEventTapProxy,
                                  type: CGEventType,
                                  event: CGEvent) -> Unmanaged<CGEvent>? {

        let loc = event.location

        // ── Step 1: Tap-disabled re-enable ────────────────────────────────────
        // macOS can disable the tap if the callback is too slow.
        // Re-enabling here keeps the lock active across any transient hiccups.
        //
        // We CONSUME (return nil) the triggering event rather than passing it
        // through: the event that tripped the timeout is, by definition, one we
        // would otherwise have evaluated for the lock. Passing it through would
        // leak that single input to the system during the disable→re-enable gap.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            print("Wardlume [InputLockManager]: ⚠️ TAP DISABLED type=\(type.rawValue), re-enabling")
            if let tap = tapRef { CGEvent.tapEnable(tap: tap, enable: true) }
            return nil
        }

        // ── Step 2: Cmd+Shift+U unlock hotkey ────────────────────────────────
        // Detected BEFORE any consume decision so it always fires.
        //
        // Handled here (inside the tap callback) rather than via
        // NSEvent.addGlobalMonitorForEvents — global NSEvent monitors are listen-only
        // taps and cannot observe events our head-insert read-write tap consumes.
        //
        // The unlock combo is user-configurable (default ⌘⇧U); cached in
        // unlockKeyCode / unlockFlags at install() time. Cmd+Shift+W is NOT special
        // — it is consumed silently like any other keystroke while the ward is active.
        if type == .keyDown {
            let keycode = event.getIntegerValueField(.keyboardEventKeycode)
            // Mask the live flags to the four real modifiers and require an EXACT
            // match, so e.g. ⌘⇧U does not also fire on ⌘⇧⌃U.
            let masked = event.flags.intersection(HotkeyCombo.realModifierMask)
            if keycode == unlockKeyCode && masked == unlockFlags {
                // Dispatch async to avoid blocking the tap callback with heavy work
                // (Touch ID prompt, biometric evaluation).
                if let cb = onUnlockHotkey {
                    DispatchQueue.main.async { cb() }
                }
                return nil
            }
            // Emergency-exit ("panic") combo: drops the ward with no authentication
            // when enabled. Independent of the grace/auth gating so it always works.
            if panicEnabled && keycode == panicKeyCode && masked == panicFlags {
                if let cb = onPanic {
                    DispatchQueue.main.async { cb() }
                }
                return nil
            }
        }

        // ── Step 3: Mouse/scroll whitelist ────────────────────────────────────
        //
        // Two categories of events:
        //
        // "Action" events (clicks, scrolls): run the full whitelist — both the
        // fast menu-bar strip check and the CGWindowListCopyWindowInfo check.
        //
        // "Move/drag" events: only the fast menu-bar strip check; we skip the
        // window-list lookup on every pixel of cursor movement for performance.
        //
        // ── Coordinate system note ──────────────────────────────────────────
        // event.location   — Quartz global coords: y=0 at TOP, y increases DOWN
        // NSWindow.frame   — AppKit global coords: y=0 at BOTTOM, y increases UP
        // CGWindowListCopyWindowInfo (kCGWindowBounds) — Quartz coords (same as event)
        //
        // The whitelist uses CGWindowListCopyWindowInfo, so comparing
        // quartzRect.contains(event.location) needs NO y-flip.
        // If we ever switch to NSWindow.frame, the conversion is:
        //   appKitY = cachedScreenHeight − event.location.y

        let isMouse = type == .leftMouseDown   || type == .leftMouseUp    ||
                      type == .rightMouseDown  || type == .rightMouseUp   ||
                      type == .scrollWheel
        let isMove  = type == .mouseMoved      || type == .leftMouseDragged  ||
                      type == .rightMouseDragged || type == .otherMouseDragged

        // System-defined events (media / brightness / volume / play-pause keys)
        // and tablet events have no meaningful window location — they target the
        // system or focused app, not a point on screen. There is no Wardlume UI
        // to whitelist for them, so they always fall through to consume below.
        // (We simply don't run the location-based whitelist for them.)

        // ── Fast path: menu-bar strip ─────────────────────────────────────────
        // The top `menuBarThreshold` pts is the system menu bar, which contains
        // far more than our status item: the Apple menu (Restart / Shut Down /
        // Log Out), Control Center, Wi-Fi, the clock, and OTHER apps' status
        // items. Blindly passing the whole strip through would let an intruder
        // restart the Mac or open Control Center. So we run the SAME ownership
        // check as the full whitelist — a click in the strip is passed through
        // ONLY if it lands on a Wardlume-owned window (our status item / its
        // menu). Everything else in the strip is consumed.
        //
        // Move/drag events that fall in the strip are passed through (cursor can
        // travel over the menu bar); a bare cursor move triggers no action, and
        // running the window-list lookup on every pixel of motion is wasteful.
        if isMove && loc.y < menuBarThreshold {
            return Unmanaged.passRetained(event)
        }

        // ── Wardlume window whitelist (clicks/scrolls only) ───────────────────
        // Lets events through only if they land inside a Wardlume-owned window
        // that is NOT the ward/reaction overlay. This covers the status item and
        // its NSMenu dropdown, NSAlert dialogs, and any future Wardlume UI.
        // Applies everywhere on screen, including the menu-bar strip (above).
        if isMouse && pointHitsWhitelistedWardlumeWindow(loc) {
            return Unmanaged.passRetained(event)
        }

        // ── Step 4: Intrusion pulse + consume ─────────────────────────────────────
        // Event failed all whitelist checks — it lands on the locked desktop.
        // Fire the debounced visual pulse (max once per 500 ms) and discard.
        let now = CACurrentMediaTime()
        if now - lastIntrusionWall > 0.5, let v = metalView {
            lastIntrusionWall = now
            v.intrusionTime = v.params.time
        }

        // Fire the reaction callback. This is NOT gated on lastIntrusionWall —
        // ReactionManager owns its own cooldown (default 5 s) and will decide
        // independently whether to show a reaction. The border pulse above is
        // capped at 500 ms for shader-stability reasons; that constraint must
        // not bleed into the reaction layer.
        // Dispatch async to avoid blocking the tap callback with heavy work
        // (NSWindow creation, Metal compositor warmup on first trigger).
        if let cb = onIntrusion {
            DispatchQueue.main.async { cb() }
        }

        return nil   // consume — event is silently discarded
    }

    /// Returns true if the screen point lands on a Wardlume-owned window that is
    /// NOT the ward overlay or reaction overlay — i.e. our status item, its menu
    /// dropdown, an NSAlert, or any other Wardlume UI that must stay clickable.
    ///
    /// Walks CGWindowListCopyWindowInfo in z-order (front → back). The ward and
    /// reaction overlays are full-screen and always on top, so they're skipped so
    /// we can see whatever Wardlume window sits beneath them. The FIRST window at
    /// the point that is NOT one of our overlays decides the answer:
    ///   • Wardlume-owned → true  (whitelist: let the event through)
    ///   • another app / desktop → false (consume)
    ///
    /// CGWindowListCopyWindowInfo bounds are in Quartz coords — the same system
    /// as event.location — so no y-flip is needed. NSApp.windows can't be used
    /// here: it's @MainActor-isolated and this runs from the nonisolated callback.
    nonisolated private func pointHitsWhitelistedWardlumeWindow(_ loc: CGPoint) -> Bool {
        let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID) as? [[String: Any]] ?? []

        for info in windowList {
            guard
                let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                let pid    = info[kCGWindowOwnerPID as String] as? Int32,
                let wid    = info[kCGWindowNumber as String] as? CGWindowID
            else { continue }

            let quartzRect = CGRect(
                x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0,
                width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)

            guard quartzRect.contains(loc) else { continue }

            if pid == wardlumePID {
                if wid == wardWindowID || wid == reactionWindowID
                    || secondaryOverlayIDs.contains(wid) {
                    // One of our full-screen overlays (ward / reaction / secondary
                    // blackout) — must be consumed, so keep scanning beneath it for
                    // a genuinely-clickable Wardlume window (menu, alert).
                    continue
                }
                // A non-overlay Wardlume window (status item, menu, alert).
                return true
            } else {
                // Topmost non-overlay window here belongs to another app or the
                // desktop. Not whitelisted.
                return false
            }
        }
        return false
    }
}
