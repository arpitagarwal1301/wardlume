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
    /// Phase 4b routing logic (with user-override resolution chain):
    ///   1. If resolved reaction image exists (user override OR pack bundle):
    ///      → ImageReactionView in image mode
    ///   2. Else if pack.style == .minimal:
    ///      → MinimalReactionView (text overlay)
    ///   3. Else (image-style pack with no resolved image):
    ///      → ImageReactionView in placeholder mode
    ///
    /// This preserves silentProfessional's minimal text overlay when no user
    /// override is present, while allowing user overrides to apply globally
    /// to any pack (including minimal-style packs).
    static func make(pack: ReactionPack, frame: CGRect) -> NSView {
        // Phase 4b: resolve reaction image via user-override chain
        let resolvedReactionURL = ReactionPack.resolvedReactionImageURL(for: pack)
        
        if let url = resolvedReactionURL, let image = NSImage(contentsOf: url) {
            // Path 1: user override OR pack's bundled reaction image exists
            return ImageReactionView(pack: pack, image: image, frame: frame)
            
        } else if pack.style == .minimal {
            // Path 2: no image available, but pack is minimal-style — render text overlay
            return MinimalReactionView(pack: pack, frame: frame)
            
        } else {
            // Path 3: image-style pack with no resolved image — show placeholder
            // This is the expected Phase 4a state for grumpyOldMan/wizard until
            // real assets are added to the bundle or user uploads an override.
            print("Wardlume [ReactionOverlayView]: pack '\(pack.id)' reaction image asset missing — using placeholder")
            return ImageReactionView(pack: pack, image: nil, frame: frame)
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: — MinimalReactionView  (Silent Professional)
// ---------------------------------------------------------------------------

/// Pure-code reaction view. No asset files required — always renders correctly.
///
/// Visual: near-black textured background (subtle crosshatch grid) + centred
/// lock-pill containing a lock.fill icon and "Input locked" at 28pt semibold.
/// Quiet authority — the locked state reads instantly without alarm aesthetics.
final class MinimalReactionView: NSView {

    private let pack: ReactionPack

    init(pack: ReactionPack, frame: CGRect) {
        self.pack = pack
        super.init(frame: frame)

        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.0, alpha: 0.15).cgColor  // semi-transparent dark overlay; crosshatch drawn in draw(_:)

        // ── Lock pill — centred on screen ─────────────────────────────────────
        // 300 × 80 pt — prominent but proportional to the hint pill below.
        let pillW: CGFloat = 300
        let pillH: CGFloat = 80
        let pill = NSView(frame: CGRect(
            x:      (frame.width  - pillW) / 2,
            y:      (frame.height - pillH) / 2,
            width:  pillW,
            height: pillH))
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor(white: 0.18, alpha: 0.88).cgColor
        pill.layer?.cornerRadius    = 20
        pill.layer?.borderWidth     = 1
        pill.layer?.borderColor     = NSColor.white.withAlphaComponent(0.22).cgColor
        addSubview(pill)

        // lock.fill icon — 28pt SF Symbol, white, left side of pill.
        let iconPadL: CGFloat = 20
        let iconSize: CGFloat = 32
        let config = NSImage.SymbolConfiguration(pointSize: 28, weight: .regular)
        if let symbol = NSImage(systemSymbolName: "lock.fill",
                                accessibilityDescription: "Screen locked")?
                           .withSymbolConfiguration(config) {
            let iv = NSImageView(frame: CGRect(
                x:      iconPadL,
                y:      (pillH - iconSize) / 2,
                width:  iconSize,
                height: iconSize))
            iv.image            = symbol
            iv.imageScaling     = .scaleProportionallyDown
            iv.contentTintColor = .white
            pill.addSubview(iv)
        }

        // "Input locked" — 36pt semibold, white. Fixed frame avoids sizeToFit()
        // layout recursion (see file header note). Height 44 fits 36pt comfortably.
        let textX: CGFloat  = iconPadL + iconSize + 12
        let textH: CGFloat  = 44
        let label = NSTextField(labelWithString: "Input locked")
        label.font            = NSFont.systemFont(ofSize: 36, weight: .semibold)
        label.textColor       = .white
        label.isBezeled       = false
        label.drawsBackground = false
        label.isEditable      = false
        label.isSelectable    = false
        label.alignment       = .left
        label.frame = CGRect(
            x:      textX,
            y:      (pillH - textH) / 2,
            width:  pillW - textX - 12,
            height: textH)
        pill.addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    /// Crosshatch grid texture — 32 pt spacing, 0.75 pt stroke, 7% white.
    /// Drawn into the layer backing store on top of the near-black background.
    /// Self-contained: no dependency on window opacity or compositor order.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let spacing: CGFloat = 32
        NSColor.white.withAlphaComponent(0.07).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 0.75

        var y: CGFloat = 0
        while y <= bounds.height {
            path.move(to: CGPoint(x: 0,            y: y))
            path.line(to: CGPoint(x: bounds.width, y: y))
            y += spacing
        }
        var x: CGFloat = 0
        while x <= bounds.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.line(to: CGPoint(x: x, y: bounds.height))
            x += spacing
        }
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
