//  PackLoader.swift
//  Wardlume
//
//  Phase 3a: Discovers and loads user-installed reaction packs from the
//  app's sandboxed Application Support directory at launch.
//
//  ── Pack format ─────────────────────────────────────────────────────────────
//
//  A user pack is a folder (any name, typically ending in .wardpack) placed at:
//
//    ~/Library/Containers/<bundle-id>/Data/Library/Application Support/
//      Wardlume/Packs/<yourPackFolder>/
//
//  The folder must contain:
//    • manifest.json  (required)  — see Manifest struct below for schema
//    • image.png      (required if style == "image")
//    • audio.m4a or audio.mp3 (optional — audio is never required)
//
//  ── Design rationale ────────────────────────────────────────────────────────
//
//  WHY a singleton:
//    Pack discovery is a one-shot operation at launch. ReactionPack.all's
//    computed property references PackLoader.shared.userPacks, so the result
//    must be stable and globally accessible without being passed around.
//
//  WHY discoverUserPacks() must run before ReactionManager.init():
//    ReactionManager.init() validates the persisted activePackID against
//    ReactionPack.all. If a user pack was selected and the app is relaunched,
//    that ID must already be in .all at validation time. AppDelegate calls
//    discoverUserPacks() before instantiating ReactionManager.
//
//  WHY ID collision is checked against ReactionPack.builtIn (not .all):
//    ReactionPack.all is computed as builtIn + PackLoader.shared.userPacks.
//    Calling .all during pack loading would re-enter this loader mid-scan
//    and return a partially-populated result. Using .builtIn breaks the cycle
//    cleanly; duplicate-user-pack ID detection uses the locally accumulated
//    array instead.
//
//  ────────────────────────────────────────────────────────────────────────────

import AppKit
import Combine

// ---------------------------------------------------------------------------
// MARK: — PackLoaderError
// ---------------------------------------------------------------------------

/// Specific failure modes for pack loading.
///
/// Cases carry enough context for Phase 3b's drag-and-drop UI to surface
/// a meaningful, actionable error message without having to parse strings.
enum PackLoaderError: Error, LocalizedError {

    /// The pack folder contains no manifest.json.
    case manifestMissing

    /// manifest.json exists but could not be read or decoded.
    case manifestUnreadable(underlying: Error)

    /// The manifest's manifestVersion field is not supported by this build.
    case manifestVersionUnsupported(got: Int)

    /// A required top-level field is absent or empty.
    case missingRequiredField(String)

    /// A field is present but its value is invalid (e.g. unknown style string).
    case invalidFieldValue(field: String, reason: String)

    /// The pack's id collides with a built-in pack or an already-loaded user pack.
    case idCollision(id: String)

    /// A file referenced in the manifest (imageFile / audioFile) does not exist
    /// in the pack folder. Only thrown for imageFile when style == "image" —
    /// audio is always optional.
    case referencedAssetMissing(filename: String)

    /// Phase 3b: The source URL is a file, not a directory.
    case notADirectory

    /// Phase 3b: A folder with this name already exists in the packs directory.
    case destinationFolderExists(name: String)

    /// Phase 3b: The pack folder could not be copied to the packs directory.
    case copyFailed(underlying: Error)

