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
import CoreGraphics
import AVFoundation
import Combine

// ---------------------------------------------------------------------------
// MARK: — ReactionManager
// ---------------------------------------------------------------------------

/// Owns the full lifecycle of punitive reaction overlays.
///
/// Usage:
///   1. Instantiate once in AppDelegate.applicationDidFinishLaunching.
///   2. Wire InputLockManager.onIntrusion → reactionManager.trigger().
///   3. Call dismissReaction() on any ward-deactivation path.
///
/// @MainActor: all reaction state (reactionWindow, reactionWindowID, lastFiredAt,
/// audioPlayer) is touched only from the main thread today — the CGEventTap
/// callback dispatches onIntrusion async to main, and the SwiftUI settings UI
/// mutates on main. Annotating the class makes that contract compiler-enforced so
/// a future off-main caller fails loudly instead of silently racing the shared
/// audioPlayer / window state read by the nonisolated tap callback.
@MainActor
final class ReactionManager: ObservableObject {

    // -------------------------------------------------------------------------
    // MARK: — Configuration (settable from Phase 2.5c settings UI)
    // -------------------------------------------------------------------------

    /// Minimum time between consecutive reactions (seconds). Default 5 s.
    /// Phase 2.5c settings will expose a 1 / 3 / 5 / 10 s picker.
    @Published var cooldown: TimeInterval = 5.0 {
        didSet {
            UserDefaults.standard.set(cooldown, forKey: "wardlume.cooldown")
        }
    }

    /// The pack that fires on the next trigger(). Default: Silent Professional —
    /// the only pack guaranteed to render without any bundle asset files.
    /// Phase 2.5c settings will persist this choice via UserDefaults.
    @Published var activePackID: String = ReactionPack.silentProfessional.id {
        didSet {
            UserDefaults.standard.set(activePackID, forKey: "wardlume.activePackID")
        }
    }

