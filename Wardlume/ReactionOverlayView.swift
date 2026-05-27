//  ReactionOverlayView.swift
//  Wardlume
//
//  Phase 2.5b: Pack-aware content views for reaction overlays.
//
//  Three rendering paths, chosen by the factory function make(pack:frame:):
//
//    .minimal                          → MinimalReactionView
//    .image  + image file exists       → ImageReactionView  (real image mode)
//    .image  + image file missing      → ImageReactionView  (placeholder mode)
//
//  All views are pure AppKit — no SwiftUI NSHostingView — to avoid the
//  NSHostingView → NSWindow activation handshake that can steal key focus
//  away from the CGEventTap callback chain. This is consistent with the
//  Phase 2.5a decision documented in ReactionManager.swift.
//
//  Label sizing never calls sizeToFit() to avoid the _NSDetectedLayoutRecursion
//  warning that fires when layoutSubtreeIfNeeded is called before a view is
//  attached to a window. Labels span full width; NSTextField's own text
//  alignment handles centering at draw time. See ROADMAP v1.x debug note.

import AppKit

// ---------------------------------------------------------------------------
// MARK: — Factory
// ---------------------------------------------------------------------------

enum ReactionOverlayView {

    /// Returns the appropriate NSView for `pack`, sized to `frame`.
    ///
    /// Routing logic:
    ///   - `.minimal` packs always get `MinimalReactionView` (no asset lookup).
    ///   - `.image` packs attempt to load the bundle image via
    ///     `ReactionPack.imageURL(for:)`. On success: `ImageReactionView` in
    ///     image mode. On failure (normal Phase 2.5b state): `ImageReactionView`
    ///     in placeholder mode, with a one-time console log.
    static func make(pack: ReactionPack, frame: CGRect) -> NSView {
        switch pack.style {
        case .minimal:
            return MinimalReactionView(pack: pack, frame: frame)

        case .image:
            // Attempt asset load. Missing files are the expected Phase 2.5b
            // state — contributors drop image.png here later without any code
            // changes. See ReactionPack.imageURL(for:) for the path convention.
            let image: NSImage?
            if let url = pack.imageURL {
                image = NSImage(contentsOf: url)
            } else {
                image = nil
            }

            if image == nil {
                // Log once per overlay construction so contributors can see
                // exactly which pack is still waiting for its asset file.
                print("Wardlume [ReactionManager]: pack '\(pack.id)' image asset missing — using placeholder")
            }

            return ImageReactionView(pack: pack, image: image, frame: frame)
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: — MinimalReactionView  (Silent Professional)
// ---------------------------------------------------------------------------

/// Pure-code reaction view. No asset files required — always renders correctly.
///
/// Visual: near-black background + 6pt red border inset from screen edges
///         + bold white "ACCESS DENIED" (or pack.placeholderText) centered.
///
/// The red border is drawn in draw(_:) using NSBezierPath so it is crisp at
/// all display scales without needing a separate layer or border view.
final class MinimalReactionView: NSView {

    private let pack: ReactionPack
    private let label: NSTextField

    init(pack: ReactionPack, frame: CGRect) {
        self.pack = pack

        label = NSTextField(labelWithString: pack.placeholderText)
        label.font            = NSFont.boldSystemFont(ofSize: 96)
        label.textColor       = .white
        label.isBezeled       = false
        label.drawsBackground = false
        label.isEditable      = false
        label.isSelectable    = false
        label.alignment       = .center

        super.init(frame: frame)

        wantsLayer = true
        layer?.backgroundColor = pack.backgroundColor.cgColor

        // Full-width label, fixed height — avoids sizeToFit() layout recursion.
        let labelHeight: CGFloat = 120
        label.frame = CGRect(
            x:      0,
            y:      (frame.height - labelHeight) / 2,
            width:  frame.width,
            height: labelHeight
        )
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    /// Draws the 6pt red border frame inset by the stroke half-width (3pt)
    /// so the stroke sits fully inside the view bounds.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let borderWidth: CGFloat = 6.0
        let inset = borderWidth / 2

        let borderRect = bounds.insetBy(dx: inset, dy: inset)
        let path = NSBezierPath(rect: borderRect)
        path.lineWidth = borderWidth

        NSColor(red: 0.9, green: 0.05, blue: 0.05, alpha: 1.0).setStroke()
        path.stroke()
    }
}

// ---------------------------------------------------------------------------
// MARK: — ImageReactionView  (Grumpy Old Man / Wizard)
// ---------------------------------------------------------------------------

/// Reaction view for .image packs.
///
/// Two internal modes depending on whether the asset file was found:
///
/// Image mode (asset exists):
///   Full-frame NSImageView with .scaleAxesIndependently scaling so the
///   image fills the screen regardless of aspect ratio. An optional text
///   label can be added later (empty for Phase 2.5b).
///
/// Placeholder mode (asset missing — normal Phase 2.5b state):
///   Pack's backgroundColor fills the background; placeholderText is shown
///   centered in white 96pt bold. Visually identical to the 2.5a test pack
///   but uses per-pack colours and text. When real image.png is dropped in,
///   this path is never reached again — zero code changes needed.
final class ImageReactionView: NSView {

    init(pack: ReactionPack, image: NSImage?, frame: CGRect) {
        super.init(frame: frame)

        wantsLayer = true

        if let image {
            // ── Image mode ────────────────────────────────────────────────────
            // Stretch to fill screen. scaleAxesIndependently means no letterboxing —
            // this matches typical "shock" reaction images that should fill the frame.
            layer?.backgroundColor = NSColor.black.cgColor

            let imageView = NSImageView(frame: bounds)
            imageView.image = image
            imageView.imageScaling = .scaleAxesIndependently
            imageView.imageAlignment = .alignCenter
            addSubview(imageView)

        } else {
            // ── Placeholder mode ──────────────────────────────────────────────
            // Asset not in bundle yet. Render coloured background + pack text.
            // This is the expected Phase 2.5b state for all image packs.
            // When image.png is dropped into Reactions/Packs/<id>/ and the app
            // is rebuilt, this branch is no longer taken — no code changes.
            layer?.backgroundColor = pack.backgroundColor.cgColor

            let label = NSTextField(labelWithString: pack.placeholderText)
            label.font            = NSFont.boldSystemFont(ofSize: 96)
            label.textColor       = .white
            label.isBezeled       = false
            label.drawsBackground = false
            label.isEditable      = false
            label.isSelectable    = false
            label.alignment       = .center

            // Full-width, fixed height — avoids sizeToFit() layout recursion.
            let labelHeight: CGFloat = 120
            label.frame = CGRect(
                x:      0,
                y:      (frame.height - labelHeight) / 2,
                width:  frame.width,
                height: labelHeight
            )
            addSubview(label)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }
}
