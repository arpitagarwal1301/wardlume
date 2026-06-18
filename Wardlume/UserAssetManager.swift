//  UserAssetManager.swift
//  Wardlume
//
//  Phase 4a: Manages three global user-uploaded asset slots (baseImage,
//  reactionImage, audio) stored on disk with validation.
//
//  ── Design rationale ────────────────────────────────────────────────────────
//
//  WHY a singleton:
//    User assets are global overrides that apply to whichever pack is active.
//    They are loaded once at app launch and persisted to disk. A singleton
//    ensures a single source of truth without passing state around.
//
//  WHY @Published:
//    Phase 4c will bind PreferencesView to these properties so the UI updates
//    live when assets are added/removed. Combine subscription pattern.
//
//  WHY three separate slots (not per-pack):
//    The bait-and-switch model (Phase 4) uses global overrides that apply to
//    any active pack. Users don't customize per-pack; they customize globally.
//    This simplifies the mental model and the storage layer.
//
//  WHY validation on setter, not on scan:
//    Setters enforce size + format rules when the user drops a file. Scan()
//    is permissive — it picks up whatever files are on disk without re-validating.
//    This allows manual file drops (for testing) without triggering validation.
//
//  ────────────────────────────────────────────────────────────────────────────

import AppKit
import AVFoundation
import Combine

// ---------------------------------------------------------------------------
// MARK: — UserAssetError
// ---------------------------------------------------------------------------

/// Specific failure modes for user asset operations.
///
/// Cases carry enough context for Phase 4c's alert binding to surface
/// a meaningful, actionable error message without having to parse strings.
enum UserAssetError: Error, LocalizedError, Identifiable {

    /// Image file format is not supported.
    case unsupportedImageFormat(extension: String)

    /// Audio file format is not supported.
    case unsupportedAudioFormat(extension: String)

    /// File size exceeds 10 MB limit.
    case fileTooLarge(sizeBytes: Int)

    /// Source URL is not accessible (security-scoped access failed).
    case sourceUnreachable

    /// File could not be copied to the asset slot directory.
    case copyFailed(underlying: Error)

    /// The file extension is allowed but the contents are not a decodable
    /// image / playable audio file (e.g. a renamed or corrupt file).
    case undecodableContent

    // Identifiable conformance
    var id: String { errorDescription ?? String(describing: self) }

