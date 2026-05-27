//  ReactionPack.swift
//  Wardlume
//
//  Phase 2.5b: Pack definitions extracted from ReactionManager.
//  Phase 3a:   Added imageURL/audioURL instance properties (Option A);
//              all → computed var combining builtIn + user packs;
//              static URL helpers deleted (2 call sites updated in their files).
//
//  ── Built-in pack asset convention ──────────────────────────────────────────
//
//  Built-in image/audio URLs are resolved from Bundle.main once at static
//  initialisation time, stored on the instance, and remain nil until the
//  asset files are dropped into the Xcode blue folder reference at:
//    Bundle.main / Reactions / Packs / <pack.id> / image.png
//    Bundle.main / Reactions / Packs / <pack.id> / audio.mp3
//
//  User pack URLs are resolved from the filesystem at load time by PackLoader
//  and stored directly on the ReactionPack instance — no Bundle.main lookup.
//
//  ── Adding a built-in pack ───────────────────────────────────────────────────
//    1. Add a static instance in extension ReactionPack (Built-in packs) below.
//    2. Append it to `builtIn`.
//    3. For .image packs: drop image.png (and optionally audio.mp3) into
//       Wardlume/Reactions/Packs/<yourPackID>/ in Finder. No Xcode changes
//       needed — the folder is a blue folder reference.
//
//  ── Adding a user pack ──────────────────────────────────────────────────────
//    See PackLoader.swift and the .wardpack format documentation (Phase 3d).

import AppKit

// ---------------------------------------------------------------------------
// MARK: — PackStyle
// ---------------------------------------------------------------------------

/// Determines how the reaction overlay is rendered.
///
/// - `.image`:   Loads an image from the resolved imageURL; falls back to
///               `placeholderText` on `backgroundColor` when URL is nil.
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
/// All fields are read at overlay-construction time. Pack instances are
/// immutable — mutating a pack after ReactionManager has resolved it for a
/// trigger() call has no effect on the already-shown overlay.
///
/// Asset URLs are resolved at construction time:
///   • Built-in packs: Bundle.main lookup (nil until asset files are added)
///   • User packs: absolute filesystem URL resolved by PackLoader at launch
///   • User overrides: filesystem URL from UserAssetManager (Phase 4a)
struct ReactionPack {

    /// Stable identifier.
    ///   • Built-in packs: short camelCase string (e.g. "silentProfessional")
    ///   • User packs: reverse-DNS recommended (e.g. "com.yourname.packname")
    /// Used as lookup key in ReactionManager.activePackID and as the bundle
    /// subdirectory name for built-in assets.
    let id: String

    /// User-visible name shown in the Preferences picker.
    let name: String

    /// How long the overlay stays on screen before auto-dismissal.
    let duration: TimeInterval

    /// Background colour used when baseImageURL is nil (all image packs until
    /// real assets are added) or as the permanent background for .minimal packs.
    let backgroundColor: NSColor

    /// Base name of the base image file inside the pack's bundle subdirectory.
    /// The base image is shown continuously while the ward is active.
    /// Nil for packs that never show a base image (e.g. Silent Professional).
    /// For built-in packs only — the resolved URL is stored in baseImageURL.
    /// For user packs this holds the baseImageFile value from the manifest.
    let baseImageBundleName: String?

    /// Base name of the reaction image file inside the pack's bundle subdirectory.
    /// The reaction image swaps in on intrusion, then swaps back to base.
    /// Nil for packs that never show a reaction image (e.g. Silent Professional).
    /// For built-in packs only — the resolved URL is stored in reactionImageURL.
    /// For user packs this holds the reactionImageFile value from the manifest.
    let reactionImageBundleName: String?

    /// Base name of the audio file inside the pack's bundle subdirectory.
    /// Nil for packs that are always silent.
    let audioBundleName: String?

    /// Text shown when baseImageURL is nil (image style) or as the primary
    /// label (minimal style).
    let placeholderText: String

    /// Resolved URL for the base image asset, set once at construction time.
    ///   • Built-in packs: Bundle.main lookup → nil until asset is in bundle
    ///   • User packs: absolute filesystem URL from PackLoader
    ///   • Packs with no base image by design (e.g. Silent Professional): always nil
    ///
    /// Resolution chain at runtime (Phase 4b):
    ///   user override → bundled base → Metal shader fallback
    let baseImageURL: URL?

    /// Resolved URL for the reaction image asset, set once at construction time.
    ///   • Built-in packs: Bundle.main lookup → nil until asset is in bundle
    ///   • User packs: absolute filesystem URL from PackLoader
    ///   • Packs with no reaction image by design (e.g. Silent Professional): always nil
    ///
    /// Resolution chain at runtime (Phase 4b):
    ///   user override → bundled reaction → if minimal-style pack, render text overlay → else no swap
    let reactionImageURL: URL?

    /// Resolved URL for the audio asset, set once at construction time.
    /// Same resolution strategy as baseImageURL and reactionImageURL.
    /// nil means no audio for this pack (silent by design or asset absent).
    let audioURL: URL?

    /// Rendering strategy for the content view. See PackStyle docs.
    let style: PackStyle
}

// ---------------------------------------------------------------------------
// MARK: — Built-in packs
// ---------------------------------------------------------------------------