    // Human-readable descriptions used in console logs and (Phase 3b) alert text.
    var errorDescription: String? {
        switch self {
        case .manifestMissing:
            return "manifest.json not found in pack folder"
        case .manifestUnreadable(let err):
            return "manifest.json could not be decoded: \(err.localizedDescription)"
        case .manifestVersionUnsupported(let v):
            return "unsupported manifestVersion \(v) (this build supports version 2)"
        case .missingRequiredField(let field):
            return "missing required field '\(field)'"
        case .invalidFieldValue(let field, let reason):
            return "invalid value for '\(field)': \(reason)"
        case .idCollision(let id):
            return "id '\(id)' is already used by a built-in or previously loaded pack"
        case .referencedAssetMissing(let filename):
            return "referenced asset '\(filename)' not found in pack folder"
        case .notADirectory:
            return "source URL is a file, not a folder"
        case .destinationFolderExists(let name):
            return "a folder named '\(name)' already exists in the packs directory; rename your source folder and try again"
        case .copyFailed(let err):
            return "could not copy pack folder: \(err.localizedDescription)"
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: — PackLoaderError + Identifiable
// ---------------------------------------------------------------------------

extension PackLoaderError: Identifiable {
    var id: String { errorDescription ?? String(describing: self) }
}

// ---------------------------------------------------------------------------
// MARK: — PackLoader
// ---------------------------------------------------------------------------

final class PackLoader: ObservableObject {

    // ── Singleton ─────────────────────────────────────────────────────────────

    static let shared = PackLoader()
    private init() {}

    // ── State ─────────────────────────────────────────────────────────────────

    /// User packs successfully loaded at last discoverUserPacks() call.
    /// Empty on launch until discoverUserPacks() runs.
    /// Phase 3b: @Published so ReactionManager can subscribe and update its picker.
    @Published private(set) var userPacks: [ReactionPack] = []

    // ── Public API ────────────────────────────────────────────────────────────

    /// Returns (and creates) the directory where user packs are stored.
    ///
    /// Uses the throwing FileManager variant so we never force-unwrap:
    ///   1. `url(for:in:appropriateFor:create:true)` resolves + creates the
    ///      Application Support base directory if it doesn't exist.
    ///   2. An explicit `createDirectory(withIntermediateDirectories:true)` call
    ///      creates the `Wardlume/Packs/` subdirectory (no-op if it already exists).
    ///
    /// Throws on disk-full or permission corruption — caller should catch and
    /// gracefully degrade to built-ins only.
    func userPacksDirectory() throws -> URL {
        // Step 1: resolve (and create if needed) the Application Support base.
        // On a sandboxed app this returns:
        //   ~/Library/Containers/<bundle-id>/Data/Library/Application Support/
        let base = try FileManager.default.url(
            for:              .applicationSupportDirectory,
            in:               .userDomainMask,
            appropriateFor:   nil,
            create:           true
        )

        // Step 2: append our subdirectory path and create it explicitly.
        // withIntermediateDirectories: true → creates Wardlume/ and Packs/ in
        // one call; no-op if either already exists.
        let packsDir = base.appendingPathComponent("Wardlume/Packs", isDirectory: true)
        try FileManager.default.createDirectory(
            at:                     packsDir,
            withIntermediateDirectories: true,
            attributes:             nil
        )
        return packsDir
    }

    /// Scans the user packs directory, loads valid packs, and populates userPacks.
    ///
    /// Called once at app launch, before ReactionManager is instantiated.
    /// On any I/O error (e.g. disk full, permissions), logs the failure and
    /// leaves userPacks empty — the app continues with built-in packs only.
    func discoverUserPacks() {
        performDiscovery()
    }

    /// Phase 3b: Re-scans the user packs directory after a drag-and-drop import.
    ///
    /// Called after importPack() successfully copies a new pack folder.
    /// The @Published userPacks assignment triggers ReactionManager's Combine
    /// subscription, which updates availablePacks and refreshes the picker.
    func refreshUserPacks() {
        performDiscovery()
    }

    /// Phase 3b: Validates and imports a pack folder via drag-and-drop.
    ///
    /// - Parameter sourceURL: The dragged folder URL (may be outside the sandbox).
    /// - Returns: The imported ReactionPack instance (with destination URLs).
    /// - Throws: PackLoaderError with a specific case for each failure mode.
    ///
    /// Flow:
    ///   1. Start security-scoped resource access (defer stop)
    ///   2. Verify sourceURL is a directory
    ///   3. Get (and create) userPacksDirectory()
    ///   4. Check destination doesn't already exist
    ///   5. Validate pack at source (loadPack with alreadyLoaded: userPacks)
    ///   6. Copy folder to destination
    ///   7. refreshUserPacks() — @Published fires, chain updates
    ///   8. Return pack from refreshed userPacks (destination URLs)
    @discardableResult
    func importPack(at sourceURL: URL) throws -> ReactionPack {
        // ── Diagnostic logging ────────────────────────────────────────────────
        print("Wardlume [PackLoader]: importPack called with URL: \(sourceURL)")
        print("Wardlume [PackLoader]: URL path: \(sourceURL.path)")
        print("Wardlume [PackLoader]: URL isFileURL: \(sourceURL.isFileURL)")
        print("Wardlume [PackLoader]: URL isDirectory check: \((try? sourceURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false)")
        
        // ── 1. Security-scoped resource access ────────────────────────────────
        // Attempt to start security-scoped access. If it returns false, the URL
        // may still be accessible via existing sandbox entitlements (e.g.,
        // com.apple.security.files.user-selected.read-only for user-dragged items).
        // We log the result for diagnostics but continue regardless — let the
        // actual file operations determine reachability.
        let didStart = sourceURL.startAccessingSecurityScopedResource()
        print("Wardlume [PackLoader]: security-scoped access \(didStart ? "granted" : "not required or unavailable")")
        
        defer {
            if didStart {
                sourceURL.stopAccessingSecurityScopedResource()
                print("Wardlume [PackLoader]: stopped security-scoped access")
            }
        }

        print("Wardlume [PackLoader]: FileManager.fileExists at path: \(FileManager.default.fileExists(atPath: sourceURL.path))")

        // ── 2. Verify sourceURL is a directory ────────────────────────────────
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDir),
              isDir.boolValue else {
            throw PackLoaderError.notADirectory
        }

        // ── 3. Get userPacksDirectory ─────────────────────────────────────────
        let packsDir = try userPacksDirectory()

        // ── 4. Compute destination and check it doesn't exist ─────────────────
        let folderName = sourceURL.lastPathComponent
        let destination = packsDir.appendingPathComponent(folderName, isDirectory: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            throw PackLoaderError.destinationFolderExists(name: folderName)
        }

        // ── 5. Validate pack at source ────────────────────────────────────────
        // loadPack throws PackLoaderError on any validation failure.
        // alreadyLoaded: userPacks ensures ID collision detection includes
        // existing user packs (not just built-ins).
        let validatedPack = try loadPack(at: sourceURL, alreadyLoaded: userPacks)

        // ── 6. Copy folder to destination ─────────────────────────────────────
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destination)
        } catch {
            throw PackLoaderError.copyFailed(underlying: error)
        }

        print("Wardlume [PackLoader]: imported pack '\(validatedPack.id)' to '\(folderName)'")

        // ── 7. Refresh user packs ─────────────────────────────────────────────
        // @Published userPacks assignment triggers ReactionManager's subscription.
        refreshUserPacks()

        // ── 8. Return pack from refreshed userPacks ───────────────────────────
        // Prefer the freshly-loaded instance (destination URLs) over the
        // validated one (source URLs). Fall back to validatedPack if refresh
        // somehow misses it (shouldn't happen in practice).
        return userPacks.first(where: { $0.id == validatedPack.id }) ?? validatedPack
    }