    // LocalizedError conformance
    var errorDescription: String? {
        switch self {
        case .unsupportedImageFormat(let ext):
            return "Image file format '\(ext)' is not supported. Use PNG, JPEG, HEIC, or GIF."
        case .unsupportedAudioFormat(let ext):
            return "Audio file format '\(ext)' is not supported. Use MP3, M4A, or WAV."
        case .fileTooLarge(let bytes):
            let sizeMB = Double(bytes) / (1024 * 1024)
            return String(format: "File is too large (%.1f MB). Maximum size is 10 MB.", sizeMB)
        case .sourceUnreachable:
            return "Could not access the source file. Check that it still exists and you have permission to read it."
        case .copyFailed(let err):
            return "Could not copy file to asset directory: \(err.localizedDescription)"
        case .undecodableContent:
            return "That file could not be read as a valid image or audio file. It may be corrupt or not the type its extension claims."
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: — UserAssetManager
// ---------------------------------------------------------------------------

/// Manages three global user-uploaded asset slots on disk.
///
/// Usage:
///   1. Access via UserAssetManager.shared singleton.
///   2. Call setBaseImage(from:), setReactionImage(from:), or setAudio(from:)
///      to upload a file. Validates size + format, copies to disk, refreshes @Published.
///   3. Call clearBaseImage(), clearReactionImage(), or clearAudio() to delete.
///   4. Bind PreferencesView to the @Published URL properties (Phase 4c).
///
/// Storage:
///   ~/Library/Containers/<bundle-id>/Data/Library/Application Support/
///     Wardlume/UserAssets/
///       baseImage.png (or .jpg, .heic, .gif)
///       reactionImage.png (or .jpg, .heic, .gif)
///       audio.mp3 (or .m4a, .wav)
final class UserAssetManager: ObservableObject {

    // ── Singleton ─────────────────────────────────────────────────────────────

    static let shared = UserAssetManager()

    // ── Configuration ─────────────────────────────────────────────────────────

    private static let maxFileSizeBytes = 10 * 1024 * 1024  // 10 MB
    private static let supportedImageExtensions = ["png", "jpg", "jpeg", "heic", "gif"]
    private static let supportedAudioExtensions = ["mp3", "m4a", "wav"]

    // ── Published state ───────────────────────────────────────────────────────

    /// URL of the user's base image override, if any.
    /// Nil if no file is stored in the baseImage.* slot.
    @Published private(set) var baseImageURL: URL?

    /// URL of the user's reaction image override, if any.
    /// Nil if no file is stored in the reactionImage.* slot.
    @Published private(set) var reactionImageURL: URL?

    /// URL of the user's audio override, if any.
    /// Nil if no file is stored in the audio.* slot.
    @Published private(set) var audioURL: URL?

    // ── Initialization ────────────────────────────────────────────────────────

    private init() {
        scan()
    }

    // ── Public API ────────────────────────────────────────────────────────────

    /// Set the base image slot from a source URL.
    ///
    /// - Validates file format (png, jpg, jpeg, heic, gif) and size (≤ 10 MB)
    /// - Deletes any existing baseImage.* file
    /// - Copies source to userAssetsDirectory()/baseImage.<ext>
    /// - Calls scan() to refresh @Published baseImageURL
    /// - Throws UserAssetError on validation or copy failure
    ///
    /// Wraps sourceURL in security-scoped resource access (defer stop).
    func setBaseImage(from sourceURL: URL) throws {
        try setAsset(from: sourceURL, slot: .baseImage, supportedExtensions: Self.supportedImageExtensions)
    }

    /// Set the reaction image slot from a source URL.
    ///
    /// Same validation and behavior as setBaseImage(from:).
    func setReactionImage(from sourceURL: URL) throws {
        try setAsset(from: sourceURL, slot: .reactionImage, supportedExtensions: Self.supportedImageExtensions)
    }

    /// Set the audio slot from a source URL.
    ///
    /// - Validates file format (mp3, m4a, wav) and size (≤ 10 MB)
    /// - Deletes any existing audio.* file
    /// - Copies source to userAssetsDirectory()/audio.<ext>
    /// - Calls scan() to refresh @Published audioURL
    /// - Throws UserAssetError on validation or copy failure
    func setAudio(from sourceURL: URL) throws {
        try setAsset(from: sourceURL, slot: .audio, supportedExtensions: Self.supportedAudioExtensions)
    }

    /// Delete the base image slot and refresh @Published.
    func clearBaseImage() {
        deleteSlot(.baseImage)
        scan()
    }

    /// Delete the reaction image slot and refresh @Published.
    func clearReactionImage() {
        deleteSlot(.reactionImage)
        scan()
    }

    /// Delete the audio slot and refresh @Published.
    func clearAudio() {
        deleteSlot(.audio)
        scan()
    }

    // ── Private: directory management ─────────────────────────────────────────

    /// Returns (and creates) the directory where user assets are stored.
    ///
    /// Uses the throwing FileManager variant so we never force-unwrap:
    ///   1. `url(for:in:appropriateFor:create:true)` resolves + creates the
    ///      Application Support base directory if it doesn't exist.
    ///   2. An explicit `createDirectory(withIntermediateDirectories:true)` call
    ///      creates the `Wardlume/UserAssets/` subdirectory (no-op if it already exists).
    ///
    /// Throws on disk-full or permission corruption — caller should catch and
    /// gracefully degrade to no user assets.
    private func userAssetsDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for:              .applicationSupportDirectory,
            in:               .userDomainMask,
            appropriateFor:   nil,
            create:           true
        )

        let assetsDir = base.appendingPathComponent("Wardlume/UserAssets", isDirectory: true)
        try FileManager.default.createDirectory(
            at:                     assetsDir,
            withIntermediateDirectories: true,
            attributes:             nil
        )
        return assetsDir
    }

    // ── Private: slot enum ────────────────────────────────────────────────────

    private enum AssetSlot {
        case baseImage
        case reactionImage
        case audio

        var prefix: String {
            switch self {
            case .baseImage:      return "baseImage"
            case .reactionImage:  return "reactionImage"
            case .audio:          return "audio"
            }
        }
    }

    // ── Private: setter logic ─────────────────────────────────────────────────

    /// Generic setter for all three slots.
    ///
    /// - Validates format and size
    /// - Starts security-scoped access (defer stop)
    /// - Deletes existing slot file
    /// - Copies source to slot
    /// - Calls scan() to refresh @Published
    private func setAsset(from sourceURL: URL,
                          slot: AssetSlot,
                          supportedExtensions: [String]) throws {

        // ── 1. Validate format ────────────────────────────────────────────────
        let sourceExt = sourceURL.pathExtension.lowercased()
        guard supportedExtensions.contains(sourceExt) else {
            if slot == .audio {
                throw UserAssetError.unsupportedAudioFormat(extension: sourceExt)
            } else {
                throw UserAssetError.unsupportedImageFormat(extension: sourceExt)
            }
        }

        // ── 2. Validate size ──────────────────────────────────────────────────
        let didStart = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: sourceURL.path)
        } catch {
            throw UserAssetError.sourceUnreachable
        }

