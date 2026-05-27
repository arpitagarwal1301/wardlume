//  PreferencesView.swift
//  Wardlume
//
//  Phase 2.5c: Settings UI for reaction packs.
//
//  SwiftUI-based preferences window that provides a native macOS interface for
//  configuring reaction pack behavior: selecting the active pack, toggling audio,
//  adjusting cooldown duration, and previewing reactions.
//
//  All settings changes apply immediately without requiring application restart.
//  Settings persist to UserDefaults via ReactionManager's didSet observers.

import SwiftUI
import UniformTypeIdentifiers

struct PreferencesView: View {
    @ObservedObject var reactionManager: ReactionManager
    
    @State private var isTargeted: Bool = false
    @State private var importError: PackLoaderError? = nil
    
    var body: some View {
        Form {
            // ── Active Pack Selection ─────────────────────────────────────────
            Section {
                Picker("Active Reaction Pack", selection: $reactionManager.activePackID) {
                    ForEach(reactionManager.availablePacks, id: \.id) { pack in
                        Text(pack.name).tag(pack.id)
                    }
                }
                .pickerStyle(.menu)
                
                Text("Custom reaction packs coming in v1.6 — bring your own image and sound.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            // ── Audio Toggle ──────────────────────────────────────────────────
            Section {
                Toggle("Play reaction sound when ward is breached", isOn: $reactionManager.audioEnabled)
                
                Text("Plays the pack's audio file if available. Some packs are silent by design.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // ── Test Reaction Button ──────────────────────────────────────────
            Section {
                Button("Test Reaction") {
                    reactionManager.triggerForPreview()
                }
                .buttonStyle(.borderedProminent)
            }
            
            // ── Cooldown Duration Selection ───────────────────────────────────
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cooldown Duration")
                        .font(.headline)
                    
                    Picker("Cooldown Duration", selection: $reactionManager.cooldown) {
                        Text("1 second").tag(1.0)
                        Text("3 seconds").tag(3.0)
                        Text("5 seconds").tag(5.0)
                        Text("10 seconds").tag(10.0)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    
                    Text("Minimum time between reactions. Prevents reaction spam from rapid input.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // ── Drag-and-Drop Import Zone ─────────────────────────────────────
            Section {
                ZStack {
                    // Background fill
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isTargeted ? Color.accentColor.opacity(0.1) : Color.clear)
                    
                    // Dashed border overlay
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isTargeted ? Color.accentColor : Color.secondary,
                            style: StrokeStyle(lineWidth: 1.5, dash: [6])
                        )
                    
                    // Content
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.down.circle")
                            .font(.title2)
                            .foregroundColor(isTargeted ? .accentColor : .secondary)
                        
                        Text("Drop pack folder here to install")
                            .font(.body)
                            .foregroundColor(isTargeted ? .accentColor : .secondary)
                    }
                    .padding(.vertical, 24)
                }
                .frame(height: 80)
                .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                    guard let provider = providers.first else { return false }
                    
                    _ = provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier,
                                          options: nil) { item, error in
                        var resolvedURL: URL?
                        if let url = item as? URL {
                            resolvedURL = url
                        } else if let data = item as? Data,
                                  let url = URL(dataRepresentation: data, relativeTo: nil) {
                            resolvedURL = url
                        }
                        
                        guard let url = resolvedURL else {
                            DispatchQueue.main.async {
                                importError = .copyFailed(
                                    underlying: error ?? NSError(domain: "Wardlume",
                                                                 code: -1,
                                                                 userInfo: [NSLocalizedDescriptionKey:
                                                                            "could not load dropped item URL"]))
                            }
                            return
                        }
                        
                        DispatchQueue.main.async {
                            do {
                                try reactionManager.importPack(at: url)
                            } catch let error as PackLoaderError {
                                importError = error
                            } catch {
                                importError = .copyFailed(underlying: error)
                            }
                        }
                    }
                    
                    return true
                }
            }
        }
        .padding()
        .alert(item: $importError) { error in
            Alert(
                title: Text("Import Failed"),
                message: Text(error.errorDescription ?? "An unknown error occurred."),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}
