//  ReactionManager.swift
//  Wardlume
//
//  Phase 2.5a: Punitive reaction engine.
//
//  ── Design rationale ────────────────────────────────────────────────────────
//
//  WHY reactions are decoupled from authentication:
//    Reactions are entirely punitive / comedic. They are shown to the *intruder*
//    to deter or amuse. They carry no authentication semantics — they never prompt
//    for a password, Touch ID, or any credential. Mixing auth logic with reaction
//    logic would risk accidentally bypassing or confusing the unlock state machine
//    built in Phases 2a–2b. Keeping ReactionManager orthogonal to
//    BiometricUnlockManager and AppDelegate's unlock paths means either subsystem
//    can change independently.
//
//  WHY the cooldown is separate from the border-pulse debounce in InputLockManager:
//    The border pulse (500 ms debounce in InputLockManager.lastIntrusionWall) is
//    a *shader feedback* mechanism — it exists so the ward owner sees a clear visual
//    acknowledgment without the shader flickering on every repeated keypress.
//    The reaction cooldown (default 5 s here) is a *user-experience gate* — reactions
//    are heavyweight (full-screen overlay, optional audio) and should not fire more
//    than once every few seconds. These two rates serve different purposes and must
//    remain independently tunable. Sharing the debounce clock would let a change to
//    one subsystem silently break the other.
//
//  WHY reactions live in their own NSWindow:
//    The ward overlay is a Metal-backed NSWindow at level .screenSaver. Compositing
//    a separate UI layer on top of a Metal surface mid-frame is non-trivial and risks
//    shader glitches. A second NSWindow at .screenSaver + 1 sits above the Metal
//    window in the compositor's z-order without touching the shader at all. This also
//    makes the reaction layer trivially dismissible (orderOut + close) without
//    affecting the ward's rendering pipeline. The reaction window is added to the
//    InputLockManager whitelist so the event tap does not fight with it.
//
//  ────────────────────────────────────────────────────────────────────────────

import AppKit
import SwiftUI

// ---------------------------------------------------------------------------
// MARK: — ReactionPack
// ---------------------------------------------------------------------------

/// A single themed reaction bundle.
///
/// - `id`:        Stable identifier used for persistence (Phase 2.5c settings).
/// - `name`:      Human-readable display name for the settings picker.
/// - `imageName`: Name of an image asset in Assets.xcassets (nil = no image).
/// - `audioName`: Name of a sound file in the app bundle (nil = silent).
/// - `duration`:  How long the reaction overlay stays on screen before auto-dismiss.
struct ReactionPack {
    let id:        String
    let name:      String
    let imageName: String?
    let audioName: String?
    let duration:  TimeInterval
}

// ---------------------------------------------------------------------------
// MARK: — Built-in packs
// ---------------------------------------------------------------------------

extension ReactionPack {
    /// Phase 2.5a placeholder — solid red overlay with "WARD HOLDS" text.
    /// Real image/audio packs are added in Phase 2.5b.
    static let test = ReactionPack(
        id:        "test",
        name:      "Ward Holds (placeholder)",
        imageName: nil,
        audioName: nil,
        duration:  2.0
    )

    /// All packs available to the settings picker. Extended in Phase 2.5b.
    static let all: [ReactionPack] = [.test]
}

// ---------------------------------------------------------------------------
// MARK: — ReactionManager
// ---------------------------------------------------------------------------

/// Owns the full lifecycle of punitive reaction overlays.
///
/// Usage:
///   1. Instantiate once in AppDelegate.applicationDidFinishLaunching.
///   2. Wire InputLockManager.onIntrusion → reactionManager.trigger().
///   3. Call dismissReaction() on any ward-deactivation path.
final class ReactionManager {

    // -------------------------------------------------------------------------
    // MARK: — Configuration (settable from Phase 2.5c settings UI)
    // -------------------------------------------------------------------------

    /// Minimum time between consecutive reactions (seconds). Default 5 s.
    /// Phase 2.5c settings will expose a 1 / 3 / 5 / 10 s picker.
    var cooldown: TimeInterval = 5.0

    /// The pack that fires on the next trigger(). Default: placeholder test pack.
    /// Phase 2.5c settings will persist this via UserDefaults.
    var activePackID: String = ReactionPack.test.id

    // -------------------------------------------------------------------------
    // MARK: — Private state
    // -------------------------------------------------------------------------

    /// Timestamp of the last successfully fired reaction.
    /// Compared against Date() to enforce the cooldown.
    private var lastFiredAt: Date = .distantPast

    /// Currently visible reaction overlay window, if any.
    private var reactionWindow: NSWindow?

    /// Scheduled task to auto-dismiss the current reaction.
    /// Retained so we can cancel it if dismissReaction() is called early.
    private var dismissWorkItem: DispatchWorkItem?

    // ── Intrusion attempt counter ─────────────────────────────────────────────
    //
    // Tracks how many intrusion events have fired since the last 15-second
    // idle reset. Currently unused by v1.5 logic, but preserved for:
    //   • v1.6 bait-and-switch escalation (e.g., switch pack after N attempts)
    //   • Future analytics / telemetry features
    //
    // Design: counter increments on every trigger() call regardless of cooldown.
    // The 15-second reset timer is rescheduled on every intrusion, so it only
    // fires when there has been a 15-second quiet period with no new attempts.
    //
    /// Running count of intrusion trigger() calls since the last idle reset.
    private(set) var intrusionCount: Int = 0

