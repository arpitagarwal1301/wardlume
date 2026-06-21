//  HotkeyManager.swift
//  Wardlume
//
//  @MainActor ObservableObject mirroring ReactionManager's persistence pattern.
//  Single owner of the configurable activate (global ⌘⇧L) and unlock (⌘⇧U)
//  combos. Persists each as JSON to one UserDefaults key; fires change closures
//  with rollback on failed Carbon registration so the user is never left with no
//  working activate hotkey.
//
//  AppDelegate wires onActivateChanged (re-registers the Carbon hotkey, returns
//  success) and onUnlockChanged (pushes the combo into the running event tap) in
//  the hotkeys increment. Until then these closures are nil and the combos are
//  simply persisted.

import AppKit
import Combine

@MainActor
final class HotkeyManager: ObservableObject {

    @Published var activate: HotkeyCombo = .activateDefault {
        didSet { handleChange(\.activate, old: oldValue, key: Self.kActivate) }
    }
    @Published var unlock: HotkeyCombo = .unlockDefault {
        didSet { handleChange(\.unlock, old: oldValue, key: Self.kUnlock) }
    }

    /// Per-field validation / registration error for inline UI. nil = OK.
    @Published var activateError: String?
    @Published var unlockError: String?

    /// Returns whether the new activate combo registered successfully (for rollback).
    var onActivateChanged: ((HotkeyCombo) -> Bool)?
    /// Pushes the new unlock combo into the running event tap.
    var onUnlockChanged: ((HotkeyCombo) -> Void)?

    private var isApplying = false   // guards didSet re-entry during init + rollback
    private static let kActivate = "wardlume.hotkey.activate"
    private static let kUnlock   = "wardlume.hotkey.unlock"

    init() {
        isApplying = true
        activate = Self.load(Self.kActivate) ?? .activateDefault
        unlock   = Self.load(Self.kUnlock)   ?? .unlockDefault
        // Cross-field safety on restore: if a corrupt/edited prefs set both equal,
        // hard-fall-back unlock to its default so the user can't be trapped.
        if activate == unlock { unlock = .unlockDefault }
        isApplying = false
        persist(activate, key: Self.kActivate)
        persist(unlock, key: Self.kUnlock)
    }

    func resetToDefaults() {
        activate = .activateDefault
        unlock   = .unlockDefault
    }

    // MARK: — Change handling

    private func handleChange(_ kp: KeyPath<HotkeyManager, HotkeyCombo>,
                              old: HotkeyCombo, key: String) {
        guard !isApplying else { return }
        let isActivate = (kp == \HotkeyManager.activate)
        let combo = self[keyPath: kp]

        // 1. Single-combo validity.
        do { try combo.validate() }
        catch {
            setError(error.localizedDescription, isActivate: isActivate)
            rollback(to: old, isActivate: isActivate, reRegister: false)
            return
        }

        // 2. Cross-field: activate != unlock.
        if activate == unlock {
            setError("Activate and Unlock must be different shortcuts.", isActivate: isActivate)
            rollback(to: old, isActivate: isActivate, reRegister: false)
            return
        }

        // 3. Persist, then apply.
        persist(combo, key: key)
        if isActivate {
            if let cb = onActivateChanged, cb(combo) == false {
                // Carbon registration failed — restore the previous combo's registration.
                setError("That shortcut couldn't be registered (it may be in use by another app).", isActivate: true)
                rollback(to: old, isActivate: true, reRegister: true)
                return
            }
        } else {
            onUnlockChanged?(combo)
        }
        setError(nil, isActivate: isActivate)
    }

    private func rollback(to old: HotkeyCombo, isActivate: Bool, reRegister: Bool) {
        isApplying = true
        if isActivate { activate = old } else { unlock = old }
        isApplying = false
        persist(old, key: isActivate ? Self.kActivate : Self.kUnlock)
        if reRegister, isActivate { _ = onActivateChanged?(old) }
    }

    private func setError(_ message: String?, isActivate: Bool) {
        if isActivate { activateError = message } else { unlockError = message }
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
