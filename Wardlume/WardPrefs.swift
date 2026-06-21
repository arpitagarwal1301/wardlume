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

    /// User-level shader look for the ward background. Default `.minimal` (the sober
    /// glass shield that matches Silent Professional). `.full` enables the animated
    /// aurora / sigils / motes. Read at activation in AppDelegate.
    @Published var shaderStyleOverride: ShaderStyle {
        didSet { UserDefaults.standard.set(shaderStyleOverride.rawValue, forKey: Self.kShaderStyle) }
    }

    private static let kBlockGestures = "wardlume.blockGestures"
    private static let kShaderStyle   = "wardlume.shaderStyleOverride"

    init() {
        // object(forKey:) distinguishes "absent" (use default) from a stored value.
        if UserDefaults.standard.object(forKey: Self.kBlockGestures) != nil {
            blockGestures = UserDefaults.standard.bool(forKey: Self.kBlockGestures)
        } else {
            blockGestures = true
        }

        if let raw = UserDefaults.standard.string(forKey: Self.kShaderStyle),
           let style = ShaderStyle(rawValue: raw) {
            shaderStyleOverride = style
        } else {
            shaderStyleOverride = .minimal
        }
    }

    func resetToDefaults() {
        blockGestures = true
        shaderStyleOverride = .minimal
    }
}
