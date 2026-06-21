//  WardPrefs.swift
//  Wardlume
//
//  User prefs that gate ward behavior. Mirrors the ReactionManager
//  @Published + didSet → UserDefaults("wardlume.*") persistence pattern.
//
//  NOTE: there is intentionally NO "black out other displays" pref. Secondary
//  displays are covered by the ward overlay itself (see the multi-display ward
//  increment), never left showing the live desktop — so there is nothing safe to
//  toggle off. Gesture blocking IS user-controllable because gestures only affect
//  navigation, not content exposure.

import Foundation
import Combine

@MainActor
final class WardPrefs: ObservableObject {

    /// When true (default), system trackpad gestures (Mission Control, Spaces,
    /// Launchpad, etc.) are suppressed while the ward is active via GestureBlocker.
    @Published var blockGestures: Bool {
        didSet { UserDefaults.standard.set(blockGestures, forKey: Self.kBlockGestures) }
    }

    private static let kBlockGestures = "wardlume.blockGestures"

    init() {
        // object(forKey:) distinguishes "absent" (use default true) from a stored false.
        if UserDefaults.standard.object(forKey: Self.kBlockGestures) != nil {
            blockGestures = UserDefaults.standard.bool(forKey: Self.kBlockGestures)
        } else {
            blockGestures = true
        }
    }

    func resetToDefaults() {
        blockGestures = true
    }
}