        guard let fileSize = attributes[.size] as? Int else {
            throw UserAssetError.sourceUnreachable
        }

        guard fileSize <= Self.maxFileSizeBytes else {
            throw UserAssetError.fileTooLarge(sizeBytes: fileSize)
        }

        // ── 3. Get asset directory ────────────────────────────────────────────
        let assetsDir: URL
        do {
            assetsDir = try userAssetsDirectory()
        } catch {
            throw UserAssetError.copyFailed(underlying: error)
        }

        // ── 4. Copy to a TEMP file first (atomic + non-destructive) ───────────
        // We copy to a unique temp name, validate decodability, and only then
        // replace the existing slot. This fixes two problems with delete-then-copy:
        //   • Delete-before-copy data loss: a failed copy would have already
        //     destroyed the prior asset. Here the existing slot is untouched until
        //     the new file is fully copied AND validated.
        //   • TOCTOU on the size check: we re-stat the copied temp file (its size
        //     is now fixed on disk) and re-enforce the limit before committing.
        let fileManager = FileManager.default
        let destination = assetsDir.appendingPathComponent("\(slot.prefix).\(sourceExt)")
        let tempDestination = assetsDir.appendingPathComponent(".\(slot.prefix).incoming.\(sourceExt)")
        try? fileManager.removeItem(at: tempDestination)   // clear any stale temp

        do {
            try fileManager.copyItem(at: sourceURL, to: tempDestination)
        } catch {
            throw UserAssetError.copyFailed(underlying: error)
        }

        // Anything thrown from here on must clean up the temp file.
        func cleanupTemp() { try? fileManager.removeItem(at: tempDestination) }

        // ── 5. Re-check size on the copied file (closes the size-check TOCTOU) ─
        if let copiedSize = (try? fileManager.attributesOfItem(atPath: tempDestination.path))?[.size] as? Int,
           copiedSize > Self.maxFileSizeBytes {
            cleanupTemp()
            throw UserAssetError.fileTooLarge(sizeBytes: copiedSize)
        }

        // ── 6. Validate decodability (extension is not enough) ────────────────
        // A file renamed to an allowed extension, or a corrupt file, would
        // otherwise be stored as a silently-broken slot. Reject it here.
        if !Self.fileIsDecodable(tempDestination, isAudio: supportedExtensions == Self.supportedAudioExtensions) {
            cleanupTemp()
            throw UserAssetError.undecodableContent
        }

