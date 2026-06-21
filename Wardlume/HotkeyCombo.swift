//  HotkeyCombo.swift
//  Wardlume
//
//  Representation-independent hotkey value type. The single source of truth is
//  the virtual keyCode — IDENTICAL across Carbon (RegisterEventHotKey), CGEvent
//  (the event tap), and NSEvent (the recorder). Only the modifier *containers*
//  differ, so this type owns the three computed mappings.
//
//  CRITICAL: `realModifierMask` is the exact set of modifier bits compared on
//  BOTH sides — the recorder (NSEvent) and the tap (CGEvent). Both must mask to
//  this same set before equality, or a recorded combo silently never fires.

import Carbon.HIToolbox
import CoreGraphics
import AppKit

struct HotkeyModifiers: OptionSet, Codable, Equatable, Sendable {
    let rawValue: UInt8
    static let command = HotkeyModifiers(rawValue: 1 << 0)
    static let shift   = HotkeyModifiers(rawValue: 1 << 1)
    static let option  = HotkeyModifiers(rawValue: 1 << 2)
    static let control = HotkeyModifiers(rawValue: 1 << 3)
}

struct HotkeyCombo: Equatable, Codable, Sendable {

    var keyCode: UInt16
    var modifiers: HotkeyModifiers

    // MARK: — Defaults (preserve today's behavior)
    static let activateDefault = HotkeyCombo(keyCode: UInt16(kVK_ANSI_L), modifiers: [.command, .shift])
    static let unlockDefault   = HotkeyCombo(keyCode: UInt16(kVK_ANSI_U), modifiers: [.command, .shift])

    /// The exact 4 modifier bits compared on both the recorder and tap sides.
    /// Defined nonisolated so the nonisolated CGEventTap callback can use it.
    nonisolated static let realModifierMask: CGEventFlags =
        [.maskCommand, .maskShift, .maskAlternate, .maskControl]

    // MARK: — Mappings
    var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if modifiers.contains(.command) { m |= UInt32(cmdKey) }
        if modifiers.contains(.shift)   { m |= UInt32(shiftKey) }
        if modifiers.contains(.option)  { m |= UInt32(optionKey) }
        if modifiers.contains(.control) { m |= UInt32(controlKey) }
        return m
    }

    /// CGEvent flags for the tap's exact-match unlock check. Note: option → .maskAlternate.
    var cgEventFlags: CGEventFlags {
        var f: CGEventFlags = []
        if modifiers.contains(.command) { f.insert(.maskCommand) }
        if modifiers.contains(.shift)   { f.insert(.maskShift) }
        if modifiers.contains(.option)  { f.insert(.maskAlternate) }
        if modifiers.contains(.control) { f.insert(.maskControl) }
        return f
    }

    var displayString: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option)  { s += "⌥" }
        if modifiers.contains(.shift)   { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        s += Self.keyName(for: keyCode)
        return s
    }

    /// Human-readable spelling for people who don't recognize the glyphs,
    /// e.g. "Command-Shift-U". Pair with displayString: "⌘⇧U (Command-Shift-U)".
    var spokenString: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("Control") }
        if modifiers.contains(.option)  { parts.append("Option") }
        if modifiers.contains(.shift)   { parts.append("Shift") }
        if modifiers.contains(.command) { parts.append("Command") }
        parts.append(Self.keyName(for: keyCode))
        return parts.joined(separator: "-")
    }

    // MARK: — Build from an NSEvent (recorder)
    static func from(event: NSEvent) -> HotkeyCombo {
        var mods: HotkeyModifiers = []
        let flags = event.modifierFlags
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.shift)   { mods.insert(.shift) }
        if flags.contains(.option)  { mods.insert(.option) }
        if flags.contains(.control) { mods.insert(.control) }
        return HotkeyCombo(keyCode: event.keyCode, modifiers: mods)
    }

    // MARK: — Validation
    enum ValidationError: LocalizedError {
        case needsModifier
        case reserved
        var errorDescription: String? {
            switch self {
            case .needsModifier: return "Use at least one of ⌘, ⌥, or ⌃ (a bare or Shift-only key would block typing)."
            case .reserved:      return "⌘⌥Esc is reserved by macOS and can't be used."
            }
        }
    }

    /// Single-combo validity (cross-field activate != unlock is enforced in HotkeyManager).
    func validate() throws {
        if modifiers.isDisjoint(with: [.command, .option, .control]) {
            throw ValidationError.needsModifier
        }
        if keyCode == UInt16(kVK_Escape),
           modifiers.contains(.command), modifiers.contains(.option) {
            throw ValidationError.reserved
        }
    }

    // MARK: — Key names
    static func keyName(for code: UInt16) -> String {
        if let name = keyNames[code] { return name }
        return "Key \(code)"
    }

    private static let keyNames: [UInt16: String] = [
        UInt16(kVK_ANSI_A): "A", UInt16(kVK_ANSI_B): "B", UInt16(kVK_ANSI_C): "C",
        UInt16(kVK_ANSI_D): "D", UInt16(kVK_ANSI_E): "E", UInt16(kVK_ANSI_F): "F",
        UInt16(kVK_ANSI_G): "G", UInt16(kVK_ANSI_H): "H", UInt16(kVK_ANSI_I): "I",
        UInt16(kVK_ANSI_J): "J", UInt16(kVK_ANSI_K): "K", UInt16(kVK_ANSI_L): "L",
        UInt16(kVK_ANSI_M): "M", UInt16(kVK_ANSI_N): "N", UInt16(kVK_ANSI_O): "O",
        UInt16(kVK_ANSI_P): "P", UInt16(kVK_ANSI_Q): "Q", UInt16(kVK_ANSI_R): "R",
        UInt16(kVK_ANSI_S): "S", UInt16(kVK_ANSI_T): "T", UInt16(kVK_ANSI_U): "U",
        UInt16(kVK_ANSI_V): "V", UInt16(kVK_ANSI_W): "W", UInt16(kVK_ANSI_X): "X",
        UInt16(kVK_ANSI_Y): "Y", UInt16(kVK_ANSI_Z): "Z",
        UInt16(kVK_ANSI_0): "0", UInt16(kVK_ANSI_1): "1", UInt16(kVK_ANSI_2): "2",
        UInt16(kVK_ANSI_3): "3", UInt16(kVK_ANSI_4): "4", UInt16(kVK_ANSI_5): "5",
        UInt16(kVK_ANSI_6): "6", UInt16(kVK_ANSI_7): "7", UInt16(kVK_ANSI_8): "8",
        UInt16(kVK_ANSI_9): "9",
        UInt16(kVK_Space): "Space", UInt16(kVK_Return): "↩", UInt16(kVK_Tab): "⇥",
        UInt16(kVK_Escape): "⎋", UInt16(kVK_Delete): "⌫",
        UInt16(kVK_LeftArrow): "←", UInt16(kVK_RightArrow): "→",
        UInt16(kVK_UpArrow): "↑", UInt16(kVK_DownArrow): "↓",
        UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3",
        UInt16(kVK_F4): "F4", UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6",
        UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8", UInt16(kVK_F9): "F9",
        UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
    ]
}