    /// Scheduled work item that resets intrusionCount after 15 s of no activity.
    private var counterResetWorkItem: DispatchWorkItem?

    // -------------------------------------------------------------------------
    // MARK: — Public API
    // -------------------------------------------------------------------------

    /// Attempt to fire the active reaction pack.
    ///
    /// - Silently ignored if called within `cooldown` seconds of the last fire.
    /// - Must be called on the main thread (mirrors the CGEventTap callback thread).
    func trigger() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastFiredAt)
        let remaining = cooldown - elapsed

        // ── Increment attempt counter regardless of cooldown ──────────────────
        incrementIntrusionCounter()

        // ── Cooldown gate ─────────────────────────────────────────────────────
        if elapsed < cooldown {
            print(String(format: "Wardlume [ReactionManager]: trigger ignored " +
                         "(cooldown active, %.1fs remaining)", remaining))
            return
        }

        // ── Resolve pack ──────────────────────────────────────────────────────
        let pack = ReactionPack.all.first(where: { $0.id == activePackID })
                   ?? ReactionPack.test

        lastFiredAt = now

        print(String(format: "Wardlume [ReactionManager]: triggered pack='%@' " +
                     "(cooldown remaining: 0.0s)", pack.id))

        showReaction(pack: pack)
    }

    /// Immediately dismiss any visible reaction overlay.
    ///
    /// Called by AppDelegate on every ward-deactivation path (toggleWard deactivate
    /// branch, quitApp) to ensure no stale overlay outlives the ward session.
    func dismissReaction() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        tearDownReactionWindow()
    }

    // -------------------------------------------------------------------------
    // MARK: — Intrusion counter helpers
    // -------------------------------------------------------------------------

    private func incrementIntrusionCounter() {
        intrusionCount += 1

        // Cancel any pending reset and reschedule from now.
        counterResetWorkItem?.cancel()
        let reset = DispatchWorkItem { [weak self] in
            self?.intrusionCount = 0
        }
        counterResetWorkItem = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 15.0, execute: reset)
    }

    // -------------------------------------------------------------------------
    // MARK: — Overlay window lifecycle
    // -------------------------------------------------------------------------

    private func showReaction(pack: ReactionPack) {
        // Dismiss any existing reaction first (e.g., rapid re-triggers after
        // cooldown expires while a previous long-duration overlay is still up).
        tearDownReactionWindow()

        let screenFrame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)

        // ── Reaction NSWindow ─────────────────────────────────────────────────
        // Borderless, full-screen, opaque. Level is .screenSaver + 1 so it sits
        // above the ward Metal overlay (which is at .screenSaver) in the
        // compositor z-order. This avoids touching the Metal pipeline entirely.
        let window = NSWindow(
            contentRect: screenFrame,
            styleMask:   [.borderless],
            backing:     .buffered,
            defer:       false
        )
        window.isReleasedWhenClosed = false
        window.level                = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        window.isOpaque             = true
        window.hasShadow            = false
        window.ignoresMouseEvents   = true   // pass-through so Cmd+Shift+W still reaches the tap

        // ── Content view (Phase 2.5a: placeholder) ───────────────────────────
        window.contentView = makePlaceholderView(frame: screenFrame, pack: pack)

        window.makeKeyAndOrderFront(nil)
        reactionWindow = window

        // Log the reaction window ID so InputLockManager's whitelist can be
        // extended in a future phase if needed.
        let wid = CGWindowID(window.windowNumber)
        print("Wardlume [ReactionManager]: reaction window on screen (CGWindowID=\(wid))")

        // ── Auto-dismiss ──────────────────────────────────────────────────────
        let workItem = DispatchWorkItem { [weak self] in
            self?.tearDownReactionWindow()
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + pack.duration, execute: workItem)
    }

    private func tearDownReactionWindow() {
        guard let window = reactionWindow else { return }
        window.orderOut(nil)
        window.close()
        reactionWindow = nil
    }

    // -------------------------------------------------------------------------
    // MARK: — Placeholder content view (Phase 2.5a)
    // -------------------------------------------------------------------------
    // Phase 2.5b will replace this with real image/audio assets per pack.
    // The view is intentionally AppKit-only (no SwiftUI hosting) to avoid the
    // NSHostingView → NSWindow activation dance that can steal key focus.

    private func makePlaceholderView(frame: CGRect, pack: ReactionPack) -> NSView {
        let container = NSView(frame: frame)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.red.cgColor

        let label = NSTextField(labelWithString: "WARD HOLDS")
        label.font            = NSFont.boldSystemFont(ofSize: 96)
        label.textColor       = .white
        label.isBezeled       = false
        label.drawsBackground = false
        label.isEditable      = false
        label.isSelectable    = false
        label.alignment       = .center

        // Span the full width so NSTextField's own centered alignment handles
        // horizontal positioning — avoids sizeToFit() which fires an internal
        // layoutSubtreeIfNeeded before the view is in a window hierarchy.
        // 120 pt height gives comfortable headroom for a 96 pt bold font.
        let labelHeight: CGFloat = 120
        label.frame = CGRect(
            x: 0,
            y: (frame.height - labelHeight) / 2,
            width:  frame.width,
            height: labelHeight
        )
        container.addSubview(label)
        return container
    }
}