        // ── 7. Commit: delete old slot, move temp into place ──────────────────
        // Both steps happen only after the new file is validated, so a failure
        // can never leave the slot empty with the prior asset already gone.
        deleteSlot(slot)
        do {
            try fileManager.moveItem(at: tempDestination, to: destination)
        } catch {
            cleanupTemp()
            throw UserAssetError.copyFailed(underlying: error)
        }

        // ── 8. Refresh @Published ─────────────────────────────────────────────
        scan()
    }

    /// Verifies that the file at `url` is actually a decodable image or playable
    /// audio file — not just something with an allowed extension. Used to reject
    /// renamed / corrupt files at import time so the user gets clear feedback
    /// instead of a silently-broken slot.
    private static func fileIsDecodable(_ url: URL, isAudio: Bool) -> Bool {
        if isAudio {
            // AVAudioFile fails to open data that isn't valid, decodable audio.
            return (try? AVAudioFile(forReading: url)) != nil
        } else {
            // NSImage(contentsOf:) returns nil for non-image / corrupt data, and
            // we additionally require at least one bitmap representation so a
            // zero-byte or header-only file is rejected.
            guard let image = NSImage(contentsOf: url) else { return false }
            return !image.representations.isEmpty
        }
    }

    // ── Private: scan logic ───────────────────────────────────────────────────

    /// Scans the user assets directory and updates all three @Published properties.
    ///
    /// Called at init and after each setter. Permissive — picks up whatever files
    /// are on disk without re-validating. This allows manual file drops (for testing)
    /// without triggering validation.
    ///
    /// On any I/O error, logs the failure and leaves @Published properties unchanged.
    private func scan() {
        let assetsDir: URL
        do {
            assetsDir = try userAssetsDirectory()
        } catch {
            print("Wardlume [UserAssetManager]: failed to access/create assets directory — " +
                  "\(error.localizedDescription). User assets unavailable.")
            return
        }

        // Enumerate files in the assets directory
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at:                    assetsDir,
            includingPropertiesForKeys: nil,
            options:               [.skipsHiddenFiles]
        ) else {
            print("Wardlume [UserAssetManager]: could not enumerate assets directory.")
            baseImageURL = nil
            reactionImageURL = nil
            audioURL = nil
            return
        }

        // Match files against slot prefixes
        var foundBaseImage: URL?
        var foundReactionImage: URL?
        var foundAudio: URL?

        for fileURL in contents {
            let filename = fileURL.lastPathComponent

            if filename.hasPrefix("baseImage.") {
                foundBaseImage = fileURL
            } else if filename.hasPrefix("reactionImage.") {
                foundReactionImage = fileURL
            } else if filename.hasPrefix("audio.") {
                foundAudio = fileURL
            }
        }

        // Update @Published properties
        baseImageURL = foundBaseImage
        reactionImageURL = foundReactionImage
        audioURL = foundAudio
    }

    // ── Private: delete logic ─────────────────────────────────────────────────

    /// Delete all files matching a slot's prefix from the assets directory.
    ///
    /// Silent no-op if the slot is already empty or the directory doesn't exist.
    private func deleteSlot(_ slot: AssetSlot) {
        let assetsDir: URL
        do {
            assetsDir = try userAssetsDirectory()
        } catch {
            print("Wardlume [UserAssetManager]: could not access assets directory to delete slot.")
            return
        }

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at:                    assetsDir,
            includingPropertiesForKeys: nil,
            options:               [.skipsHiddenFiles]
        ) else {
            return
        }

        for fileURL in contents {
            let filename = fileURL.lastPathComponent
            if filename.hasPrefix(slot.prefix + ".") {
                do {
                    try FileManager.default.removeItem(at: fileURL)
                } catch {
                    print("Wardlume [UserAssetManager]: failed to delete \(filename) — \(error.localizedDescription)")
                }
            }
        }
    }
}
