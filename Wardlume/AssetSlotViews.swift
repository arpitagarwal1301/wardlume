//  AssetSlotViews.swift
//  Wardlume
//
//  Phase 4c: Reusable SwiftUI slot widgets for user asset uploads.
//
//  Contains:
//    • AudioPreviewPlayer — ObservableObject wrapper for AVAudioPlayer with delegate
//    • ImageAssetSlotView — shared by Base Image and Reaction Image slots
//    • AudioAssetSlotView — specialized for audio with play/stop button
//
//  All three slots use the same drop pattern from Phase 3b, adapted for single-file
//  uploads instead of folder imports. Validation and persistence are handled by
//  UserAssetManager; these views are purely presentational.

import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import Combine

// ---------------------------------------------------------------------------
// MARK: — AudioPreviewPlayer
// ---------------------------------------------------------------------------

/// ObservableObject wrapper for AVAudioPlayer with delegate support.
///
/// SwiftUI Views are structs and can't conform to AVAudioPlayerDelegate directly.
/// This class owns the AVAudioPlayer, serves as its delegate, and publishes
/// playback state so the UI can toggle between play/stop buttons.
///
/// Usage:
///   @StateObject private var preview = AudioPreviewPlayer()
///   Button { preview.play(url: audioURL) } label: { ... }
final class AudioPreviewPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    
    /// True while audio is playing, false otherwise.
    /// Drives the play/stop button icon in AudioAssetSlotView.
    @Published private(set) var isPlaying: Bool = false
    
    /// The active AVAudioPlayer instance, or nil when idle.
    private var player: AVAudioPlayer?
    
    /// Start playing audio from the given URL.
    ///
    /// Stops any in-flight playback first. On failure (e.g., corrupted file),
    /// logs the error and sets isPlaying to false.
    func play(url: URL) {
        stop()  // stop any in-flight playback
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.prepareToPlay()
            p.play()
            player = p
            isPlaying = true
        } catch {
            print("Wardlume [AudioPreviewPlayer]: failed to play \(url.lastPathComponent): \(error)")
            isPlaying = false
        }
    }
    
    /// Stop playback and release the player.
    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
    }
    
    /// AVAudioPlayerDelegate callback — fired when audio finishes naturally.
    ///
    /// Dispatches to main queue to update @Published isPlaying (delegate callback
    /// may fire on a background thread).
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.player = nil
            self?.isPlaying = false
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: — ImageAssetSlotView
// ---------------------------------------------------------------------------

/// Reusable slot widget for image uploads (Base Image and Reaction Image).
///
/// Shows a thumbnail of the uploaded image if present, or an empty-state hint
/// with dashed border if nil. When filled, displays a ✕ button in the top-right
/// corner that calls onClear().
///
/// Drop handling delegates to the parent view (PreferencesView) so error handling
/// and UserAssetManager calls stay centralized.
struct ImageAssetSlotView: View {
    let title: String                    // "Base Image" or "Reaction Image"
    let assetURL: URL?                   // current uploaded file, or nil
    let onDrop: (URL) -> Void            // called when user drops a file
    let onClear: () -> Void              // called when ✕ tapped
    
    @State private var isTargeted: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            ZStack(alignment: .topTrailing) {
                // background + content
                ZStack {
                    // border + fill
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isTargeted ? Color.accentColor.opacity(0.15) : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(
                                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.5),
                                    style: StrokeStyle(lineWidth: 1.5, dash: assetURL == nil ? [6] : [])
                                )
                        )
                    
                    // content (thumbnail or empty-state hint)
                    if let url = assetURL, let image = NSImage(contentsOf: url) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 110, height: 70)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .padding(6)
                    } else {
                        VStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle").font(.title3)
                            Text("Drop image").font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 130, height: 90)
                
                // clear button (only shown when filled)
                if assetURL != nil {
                    Button(action: onClear) {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.6))
                            .font(.body)
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers: providers)
            }
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            var resolvedURL: URL?
            if let url = item as? URL {
                resolvedURL = url
            } else if let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) {
                resolvedURL = url
            }
            guard let url = resolvedURL else { return }
            DispatchQueue.main.async { onDrop(url) }
        }
        return true
    }
}

// ---------------------------------------------------------------------------
// MARK: — AudioAssetSlotView
// ---------------------------------------------------------------------------

/// Specialized slot widget for audio uploads.
///
/// When filled, shows filename + speaker icon + play/stop button. When empty,
/// shows "Drop audio" hint with dashed border. Play button uses AudioPreviewPlayer
/// to handle playback and delegate callbacks.
///
/// Tapping ✕ stops any in-flight playback before calling onClear().
struct AudioAssetSlotView: View {
    let assetURL: URL?
    let onDrop: (URL) -> Void
    let onClear: () -> Void
    
    @State private var isTargeted: Bool = false
    @StateObject private var preview = AudioPreviewPlayer()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Audio").font(.caption).foregroundStyle(.secondary)
            ZStack(alignment: .topTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isTargeted ? Color.accentColor.opacity(0.15) : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(
                                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.5),
                                    style: StrokeStyle(lineWidth: 1.5, dash: assetURL == nil ? [6] : [])
                                )
                        )
                    
                    if let url = assetURL {
                        HStack(spacing: 8) {
                            Button {
                                if preview.isPlaying {
                                    preview.stop()
                                } else {
                                    preview.play(url: url)
                                }
                            } label: {
                                Image(systemName: preview.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(Color.accentColor)
                            }
                            .buttonStyle(.plain)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(url.lastPathComponent)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle").font(.title3)
                            Text("Drop audio").font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 130, height: 90)
                
                if assetURL != nil {
                    Button(action: {
                        preview.stop()
                        onClear()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.6))
                            .font(.body)
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers: providers)
            }
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            var resolvedURL: URL?
            if let url = item as? URL {
                resolvedURL = url
            } else if let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) {
                resolvedURL = url
            }
            guard let url = resolvedURL else { return }
            DispatchQueue.main.async { onDrop(url) }
        }
        return true
    }
}
