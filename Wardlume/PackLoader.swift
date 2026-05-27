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

    // Human-readable descriptions used in console logs and (Phase 3b) alert text.
    var errorDescription: String? {
        switch self {
        case .manifestMissing:
            return "manifest.json not found in pack folder"
        case .manifestUnreadable(let err):
            return "manifest.json could not be decoded: \(err.localizedDescription)"
        case .manifestVersionUnsupported(let v):
            return "unsupported manifestVersion \(v) (this build supports version 1)"
        case .missingRequiredField(let field):
            return "missing required field '\(field)'"
        case .invalidFieldValue(let field, let reason):
            return "invalid value for '\(field)': \(reason)"
        case .idCollision(let id):
            return "id '\(id)' is already used by a built-in or previously loaded pack"
        case .referencedAssetMissing(let filename):
            return "referenced asset '\(filename)' not found in pack folder"
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: — PackLoader
// ---------------------------------------------------------------------------

final class PackLoader {

    // ── Singleton ─────────────────────────────────────────────────────────────

    static let shared = PackLoader()
    private init() {}

    // ── State ─────────────────────────────────────────────────────────────────

    /// User packs successfully loaded at last discoverUserPacks() call.
    /// Empty on launch until discoverUserPacks() runs.
    private(set) var userPacks: [ReactionPack] = []

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

    /// Phase 3b stub. Called after a successful drag-and-drop import.
    ///
    /// Currently a no-op. Phase 3b will re-run discovery, merge results with
    /// existing userPacks, and notify observers (likely via @Published on
    /// ReactionManager or a dedicated @Published property here) so the
    /// Preferences picker updates live without a relaunch.
    func refreshUserPacks() {
        // TODO Phase 3b: re-run discovery, publish change
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

        guard manifest.manifestVersion == 1 else {
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

        let resolvedImageURL: URL?
        if let imageFile = manifest.imageFile, !imageFile.isEmpty {
            let url = folderURL.appendingPathComponent(imageFile)
            if FileManager.default.fileExists(atPath: url.path) {
                resolvedImageURL = url
            } else if packStyle == .image {
                // Image packs that specify an imageFile but the file is absent
                // get a hard error — the user clearly intended an image pack but
                // the asset is missing. They can use style: "minimal" for code-only packs.
                throw PackLoaderError.referencedAssetMissing(filename: imageFile)
            } else {
                // minimal pack with an imageFile entry — ignore it (imageFile is
                // irrelevant for minimal packs, no need to throw).
                resolvedImageURL = nil
            }
        } else {
            resolvedImageURL = nil
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
            id:              manifest.id,
            name:            manifest.name,
            duration:        manifest.duration,
            backgroundColor: NSColor(red:   bg.r, green: bg.g,
                                     blue:  bg.b, alpha: bg.a),
            imageBundleName: manifest.imageFile,   // kept for reference; URL is resolved
            audioBundleName: manifest.audioFile,   // kept for reference; URL is resolved
            placeholderText: manifest.placeholderText,
            imageURL:        resolvedImageURL,
            audioURL:        resolvedAudioURL,
            style:           packStyle
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
    struct Manifest: Decodable {
        /// Format version. Only version 1 is supported in this build.
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

        /// Relative filename of the image asset within the pack folder.
        /// Required when style == "image". Omit or set null for minimal packs.
        let imageFile:         String?

        /// Relative filename of the audio asset within the pack folder.
        /// Optional for all pack styles — audio is never required.
        let audioFile:         String?

        /// Background colour as RGBA 0–1 floats.
        let backgroundColor:   ManifestColor

        /// Text shown when image is missing (image style) or as the primary
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
