//  ReactionPack.swift
//  Wardlume
//
//  Phase 2.5b: Pack definitions extracted from ReactionManager.
//
//  Adding a new pack:
//    1. Add a static instance in the `extension ReactionPack` below.
//    2. Append it to `all`.
//    3. For .image packs: drop `image.png` (and optionally `audio.mp3`) into
//       Wardlume/Reactions/Packs/<yourPackID>/ in Finder. No Xcode changes
//       needed — the folder is a blue folder reference that mirrors the
//       on-disk layout verbatim into the .app bundle.
//
//  Asset path convention (enforced by imageURL/audioURL helpers below):
//    Bundle.main / Reactions / Packs / <pack.id> / image.png
//    Bundle.main / Reactions / Packs / <pack.id> / audio.mp3
//
//  When an asset is absent the overlay falls back to placeholderText on
//  backgroundColor. This is the normal Phase 2.5b state for image packs —
//  the pack architecture is designed so that swapping in real assets later
//  requires zero code changes.

import AppKit

// ---------------------------------------------------------------------------
// MARK: — PackStyle
// ---------------------------------------------------------------------------

/// Determines how the reaction overlay is rendered.
///
/// - `.image`:   Loads an image from the bundle; falls back to `placeholderText`
///               on `backgroundColor` when the asset file is missing.
/// - `.minimal`: Pure-code rendering — dark background, red border frame,
///               bold text. No asset lookup. Always works without any files.
enum PackStyle {
    case image
    case minimal
}

// ---------------------------------------------------------------------------
// MARK: — ReactionPack
// ---------------------------------------------------------------------------

/// A single themed reaction bundle.
///
/// All fields are read at overlay-construction time. Mutating a pack after
/// ReactionManager has resolved it for a trigger() call has no effect on the
/// already-shown overlay.
struct ReactionPack {
    /// Stable identifier. Used as the bundle subdirectory name for assets,
    /// as the UserDefaults key for Phase 2.5c persistence, and as the
    /// lookup key in ReactionManager.activePackID.
    let id: String

    /// User-visible name shown in the Phase 2.5c settings picker.
    let name: String

    /// How long the overlay stays on screen before auto-dismissal.
    let duration: TimeInterval

    /// Background colour used when no image asset is present (all image packs
    /// in Phase 2.5b) or as a permanent background for .minimal packs.
    let backgroundColor: NSColor

    /// Base name of the image file inside the pack's bundle subdirectory.
    /// Use nil for packs that never show an image (e.g. Silent Professional).
    /// The file extension is always `.png` — see imageURL(for:).
    let imageBundleName: String?

    /// Base name of the audio file inside the pack's bundle subdirectory.
    /// Use nil for packs that are always silent.
    /// The file extension is always `.mp3` — see audioURL(for:).
    let audioBundleName: String?

    /// Text shown when the image asset is missing or when style == .minimal.
    /// Chosen to be readable and thematically appropriate for each pack.
    let placeholderText: String

    /// Rendering strategy for the content view. See PackStyle docs.
    let style: PackStyle
}

// ---------------------------------------------------------------------------
// MARK: — Built-in packs
// ---------------------------------------------------------------------------

extension ReactionPack {

    // ── Grumpy Old Man ────────────────────────────────────────────────────────
    /// Image pack. Assets: Reactions/Packs/grumpyOldMan/image.png + audio.mp3.
    /// Phase 2.5b state: no assets → renders gray bg + "GRUMPY OLD MAN" text.
    static let grumpyOldMan = ReactionPack(
        id:              "grumpyOldMan",
        name:            "Grumpy Old Man",
        duration:        2.0,
        backgroundColor: NSColor(red: 0.4, green: 0.4, blue: 0.42, alpha: 1.0),
        imageBundleName: "image",
        audioBundleName: "audio",
        placeholderText: "GRUMPY OLD MAN",
        style:           .image
    )

    // ── Wizard ────────────────────────────────────────────────────────────────
    /// Image pack. Assets: Reactions/Packs/wizard/image.png + audio.mp3.
    /// Phase 2.5b state: no assets → renders dark purple bg + "WIZARD" text.
    static let wizard = ReactionPack(
        id:              "wizard",
        name:            "Wizard",
        duration:        2.5,
        backgroundColor: NSColor(red: 0.2, green: 0.1, blue: 0.3, alpha: 1.0),
        imageBundleName: "image",
        audioBundleName: "audio",
        placeholderText: "WIZARD",
        style:           .image
    )

    // ── Silent Professional ───────────────────────────────────────────────────
    /// Minimal pack. Fully implemented in code — no asset files ever needed.
    /// Renders: near-black background + 6pt red border frame + "ACCESS DENIED".
    /// This is the default pack and the safe fallback for unknown activePackIDs.
    static let silentProfessional = ReactionPack(
        id:              "silentProfessional",
        name:            "Silent Professional",
        duration:        0.6,
        backgroundColor: NSColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1.0),
        imageBundleName: nil,
        audioBundleName: nil,
        placeholderText: "ACCESS DENIED",
        style:           .minimal
    )

    /// Ordered list of all built-in packs. Order determines display order
    /// in the Phase 2.5c settings picker. silentProfessional is first because
    /// it is the default and the guaranteed-working fallback.
    static let all: [ReactionPack] = [
        .silentProfessional,
        .grumpyOldMan,
        .wizard,
    ]
}

// ---------------------------------------------------------------------------
// MARK: — Asset URL helpers
// ---------------------------------------------------------------------------

extension ReactionPack {

    /// Returns the bundle URL for this pack's image asset, or nil if:
    ///   • `imageBundleName` is nil (pack has no image by design), or
    ///   • the file does not exist in the bundle yet (Phase 2.5b normal state).
    ///
    /// Subdirectory: `Reactions/Packs/<pack.id>`
    /// The folder must be added to Xcode as a **blue folder reference** (not a
    /// yellow group) so the directory hierarchy is preserved in the .app bundle.
    static func imageURL(for pack: ReactionPack) -> URL? {
        guard let name = pack.imageBundleName else { return nil }
        return Bundle.main.url(
            forResource:  name,
            withExtension: "png",
            subdirectory: "Reactions/Packs/\(pack.id)"
        )
    }

    /// Returns the bundle URL for this pack's audio asset, or nil if:
    ///   • `audioBundleName` is nil (pack is always silent), or
    ///   • the file does not exist in the bundle yet.
    ///
    /// Same subdirectory convention as imageURL(for:).
    static func audioURL(for pack: ReactionPack) -> URL? {
        guard let name = pack.audioBundleName else { return nil }
        return Bundle.main.url(
            forResource:  name,
            withExtension: "mp3",
            subdirectory: "Reactions/Packs/\(pack.id)"
        )
    }
}
