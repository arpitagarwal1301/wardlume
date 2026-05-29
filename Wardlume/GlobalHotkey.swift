//  GlobalHotkey.swift
//  Wardlume
//
//  A minimal Carbon RegisterEventHotKey wrapper for a single global hotkey.
//  Carbon is used (not NSEvent.addGlobalMonitorForEvents) because Carbon
//  hotkeys are consumed — the foreground app won't also receive the combo.
//  Used for the global ward activation hotkey (⌘⇧L), which must work while
//  the user is focused in another app (IDE, browser) with the ward inactive.

import AppKit
import Carbon.HIToolbox

final class GlobalHotkey {

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let callback: () -> Void

    /// Registers a global hotkey.
    /// - Parameters:
    ///   - keyCode:   virtual key code (e.g. kVK_ANSI_L = 0x25 for "L")
    ///   - modifiers: Carbon modifier mask (e.g. cmdKey | shiftKey)
    ///   - callback:  fired on the main thread when the hotkey is pressed
    init?(keyCode: UInt32, modifiers: UInt32, callback: @escaping () -> Void) {
        self.callback = callback

        // Unique signature/id for this hotkey. 'WRLM' = 0x57524C4D.
        let hotKeyID = EventHotKeyID(signature: OSType(0x57524C4D), id: 1)

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: OSType(kEventHotKeyPressed))

        // Install the handler. The `self` pointer is passed as userData so the
        // C callback can route back to this instance without a global variable.
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData = userData else { return noErr }
                let instance = Unmanaged<GlobalHotkey>.fromOpaque(userData)
                                    .takeUnretainedValue()
                DispatchQueue.main.async { instance.callback() }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandler
        )
        guard installStatus == noErr else { return nil }

        // Register the hotkey itself with the system.
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            // Clean up the event handler we just installed if hotkey registration fails.
            if let handler = eventHandler { RemoveEventHandler(handler) }
            return nil
        }
    }

    deinit {
        if let ref = hotKeyRef    { UnregisterEventHotKey(ref) }
        if let ref = eventHandler { RemoveEventHandler(ref) }
    }
}
