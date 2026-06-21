//  HotkeyManager.swift
//  Wardlume
//
//  @MainActor ObservableObject mirroring ReactionManager's persistence pattern.
//  Owns the configurable activate (global ⌘⇧L) and unlock (⌘⇧U) combos, plus an
//  optional, default-OFF emergency-exit combo that drops the ward without any
//  authentication. Each combo persists as JSON to one UserDefaults key. All three
//  are kept mutually distinct and individually valid; the activate combo rolls
//  back if Carbon registration fails.
//
//  AppDelegate wires onActivateChanged (re-registers the Carbon hotkey, returns
//  success), onUnlockChanged (pushes the combo into the running event tap), and
//  onEmergencyChanged (pushes enabled + combo into the tap).

import AppKit
import Combine

@MainActor
final class HotkeyManager: ObservableObject {

    @Published var activate: HotkeyCombo = .activateDefault {
        didSet { handleChange(.activate, old: oldValue) }
    }
    @Published var unlock: HotkeyCombo = .unlockDefault {
        didSet { handleChange(.unlock, old: oldValue) }
    }
    /// Emergency-exit combo. Only honored by the tap when `emergencyExitEnabled`.
    @Published var emergencyExit: HotkeyCombo = .emergencyExitDefault {
        didSet { handleChange(.emergency, old: oldValue) }
    }
    /// When true, the emergency-exit combo instantly drops the ward with NO
    /// authentication. Default OFF — anyone at the keyboard could use it.
    @Published var emergencyExitEnabled: Bool = false {
        didSet {
            guard !isApplying else { return }
            UserDefaults.standard.set(emergencyExitEnabled, forKey: Self.kEmergencyEnabled)
            onEmergencyChanged?(emergencyExitEnabled, emergencyExit)
        }
    }

    @Published var activateError: String?
    @Published var unlockError: String?
    @Published var emergencyError: String?

    var onActivateChanged: ((HotkeyCombo) -> Bool)?
    var onUnlockChanged: ((HotkeyCombo) -> Void)?
    var onEmergencyChanged: ((Bool, HotkeyCombo) -> Void)?

    private var isApplying = false
    private static let kActivate         = "wardlume.hotkey.activate"
    private static let kUnlock           = "wardlume.hotkey.unlock"
    private static let kEmergency        = "wardlume.hotkey.emergencyExit"
    private static let kEmergencyEnabled = "wardlume.hotkey.emergencyExitEnabled"

    private enum Field { case activate, unlock, emergency }

    init() {
        isApplying = true
        activate      = Self.load(Self.kActivate)  ?? .activateDefault
        unlock        = Self.load(Self.kUnlock)    ?? .unlockDefault
        emergencyExit = Self.load(Self.kEmergency) ?? .emergencyExitDefault
        // De-conflict on restore (corrupt / hand-edited prefs) so the three combos
        // can never come up equal — that would make the tap checks ambiguous.
        if unlock == activate { unlock = .unlockDefault }
        if emergencyExit == activate || emergencyExit == unlock { emergencyExit = .emergencyExitDefault }
        emergencyExitEnabled = UserDefaults.standard.bool(forKey: Self.kEmergencyEnabled)
        isApplying = false

        persist(activate, key: Self.kActivate)
        persist(unlock, key: Self.kUnlock)
        persist(emergencyExit, key: Self.kEmergency)
    }

    func resetToDefaults() {
        activate             = .activateDefault
        unlock               = .unlockDefault
        emergencyExit        = .emergencyExitDefault
        emergencyExitEnabled = false
    }

    // MARK: — Change handling

    private func handleChange(_ field: Field, old: HotkeyCombo) {
        guard !isApplying else { return }
        let combo = self[field]

        do { try combo.validate() }
        catch {
            setError(error.localizedDescription, field)
            rollback(field, to: old, reRegister: false)
            return
        }
        if conflicts(combo, excluding: field) {
            setError("Each shortcut must be different.", field)
            rollback(field, to: old, reRegister: false)
            return
        }

        persist(combo, key: key(field))
        switch field {
        case .activate:
            if let cb = onActivateChanged, cb(combo) == false {
                setError("That shortcut couldn't be registered (it may be in use by another app).", .activate)
                rollback(.activate, to: old, reRegister: true)
                return
            }
        case .unlock:
            onUnlockChanged?(combo)
        case .emergency:
            onEmergencyChanged?(emergencyExitEnabled, combo)
        }
        setError(nil, field)
    }

    private func conflicts(_ combo: HotkeyCombo, excluding field: Field) -> Bool {
        for f in [Field.activate, .unlock, .emergency] where f != field {
            if self[f] == combo { return true }
        }
        return false
    }

    private func rollback(_ field: Field, to old: HotkeyCombo, reRegister: Bool) {
        isApplying = true
        switch field {
        case .activate:  activate = old
        case .unlock:    unlock = old
        case .emergency: emergencyExit = old
        }
        isApplying = false
        persist(old, key: key(field))
        if reRegister, field == .activate { _ = onActivateChanged?(old) }
    }

    private subscript(_ field: Field) -> HotkeyCombo {
        switch field {
        case .activate:  activate
        case .unlock:    unlock
        case .emergency: emergencyExit
        }
    }

    private func key(_ field: Field) -> String {
        switch field {
        case .activate:  Self.kActivate
        case .unlock:    Self.kUnlock
        case .emergency: Self.kEmergency
        }
    }

    private func setError(_ message: String?, _ field: Field) {
        switch field {
        case .activate:  activateError = message
        case .unlock:    unlockError = message
        case .emergency: emergencyError = message
        }
    }

    // MARK: — Persistence
    private func persist(_ combo: HotkeyCombo, key: String) {
        if let data = try? JSONEncoder().encode(combo) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func load(_ key: String) -> HotkeyCombo? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let combo = try? JSONDecoder().decode(HotkeyCombo.self, from: data),
              (try? combo.validate()) != nil
        else { return nil }
        return combo
    }
}
