//  HotkeyRecorderView.swift
//  Wardlume
//
//  A click-to-record hotkey field for the Shortcuts pane. Clicking the chip makes
//  the embedded NSView first responder; the next key press is captured as a
//  HotkeyCombo and written to the binding. Setting the binding routes through
//  HotkeyManager's didSet, which validates, persists, applies, and rolls back on
//  failure (surfacing an error string the field shows inline). Esc cancels.

import SwiftUI
import AppKit

// MARK: — AppKit capture layer

/// Transparent NSView overlaid on the chip. Becomes first responder on click and
/// reports the next key chord (or a cancel) back through its coordinator.
final class HotkeyRecorderNSView: NSView {
    weak var coordinator: HotkeyRecorderRepresentable.Coordinator?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        coordinator?.setRecording?(true)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {                 // Esc — cancel, no change
            coordinator?.onCapture?(nil)
            window?.makeFirstResponder(nil)
            return
        }
        coordinator?.onCapture?(HotkeyCombo.from(event: event))
        window?.makeFirstResponder(nil)
    }

    override func resignFirstResponder() -> Bool {
        coordinator?.setRecording?(false)        // click-away / commit both end recording
        return super.resignFirstResponder()
    }
}

struct HotkeyRecorderRepresentable: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onCapture: (HotkeyCombo?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> HotkeyRecorderNSView {
        let v = HotkeyRecorderNSView()
        v.coordinator = context.coordinator
        return v
    }

    func updateNSView(_ nsView: HotkeyRecorderNSView, context: Context) {
        // Refresh the closures each update so they capture the current binding.
        context.coordinator.setRecording = { recording in
            if isRecording != recording { isRecording = recording }
        }
        context.coordinator.onCapture = onCapture
    }

    final class Coordinator {
        var setRecording: ((Bool) -> Void)?
        var onCapture: ((HotkeyCombo?) -> Void)?
    }
}

// MARK: — SwiftUI field

struct HotkeyRecorderField: View {
    let title: String
    let subtitle: String
    @Binding var combo: HotkeyCombo
    let error: String?
    let onReset: () -> Void

    @State private var recording = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.textPrimary)
                if let error {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 8)
            chip
            Button(action: onReset) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 30, height: 38)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.keycapBackground))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderSubtle, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .help("Reset to default")
        }
        .padding(.vertical, 10)
    }

    private var chip: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(recording ? Theme.accentTeal.opacity(0.12) : Theme.keycapBackground)
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(recording ? Theme.accentTeal : Theme.borderSubtle,
                            lineWidth: recording ? 1.5 : 0.5))
            if recording {
                Text("Press shortcut…")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.accentTeal)
            } else {
                HotkeyKeycaps(combo: combo)
            }
        }
        .frame(width: 150, height: 38)
        .overlay(HotkeyRecorderRepresentable(isRecording: $recording, onCapture: handleCapture))
        .help("Click, then press your shortcut")
    }

    private func handleCapture(_ captured: HotkeyCombo?) {
        guard let captured else { return }   // nil = cancelled → keep current
        combo = captured                     // routes through HotkeyManager didSet (validate/apply/rollback)
    }
}