    // ── Private: discovery ────────────────────────────────────────────────────

    /// Phase 3b DRY refactor: shared scan logic for discoverUserPacks() and
    /// refreshUserPacks().
    ///
    /// Scans the user packs directory, loads valid packs, and reassigns userPacks.
    /// On any I/O error, logs the failure and leaves userPacks empty (or unchanged
    /// if this is a refresh call after a successful import).
    private func performDiscovery() {
        let packsDir: URL
        do {
            packsDir = try userPacksDirectory()
        } catch {
            print("Wardlume [PackLoader]: failed to access/create packs directory — " +
                  "\(error.localizedDescription). Continuing with built-in packs only.")
            userPacks = []
            return
        }

        print("Wardlume [PackLoader]: scanning \(packsDir.path)")

        // Enumerate immediate subdirectories only (non-recursive).
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at:                    packsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options:               [.skipsHiddenFiles]
        ) else {
            print("Wardlume [PackLoader]: could not enumerate packs directory. " +
                  "Continuing with built-in packs only.")
            userPacks = []
            return
        }

        var loaded: [ReactionPack] = []

        for candidateURL in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            // Skip non-directories (e.g. stray .DS_Store, README files).
            let isDir = (try? candidateURL.resourceValues(forKeys: [.isDirectoryKey])
                                          .isDirectory) ?? false
            guard isDir else { continue }

            let folderName = candidateURL.lastPathComponent