    /// When true, plays the pack's audio file (if it exists in the bundle).
    /// Default OFF — toggled by the Phase 2.5c audio toggle / debug menu item.
    @Published var audioEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(audioEnabled, forKey: "wardlume.audioEnabled")
            // Requirement 4.8: Stop audio immediately when toggle is disabled
            if !audioEnabled {
                audioPlayer?.stop()
                audioPlayer = nil
            }
        }
    }

    /// Phase 4b: The currently active pack, resolved from activePackID.
    /// Falls back to Silent Professional if activePackID is invalid.
    /// Used by AppDelegate to resolve the base image at ward activation time.
    var activePack: ReactionPack {
        ReactionPack.all.first(where: { $0.id == activePackID }) ?? .silentProfessional
    }

    // -------------------------------------------------------------------------
    // MARK: — Private state
    // -------------------------------------------------------------------------

    /// Valid cooldown values for segmented control (Requirement 5.8)
    static let validCooldowns: [Double] = [1.0, 3.0, 5.0, 10.0]

    /// Timestamp of the last successfully fired reaction.
    /// Compared against Date() to enforce the cooldown.
    private var lastFiredAt: Date = .distantPast

    /// Currently visible reaction overlay window, if any.
    private var reactionWindow: NSWindow?

    /// Scheduled task to auto-dismiss the current reaction.
    /// Retained so we can cancel it if dismissReaction() is called early.
    private var dismissWorkItem: DispatchWorkItem?

    /// Held strongly for the duration of audio playback. AVAudioPlayer is
    /// deallocated as soon as its last strong reference drops — without this
    /// property the player would stop mid-clip when showReaction() returns.
    /// Nilled out in tearDownReactionWindow() to stop audio on early dismiss.
    private var audioPlayer: AVAudioPlayer?

    /// Set by AppDelegate at wire-up time. Used to inform the input lock
    /// which reaction window is currently on screen so it can be consumed
    /// rather than whitelisted.
    weak var inputLockManager: InputLockManager?

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
    // MARK: — Initialization
    // -------------------------------------------------------------------------

    /// Returns the closest valid cooldown value to the given value.
    ///
    /// Valid cooldowns are 1.0, 3.0, 5.0, and 10.0 seconds. This method finds
    /// the value with the minimum absolute difference from the input.
    private static func closestValidCooldown(_ value: Double) -> Double {
        return validCooldowns.min(by: { abs($0 - value) < abs($1 - value) }) ?? 5.0
    }

    /// Initialize ReactionManager with settings restored from UserDefaults.
    ///
    /// Settings are validated and reset to defaults if corrupted or invalid:
    /// - activePackID: Must exist in ReactionPack.all, defaults to silentProfessional
    /// - audioEnabled: Defaults to false if not set
    /// - cooldown: Must be > 0, snapped to closest valid value (1.0, 3.0, 5.0, 10.0)
    init() {
        // Restore activePackID with validation
        if let savedPackID = UserDefaults.standard.string(forKey: "wardlume.activePackID") {
            if ReactionPack.all.contains(where: { $0.id == savedPackID }) {
                self.activePackID = savedPackID
            } else {
                print("Wardlume [ReactionManager]: Invalid saved pack ID '\(savedPackID)', defaulting to silentProfessional")
                self.activePackID = ReactionPack.silentProfessional.id
            }
        }
        
        // Restore audioEnabled (default false if not set)
        self.audioEnabled = UserDefaults.standard.bool(forKey: "wardlume.audioEnabled")
        
        // Restore cooldown with closest-valid-value logic (Requirement 5.8)
        let savedCooldown = UserDefaults.standard.double(forKey: "wardlume.cooldown")
        if savedCooldown > 0 {
            let snapped = Self.closestValidCooldown(savedCooldown)
            // Migration guard: any stale value above 5 s (e.g. old default of 10 s)
            // is capped back to 5 s and persisted so it does not re-appear on relaunch.
            if snapped > 5.0 {
                self.cooldown = 5.0
                UserDefaults.standard.set(5.0, forKey: "wardlume.cooldown")
            } else {
                self.cooldown = snapped
            }
        } else {
            self.cooldown = 5.0
        }
    }

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
        // Falls back to Silent Professional on unknown ID — it is the only pack
        // guaranteed to render without any asset files in the bundle.
        let pack = ReactionPack.all.first(where: { $0.id == activePackID })
                   ?? .silentProfessional

        lastFiredAt = now

        print(String(format: "Wardlume [ReactionManager]: triggered pack='%@' " +
                     "(cooldown remaining: 0.0s)", pack.id))

        showReaction(pack: pack)
    }

    /// Trigger a reaction for preview purposes in the settings UI.
    ///
    /// Unlike trigger(), this method:
    /// - Does NOT check cooldown (allows rapid consecutive previews)
    /// - Does NOT update lastFiredAt (preview doesn't consume cooldown budget)
    /// - Works even when ward is inactive
    ///
    /// Must be called on the main thread.
    func triggerForPreview() {
        let pack = ReactionPack.all.first(where: { $0.id == activePackID })
                   ?? .silentProfessional
        
        print("Wardlume [ReactionManager]: preview triggered for pack='\(pack.id)'")
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
        // Above the ward overlay (which sits at CGShieldingWindowLevel) so the
        // reaction image is visible, not drawn behind the ward.
        window.level                = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        
        // Dynamically set opacity based on pack style to let the Metal shader show through in minimal mode
        if pack.style == .minimal {
            window.isOpaque         = false
            window.backgroundColor  = .clear
        } else {
            window.isOpaque         = true
            window.backgroundColor  = .black
        }
        window.hasShadow            = false
        window.ignoresMouseEvents   = true   // pass-through so Cmd+Shift+W still reaches the tap

        // ── Content view ──────────────────────────────────────────────────────
        // ReactionOverlayView.make() routes to the correct rendering path:
        //   .minimal            → MinimalReactionView (no asset lookup)
        //   .image + file found → ImageReactionView   (real image)
        //   .image + file missing → ImageReactionView (placeholder + log)
        window.contentView = ReactionOverlayView.make(pack: pack, frame: screenFrame)

        // Register the reaction window ID with InputLockManager BEFORE the window
        // is shown, so the tap treats it as consume-not-whitelist from the very
        // first frame it can appear on screen. Registering after makeKeyAndOrderFront
        // would leave a gap where the full-screen window is topmost but its ID is
        // not yet known, and a click in that gap could leak through the whitelist.
        let wid = CGWindowID(window.windowNumber)
        inputLockManager?.reactionWindowID = wid
        reactionWindow = window

        window.makeKeyAndOrderFront(nil)

        print("Wardlume [ReactionManager]: reaction window on screen (CGWindowID=\(wid))")

        // ── Audio ─────────────────────────────────────────────────────────────
        // Gated on audioEnabled so the default (OFF) never touches the file
        // system. When ON and the file is absent, playAudio() silently no-ops.
        if audioEnabled {
            playAudio(for: pack)
        }

        // ── Auto-dismiss ──────────────────────────────────────────────────────
        let workItem = DispatchWorkItem { [weak self] in
            self?.tearDownReactionWindow()
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + pack.duration, execute: workItem)
    }

    private func tearDownReactionWindow() {
        guard let window = reactionWindow else { return }
        // Stop any in-progress audio so it doesn't outlive the overlay window.
        audioPlayer?.stop()
        audioPlayer = nil
        // Remove the window from screen FIRST, then clear the ID. This keeps the
        // invariant "reactionWindowID is set whenever the reaction window is on
        // screen" true even if teardown ever re-enters the run loop — symmetric
        // with the register-before-show ordering in showReaction().
        window.orderOut(nil)
        window.close()
        reactionWindow = nil
        inputLockManager?.reactionWindowID = nil
    }

    // -------------------------------------------------------------------------
    // MARK: — Audio
    // -------------------------------------------------------------------------

    /// Attempts to load and play the pack's audio asset.
    ///
    /// Phase 4b: Uses the resolution chain (user override → pack bundle → silent).
    /// Silent no-op when no audio URL is resolved. No log emitted on missing audio
    /// because audio is optional by design even for image packs.
    private func playAudio(for pack: ReactionPack) {
        guard let url = ReactionPack.resolvedAudioURL(for: pack) else { return }
        audioPlayer = try? AVAudioPlayer(contentsOf: url)
        audioPlayer?.play()
    }
}
