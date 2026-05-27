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

struct PreferencesView: View {
    @ObservedObject var reactionManager: ReactionManager
    
    var body: some View {
        Form {
            // ── Active Pack Selection ─────────────────────────────────────────
            Section {
                Picker("Active Reaction Pack", selection: $reactionManager.activePackID) {
                    ForEach(ReactionPack.all, id: \.id) { pack in
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
        }
        .padding()
    }
}