            do {
                // Pass currently-accumulated packs so duplicate-user-pack ID
                // detection works without calling ReactionPack.all (see design note).
                let pack = try loadPack(at: candidateURL, alreadyLoaded: loaded)
                loaded.append(pack)
                print("Wardlume [PackLoader]: loaded pack '\(pack.id)' from '\(folderName)'")
            } catch {
                // Log the specific reason and continue — one bad pack never
                // prevents valid packs from loading.
                let reason = (error as? PackLoaderError)?.errorDescription
                             ?? error.localizedDescription
                print("Wardlume [PackLoader]: skipped '\(folderName)': \(reason)")
            }
        }

        userPacks = loaded
        print("Wardlume [PackLoader]: discovered \(loaded.count) user pack(s)")
    }

    // ── Private: pack loading ─────────────────────────────────────────────────

    /// Loads a single pack from `folderURL`.
    ///
    /// - Parameter folderURL: The pack's root folder (contains manifest.json + assets).
    /// - Parameter alreadyLoaded: User packs accumulated so far in this discovery pass.
    ///   Used for duplicate-ID detection without referencing ReactionPack.all mid-scan.
    /// - Throws: `PackLoaderError` with a specific case for each failure mode.
    private func loadPack(at folderURL: URL,
                          alreadyLoaded: [ReactionPack]) throws -> ReactionPack {

        // ── 1. Read + decode manifest.json ────────────────────────────────────

        let manifestURL = folderURL.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw PackLoaderError.manifestMissing
        }

        let data: Data
        let manifest: Manifest
        do {
            data = try Data(contentsOf: manifestURL)
        } catch {
            throw PackLoaderError.manifestUnreadable(underlying: error)
        }
        do {
            let decoder = JSONDecoder()
            // Field names in the manifest already match Swift conventions
            // (camelCase), so no keyDecodingStrategy override is needed.
            manifest = try decoder.decode(Manifest.self, from: data)
        } catch {
            throw PackLoaderError.manifestUnreadable(underlying: error)
        }

        // ── 2. Manifest version check ─────────────────────────────────────────

        guard manifest.manifestVersion == 2 else {
            throw PackLoaderError.manifestVersionUnsupported(got: manifest.manifestVersion)
        }

        // ── 3. Required field validation ──────────────────────────────────────

        // id and name are non-optional in the Codable struct, but guard against
        // empty strings which are technically valid JSON but semantically broken.
        guard !manifest.id.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw PackLoaderError.missingRequiredField("id")
        }
        guard !manifest.name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw PackLoaderError.missingRequiredField("name")
        }
        guard !manifest.style.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw PackLoaderError.missingRequiredField("style")
        }
        guard manifest.duration > 0 else {
            throw PackLoaderError.invalidFieldValue(
                field:  "duration",
                reason: "must be > 0, got \(manifest.duration)"
            )
        }

        // ── 4. Style validation ───────────────────────────────────────────────

        let packStyle: PackStyle
        switch manifest.style {
        case "image":   packStyle = .image
        case "minimal": packStyle = .minimal
        default:
            throw PackLoaderError.invalidFieldValue(
                field:  "style",
                reason: "must be \"image\" or \"minimal\", got \"\(manifest.style)\""
            )
        }

        // ── 5. ID collision check ─────────────────────────────────────────────

        // Check against built-in IDs first.
        if ReactionPack.builtIn.contains(where: { $0.id == manifest.id }) {
            throw PackLoaderError.idCollision(id: manifest.id)
        }
        // Check against user packs already loaded in this discovery pass.
        if alreadyLoaded.contains(where: { $0.id == manifest.id }) {
            throw PackLoaderError.idCollision(id: manifest.id)
        }

        // ── 6. Resolve asset URLs (filesystem, not Bundle.main) ───────────────

        let resolvedBaseImageURL: URL?
        if let baseImageFile = manifest.baseImageFile, !baseImageFile.isEmpty {
            let url = folderURL.appendingPathComponent(baseImageFile)
            // Base image is optional — missing file is not an error, just nil.
            resolvedBaseImageURL = FileManager.default.fileExists(atPath: url.path) ? url : nil
        } else {
            resolvedBaseImageURL = nil
        }

        let resolvedReactionImageURL: URL?
        if let reactionImageFile = manifest.reactionImageFile, !reactionImageFile.isEmpty {
            let url = folderURL.appendingPathComponent(reactionImageFile)
            if FileManager.default.fileExists(atPath: url.path) {
                resolvedReactionImageURL = url
            } else if packStyle == .image {
                // Image packs that specify a reactionImageFile but the file is absent
                // get a hard error — the user clearly intended an image pack but
                // the asset is missing. They can use style: "minimal" for code-only packs.
                throw PackLoaderError.referencedAssetMissing(filename: reactionImageFile)
            } else {
                // minimal pack with a reactionImageFile entry — ignore it (reactionImageFile is
                // irrelevant for minimal packs, no need to throw).
                resolvedReactionImageURL = nil
            }
        } else {
            resolvedReactionImageURL = nil
        }

        let resolvedAudioURL: URL?
        if let audioFile = manifest.audioFile, !audioFile.isEmpty {
            let url = folderURL.appendingPathComponent(audioFile)
            // Audio is always optional — missing file is not an error, just nil.
            resolvedAudioURL = FileManager.default.fileExists(atPath: url.path) ? url : nil
        } else {
            resolvedAudioURL = nil
        }

        // ── 7. Construct ReactionPack ─────────────────────────────────────────

        let bg = manifest.backgroundColor
        return ReactionPack(
            id:                      manifest.id,
            name:                    manifest.name,
            duration:                manifest.duration,
            backgroundColor:         NSColor(red:   bg.r, green: bg.g,
                                             blue:  bg.b, alpha: bg.a),
            baseImageBundleName:     manifest.baseImageFile,      // kept for reference; URL is resolved
            reactionImageBundleName: manifest.reactionImageFile,  // kept for reference; URL is resolved
            audioBundleName:         manifest.audioFile,          // kept for reference; URL is resolved
            placeholderText:         manifest.placeholderText,
            baseImageURL:            resolvedBaseImageURL,
            reactionImageURL:        resolvedReactionImageURL,
            audioURL:                resolvedAudioURL,
            style:                   packStyle
        )
    }
}

