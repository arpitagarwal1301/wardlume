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
    @ObservedObject private var userAssets = UserAssetManager.shared
    
    @State private var assetError: UserAssetError? = nil
    
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
            
            // ── Your Custom Assets ────────────────────────────────────────────
            Section {
                HStack(alignment: .top, spacing: 16) {
                    ImageAssetSlotView(
                        title: "Base Image",
                        assetURL: userAssets.baseImageURL,
                        onDrop: { url in
                            do { try userAssets.setBaseImage(from: url) }
                            catch let e as UserAssetError { assetError = e }
                            catch { assetError = .copyFailed(underlying: error) }
                        },
                        onClear: { userAssets.clearBaseImage() }
                    )
                    ImageAssetSlotView(
                        title: "Reaction Image",
                        assetURL: userAssets.reactionImageURL,
                        onDrop: { url in
                            do { try userAssets.setReactionImage(from: url) }
                            catch let e as UserAssetError { assetError = e }
                            catch { assetError = .copyFailed(underlying: error) }
                        },
                        onClear: { userAssets.clearReactionImage() }
                    )
                    AudioAssetSlotView(
                        assetURL: userAssets.audioURL,
                        onDrop: { url in
                            do { try userAssets.setAudio(from: url) }
                            catch let e as UserAssetError { assetError = e }
                            catch { assetError = .copyFailed(underlying: error) }
                        },
                        onClear: { userAssets.clearAudio() }
                    )
                }
                Text("Drop a file on any slot to customize your reactions. Click × to revert to the active pack's default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            } header: {
                Text("Your Custom Assets").font(.headline)
            }
        }
        .padding()
        .alert(item: $assetError) { error in
            Alert(
                title: Text("Import Failed"),
                message: Text(error.errorDescription ?? "An unknown error occurred."),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}
