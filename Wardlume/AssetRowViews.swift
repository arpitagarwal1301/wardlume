//  AssetRowViews.swift
//  Wardlume
//
//  Row-based custom-asset widgets for the Pack & assets pane. Each row is a
//  full-width, self-explanatory slot: a preview/drop-zone tile, a plain label
//  with a "when it shows" caption, and Browse… / Replace… / Remove actions.
//
//  Two equally-discoverable ways in (both route to the same UserAssetManager
//  setters): drag a file anywhere on the row, or click Browse… (NSOpenPanel
//  filtered to the slot's types). Validation errors surface inline beneath the
//  row via UserAssetError.errorDescription — no detached global alert.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: — Role

enum AssetRole {
    case cover, reaction, sound

    var isAudio: Bool { self == .sound }

    var label: String {
        switch self {
        case .cover:    "Cover image"
        case .reaction: "Reaction image"
        case .sound:    "Reaction sound"
        }
    }

    var help: String {
        switch self {
        case .cover:    "Shows the whole time the ward is on, in place of the glass shield."
        case .reaction: "Flashes for a moment when someone touches your keyboard or mouse, then disappears."
        case .sound:    "Plays together with the reaction image when someone touches your Mac. Press play to preview."
        }
    }

    var format: String {
        isAudio ? "MP3, M4A or WAV · up to 10 MB"
                : "PNG, JPEG, HEIC or GIF · up to 10 MB"
    }

    /// Green status line shown when an image slot is filled. (Audio shows its filename instead.)
    var activeNote: String {
        switch self {
        case .cover:    "Active — overriding the glass shield"
        case .reaction: "Active — flashes on intrusion"
        case .sound:    "Active"
        }
    }

    var allowedTypes: [UTType] {
        isAudio ? [.mp3, .mpeg4Audio, .wav] : [.png, .jpeg, .heic, .gif]
    }
}

// MARK: — Row

struct AssetRow: View {
    let role: AssetRole
    let assetURL: URL?
    let set: (URL) throws -> Void
    let clear: () -> Void

    @State private var isTargeted = false
    @State private var error: String?
    @StateObject private var preview = AudioPreviewPlayer()

    private var isFilled: Bool { assetURL != nil }

    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            tile
            VStack(alignment: .leading, spacing: 3) { center }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { handleDrop($0) }
    }

    // MARK: Tile (preview + drop zone)

    private var tile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(isTargeted ? Theme.accentTeal.opacity(0.12) : Color.clear)
            tileContent
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(
                    isTargeted ? Theme.accentTeal
                               : (isFilled ? Theme.borderSubtle : Color.white.opacity(0.28)),
                    style: StrokeStyle(lineWidth: (isFilled && !isTargeted) ? 0.5 : 1.5,
                                       dash: (isFilled || isTargeted) ? [] : [5]))
        }
        .frame(width: 86, height: 60)
    }

    @ViewBuilder private var tileContent: some View {
        if isTargeted {
            VStack(spacing: 3) {
                Image(systemName: "arrow.down.circle.fill").font(.system(size: 18))
                Text("Release").font(.system(size: 10))
            }
            .foregroundStyle(Theme.accentTeal)
        } else if isFilled {
            if role.isAudio {
                Button {
                    if preview.isPlaying { preview.stop() }
                    else if let url = assetURL { preview.play(url: url) }
                } label: {
                    Image(systemName: preview.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(Theme.accentTeal)
                }
                .buttonStyle(.plain)
            } else if let url = assetURL, let img = NSImage(contentsOf: url) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 86, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            } else {
                Image(systemName: "photo").foregroundStyle(Theme.textTertiary)
            }
        } else {
            VStack(spacing: 3) {
                Image(systemName: "tray.and.arrow.down").font(.system(size: 17))
                Text("Drag here").font(.system(size: 10))
            }
            .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: Center (label + status / help / error)

    @ViewBuilder private var center: some View {
        Text(role.label)
            .font(.system(size: 13.5))
            .foregroundStyle(Theme.textPrimary)

        if let error {
            Text(error)
                .font(.system(size: 12))
                .foregroundStyle(Theme.danger)
                .fixedSize(horizontal: false, vertical: true)
        } else if isFilled {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.statusActive)
                Text(filledNote)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.statusActive)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } else {
            Text(role.help)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(role.format)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var filledNote: String {
        if role.isAudio {
            let name = assetURL?.lastPathComponent ?? "Sound"
            return "\(name) · press play to preview"
        }
        return role.activeNote
    }

    // MARK: Trailing (actions)

    @ViewBuilder private var trailing: some View {
        VStack(spacing: 6) {
            actionButton(isFilled ? "Replace…" : "Browse…",
                         icon: isFilled ? "arrow.triangle.2.circlepath" : "folder",
                         action: browse)
            if isFilled {
                Button(action: clearAsset) {
                    Text("Remove")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12))
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 13).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(Theme.keycapBackground))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.borderSubtle, lineWidth: 0.5))
            .foregroundStyle(Theme.textPrimary)
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private func browse() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = role.allowedTypes
        if panel.runModal() == .OK, let url = panel.url { apply(url) }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            var resolved: URL?
            if let url = item as? URL {
                resolved = url
            } else if let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) {
                resolved = url
            }
            guard let url = resolved else { return }
            DispatchQueue.main.async { apply(url) }
        }
        return true
    }

    private func apply(_ url: URL) {
        do {
            try set(url)
            error = nil
        } catch let e as UserAssetError {
            error = e.errorDescription
        } catch let e {
            error = e.localizedDescription
        }
    }

    private func clearAsset() {
        if role.isAudio { preview.stop() }
        clear()
        error = nil
    }
}