// ---------------------------------------------------------------------------
// MARK: — Manifest (private Codable)
// ---------------------------------------------------------------------------

private extension PackLoader {

    /// Mirrors the manifest.json schema exactly.
    ///
    /// Field names use camelCase to match JSON keys directly — no
    /// keyDecodingStrategy override required. Optional fields map to
    /// optional Swift properties.
    ///
    /// Phase 4a: manifestVersion bumped to 2. Version 1 manifests are rejected
    /// with a clear log message directing users to upgrade.
    struct Manifest: Decodable {
        /// Format version. Only version 2 is supported in this build.
        /// Version 1 manifests (pre-bait-and-switch) are skipped with a log.
        let manifestVersion:   Int

        /// Globally unique pack identifier. Reverse-DNS recommended for user
        /// packs (e.g. "com.yourname.packname") to avoid collisions.
        let id:                String

        /// User-visible pack name shown in the Preferences picker.
        let name:              String

        /// Pack author's name. Not currently shown in UI; reserved for
        /// Phase 3c pack management view.
        let author:            String?

        /// Overlay display duration in seconds. Must be > 0.
        let duration:          Double

        /// Rendering style. "image" or "minimal".
        let style:             String

        /// Relative filename of the base image asset within the pack folder.
        /// The base image is shown continuously while the ward is active.
        /// Optional for all pack styles — base image is never required.
        /// Phase 4a: new field.
        let baseImageFile:     String?

        /// Relative filename of the reaction image asset within the pack folder.
        /// The reaction image swaps in on intrusion, then swaps back to base.
        /// Required when style == "image". Omit or set null for minimal packs.
        /// Phase 4a: renamed from imageFile.
        let reactionImageFile: String?

        /// Relative filename of the audio asset within the pack folder.
        /// Optional for all pack styles — audio is never required.
        let audioFile:         String?

        /// Background colour as RGBA 0–1 floats.
        let backgroundColor:   ManifestColor

        /// Text shown when reaction image is missing (image style) or as the primary
        /// text label (minimal style).
        let placeholderText:   String
    }

    /// RGBA colour as encoded in manifest.json.
    struct ManifestColor: Decodable {
        let r: Double
        let g: Double
        let b: Double
        let a: Double
    }
}