extension ReactionPack {

    // ── Grumpy Old Man ────────────────────────────────────────────────────────
    /// Image pack. Assets: Reactions/Packs/grumpyOldMan/baseImage.png,
    /// reactionImage.png, audio.mp3.
    /// Phase 4a state: no assets in bundle → baseImageURL/reactionImageURL/audioURL
    /// all nil → overlay renders gray bg + "GRUMPY OLD MAN" placeholder text.
    static let grumpyOldMan = ReactionPack(
        id:                      "grumpyOldMan",
        name:                    "Grumpy Old Man",
        duration:                2.0,
        backgroundColor:         NSColor(red: 0.4, green: 0.4, blue: 0.42, alpha: 1.0),
        baseImageBundleName:     "baseImage",
        reactionImageBundleName: "reactionImage",
        audioBundleName:         "audio",
        placeholderText:         "GRUMPY OLD MAN",
        baseImageURL:            Bundle.main.url(forResource: "baseImage",
                                                 withExtension: "png",
                                                 subdirectory: "Reactions/Packs/grumpyOldMan"),
        reactionImageURL:        Bundle.main.url(forResource: "reactionImage",
                                                 withExtension: "png",
                                                 subdirectory: "Reactions/Packs/grumpyOldMan"),
        audioURL:                Bundle.main.url(forResource: "audio",
                                                 withExtension: "mp3",
                                                 subdirectory: "Reactions/Packs/grumpyOldMan"),
        style:                   .image
    )

    // ── Wizard ────────────────────────────────────────────────────────────────
    /// Image pack. Assets: Reactions/Packs/wizard/baseImage.png,
    /// reactionImage.png, audio.mp3.
    /// Phase 4a state: no assets in bundle → baseImageURL/reactionImageURL/audioURL
    /// all nil → overlay renders dark purple bg + "WIZARD" placeholder text.
    static let wizard = ReactionPack(
        id:                      "wizard",
        name:                    "Wizard",
        duration:                2.5,
        backgroundColor:         NSColor(red: 0.2, green: 0.1, blue: 0.3, alpha: 1.0),
        baseImageBundleName:     "baseImage",
        reactionImageBundleName: "reactionImage",
        audioBundleName:         "audio",
        placeholderText:         "WIZARD",
        baseImageURL:            Bundle.main.url(forResource: "baseImage",
                                                 withExtension: "png",
                                                 subdirectory: "Reactions/Packs/wizard"),
        reactionImageURL:        Bundle.main.url(forResource: "reactionImage",
                                                 withExtension: "png",
                                                 subdirectory: "Reactions/Packs/wizard"),
        audioURL:                Bundle.main.url(forResource: "audio",
                                                 withExtension: "mp3",
                                                 subdirectory: "Reactions/Packs/wizard"),
        style:                   .image
    )

    // ── Silent Professional ───────────────────────────────────────────────────
    /// Minimal pack. Fully implemented in code — no asset files ever needed.
    /// Renders: near-black background + 6pt red border frame + "ACCESS DENIED".
    /// This is the default pack and the safe fallback for unknown activePackIDs.
    static let silentProfessional = ReactionPack(
        id:                      "silentProfessional",
        name:                    "Silent Professional",
        duration:                0.6,
        backgroundColor:         NSColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1.0),
        baseImageBundleName:     nil,
        reactionImageBundleName: nil,
        audioBundleName:         nil,
        placeholderText:         "ACCESS DENIED",
        baseImageURL:            nil,    // minimal style — never needs an image
        reactionImageURL:        nil,    // minimal style — never needs an image
        audioURL:                nil,    // minimal style — always silent
        style:                   .minimal
    )

    // ── Pack lists ────────────────────────────────────────────────────────────

    /// Built-in packs only. Used by PackLoader for ID collision checks to avoid
    /// a circular dependency: ReactionPack.all calls PackLoader.shared.userPacks,
    /// so PackLoader must not call .all during loading — it uses .builtIn instead.
    static let builtIn: [ReactionPack] = [
        .silentProfessional,
        .grumpyOldMan,
        .wizard,
    ]

    /// All packs available in this session: built-ins first, then user packs
    /// discovered by PackLoader at launch.
    ///
    /// Computed so that user packs populated by PackLoader.shared.discoverUserPacks()
    /// are automatically included after launch. Consumers (ReactionManager,
    /// PreferencesView) call this and always get the full list.
    ///
    /// Thread safety: discoverUserPacks() runs once on the main thread at launch;
    /// all consumers also run on the main thread. Safe for current usage.
    static var all: [ReactionPack] { builtIn + PackLoader.shared.userPacks }
}

// ---------------------------------------------------------------------------
// MARK: — Static URL helpers (deleted in Phase 3a)
// ---------------------------------------------------------------------------
//
// The static imageURL(for:) and audioURL(for:) helpers that previously lived
// here have been removed. Their two call sites are updated to read the instance
// properties directly:
//
//   ReactionOverlayView.make()    →  pack.reactionImageURL (renamed in Phase 4a)
//   ReactionManager.playAudio()   →  pack.audioURL
//
// This is Option A from the Phase 3a plan: pack instances are self-contained
// with resolved URLs set at construction time. No lazy helper indirection.
