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
    // MARK: — Escape hotkey callback (Phase 2a fix)
    // -------------------------------------------------------------------------

    /// Called (on the main thread) when Cmd+Shift+W is intercepted.
    /// Set by AppDelegate to invoke toggleWard().
    ///
    /// Why not NSEvent.addGlobalMonitorForEvents?
    /// Global NSEvent monitors are implemented internally as listen-only CGEventTaps.
    /// When our head-insert read-write tap returns nil, the event is removed from
    /// the pipeline before any other tap — including NSEvent monitors — can observe it.
    /// Detecting the shortcut here, inside handleEvent(), is the only reliable approach.
    nonisolated(unsafe) var onEscapeHotkey: (() -> Void)?

    /// Called (on the main thread) when Cmd+Shift+U is intercepted.
    /// Set by AppDelegate to invoke BiometricUnlockManager.evaluateUnlock(...).
    /// Same architectural rationale as onEscapeHotkey: handled inside the
    /// CGEventTap callback because global NSEvent monitors do not observe
    /// events our head-insert read-write tap consumes.
    nonisolated(unsafe) var onUnlockHotkey: (() -> Void)?

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
    func install(view: MetalOverlayView, wardWindow: NSWindow) {
        guard tapRef == nil else { return }
        metalView = view

        // Cache whitelist identifiers while on the main thread.
        wardWindowID       = CGWindowID(wardWindow.windowNumber)
        wardlumePID        = pid_t(ProcessInfo.processInfo.processIdentifier)
        cachedScreenHeight = NSScreen.main?.frame.height ?? 800

        // Cache the menu-bar strip height while we're on the main thread.
        // Quartz coordinates: y=0 at the top of the primary display, increasing
        // downward. The menu bar occupies approximately the top `thickness` pts.
        // An 8 pt buffer gives tolerance for mismatched coordinate rounding.
        menuBarThreshold = NSStatusBar.system.thickness + 8

        // Intercept all keyboard and pointer event classes.
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
            (1 << CGEventType.scrollWheel.rawValue)

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
            return
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

        // ── Step 1: Tap-disabled re-enable ────────────────────────────────────
        // macOS can disable the tap if the callback is too slow.
        // Re-enabling here keeps the lock active across any transient hiccups.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = tapRef { CGEvent.tapEnable(tap: tap, enable: true) }
            return nil
        }

        // ── Step 2: Cmd+Shift+W escape hotkey ────────────────────────────────
        // Detected BEFORE any consume decision so it always fires.
        //
        // We handle this here (inside the tap callback) rather than via
        // NSEvent.addGlobalMonitorForEvents because global NSEvent monitors are
        // themselves listen-only CGEventTaps: when our head-insert read-write tap
        // returns nil, the event is removed from the pipeline before any monitor
        // (including global ones) can observe it.
        //
        // Keycode 13 = the 'W' physical key on standard keyboard layouts.
        if type == .keyDown {
            let keycode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags   = event.flags
            if keycode == 13 &&
               flags.contains(.maskCommand) && flags.contains(.maskShift) {
                // We are on the main thread (main run loop callback), so calling
                // onEscapeHotkey — which ultimately calls AppDelegate.toggleWard()
                // (@MainActor) — is safe without dispatch.
                onEscapeHotkey?()
                return nil   // consume the keystroke; apps underneath don't see it
            }

            // Keycode 32 = the 'U' physical key on standard keyboard layouts.
            if keycode == 32 &&
               flags.contains(.maskCommand) && flags.contains(.maskShift) {
                onUnlockHotkey?()
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

        let loc = event.location   // Quartz coords throughout this block

        // ── Fast path: menu bar strip ─────────────────────────────────────────
        // Passes through mouse/scroll events in the top strip so the status-bar
        // icon stays clickable. Quartz y < menuBarThreshold = near the top of
        // the screen = in the menu bar.
        let isMouse = type == .leftMouseDown   || type == .leftMouseUp    ||
                      type == .rightMouseDown  || type == .rightMouseUp   ||
                      type == .scrollWheel
        let isMove  = type == .mouseMoved      || type == .leftMouseDragged  ||
                      type == .rightMouseDragged || type == .otherMouseDragged

        if (isMouse || isMove) && loc.y < menuBarThreshold {
            return Unmanaged.passRetained(event)
        }

        // ── Full path: Wardlume window whitelist (action events only) ─────────
        // Lets events through if they land inside a Wardlume-owned window that
        // is NOT the ward overlay. This covers:
        //   • The NSMenu dropdown panel ("Deactivate Ward", "Quit")
        //   • NSAlert dialogs
        //   • Any future settings windows
        //
        // CGWindowListCopyWindowInfo returns windows in z-order (front → back).
        // Wardlume already has Screen Recording permission (Phase 1c), which
        // satisfies the TCC requirement for this API.
        //
        // NSApp.windows cannot be used here because NSApplication.windows is
        // @MainActor-isolated; accessing it from a nonisolated function is a
        // Swift 6 compile error even though we're actually on the main thread.
        //
        // CRITICAL FIX: The ward overlay window is full-screen, so it will always
        // be the first window in z-order that contains any click location. We must
        // continue checking ALL Wardlume windows at the click location, not break
        // after finding the first one. If we find a non-ward Wardlume window
        // (e.g., the menu dropdown), whitelist it. Only break when we find a
        // non-Wardlume window.
        if isMouse {
            let windowList = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID) as? [[String: Any]] ?? []

            for info in windowList {
                guard
                    let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                    let pid    = info[kCGWindowOwnerPID as String] as? Int32,
                    let wid    = info[kCGWindowNumber as String] as? CGWindowID
                else { continue }

                // kCGWindowBounds values are in Quartz coordinates — same system
                // as event.location — so no y-flip is needed here.
                let quartzRect = CGRect(
                    x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0,
                    width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)

                guard quartzRect.contains(loc) else { continue }

                // Found a window at this screen position.
                if pid == wardlumePID {
                    // This is a Wardlume window.
                    if wid != wardWindowID {
                        // It's NOT the ward overlay (e.g., menu dropdown, alert).
                        // Whitelist it — let the event through.
                        return Unmanaged.passRetained(event)
                    }
                    // It IS the ward overlay. Continue checking — there might be
                    // another Wardlume window (like a menu dropdown) underneath.
                    continue
                } else {
                    // This is NOT a Wardlume window. The click landed on another
                    // app's window or the desktop. Stop searching — consume.
                    break
                }
            }
        }

        // ── Step 4: Intrusion pulse + consume ─────────────────────────────────
        // Event failed all whitelist checks — it lands on the locked desktop.
        // Fire the debounced visual pulse (max once per 500 ms) and discard.
        let now = CACurrentMediaTime()
        if now - lastIntrusionWall > 0.5, let v = metalView {
            lastIntrusionWall = now
            v.intrusionTime = v.params.time
        }

        return nil   // consume — event is silently discarded
    }
}
