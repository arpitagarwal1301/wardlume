# Implementation Plan: Settings UI for Reaction Packs

## Overview

This implementation adds a SwiftUI-based preferences window to Wardlume, replacing temporary DEBUG menu items with a proper settings interface. The implementation follows a 3-file architecture: create PreferencesView.swift, modify ReactionManager.swift to support ObservableObject pattern with UserDefaults persistence, and modify AppDelegate.swift to manage the preferences window lifecycle and menu integration.

**Key Implementation Strategy:**
- One file at a time with build verification between steps
- ReactionManager first (foundation layer with state management)
- PreferencesView second (UI layer with SwiftUI bindings)
- AppDelegate last (integration layer with window management)

## Tasks

- [x] 1. Modify ReactionManager.swift to support settings persistence and preview
  - [x] 1.1 Add ObservableObject conformance and @Published properties
    - Add `import Combine` at top of file
    - Change class declaration to `final class ReactionManager: ObservableObject`
    - Add `@Published` wrapper to `cooldown`, `activePackID`, and `audioEnabled` properties
    - _Requirements: 7.1, 7.2, 7.3, 8.1_
  
  - [x] 1.2 Implement UserDefaults persistence with didSet observers
    - Add `didSet` observer to `activePackID` that saves to UserDefaults key "wardlume.activePackID"
    - Add `didSet` observer to `audioEnabled` that saves to UserDefaults key "wardlume.audioEnabled" and stops audio playback when disabled (call `audioPlayer?.stop()` and set `audioPlayer = nil`)
    - Add `didSet` observer to `cooldown` that saves to UserDefaults key "wardlume.cooldown"
    - _Requirements: 4.8, 7.1, 7.2, 7.3, 8.1_
  
  - [x] 1.3 Add init() method with UserDefaults restoration and validation
    - Create static property `validCooldowns: [Double] = [1.0, 3.0, 5.0, 10.0]`
    - Create static method `closestValidCooldown(_ value: Double) -> Double` that returns closest valid cooldown
    - Add `init()` method that restores `activePackID` from UserDefaults (validate against ReactionPack.all, default to silentProfessional with warning log if invalid)
    - Restore `audioEnabled` from UserDefaults (default false if not set)
    - Restore `cooldown` from UserDefaults with closest-valid-value logic (default 5.0 if not set or ≤ 0)
    - _Requirements: 3.4, 3.5, 4.3, 5.4, 5.8, 7.4, 7.5, 7.6, 7.7, 7.8, 7.9_
  
  - [x] 1.4 Add triggerForPreview() method for settings UI testing
    - Create `triggerForPreview()` method that resolves active pack (fallback to silentProfessional)
    - Call `showReaction(pack:)` directly without checking cooldown or updating lastFiredAt
    - Add print statement logging preview trigger with pack ID
    - _Requirements: 6.2, 6.3, 6.4, 6.5, 6.8_

- [x] 2. Checkpoint - Build and verify ReactionManager changes
  - Build project with Cmd+B and verify no compilation errors
  - Ensure all tests pass, ask the user if questions arise.

- [x] 3. Create PreferencesView.swift with SwiftUI settings controls
  - [x] 3.1 Create PreferencesView struct with ReactionManager binding
    - Create new file `Wardlume/PreferencesView.swift`
    - Add `import SwiftUI` at top
    - Define `struct PreferencesView: View` with `@ObservedObject var reactionManager: ReactionManager` property
    - Create basic `body` with `Form` container
    - _Requirements: 1.1, 1.2_
  
  - [x] 3.2 Implement active pack picker control
    - Add `Picker` with label "Active Reaction Pack" bound to `$reactionManager.activePackID`
    - Use `ForEach(ReactionPack.all, id: \.id)` to populate options, displaying `pack.name`
    - Add `.pickerStyle(.menu)` modifier
    - Add footer caption below picker: "Custom reaction packs coming in v1.6 — bring your own image and sound." in 11pt gray font (`.font(.system(size: 11))` and `.foregroundColor(.secondary)`)
    - _Requirements: 3.1, 3.2, 3.3, 3.8, 3.9_
  
  - [x] 3.3 Implement audio toggle control
    - Add `Toggle` with label "Play reaction sound when ward is breached" bound to `$reactionManager.audioEnabled`
    - Add subtitle text below toggle: "Plays the pack's audio file if available. Some packs are silent by design." using `.font(.caption)` and `.foregroundColor(.secondary)`
    - _Requirements: 4.1, 4.2, 4.4, 4.5_
  
  - [x] 3.4 Implement cooldown segmented control
    - Add `Picker` with label "Cooldown Duration" bound to `$reactionManager.cooldown`
    - Use `.pickerStyle(.segmented)` modifier
    - Add four options: 1.0 ("1 second"), 3.0 ("3 seconds"), 5.0 ("5 seconds"), 10.0 ("10 seconds")
    - Add subtitle text below control: "Minimum time between reactions. Prevents reaction spam from rapid input." using `.font(.caption)` and `.foregroundColor(.secondary)`
    - _Requirements: 5.1, 5.2, 5.3, 5.5_
  
  - [x] 3.5 Add test reaction button
    - Add `Button` with label "Test Reaction" that calls `reactionManager.triggerForPreview()`
    - Style button with `.buttonStyle(.borderedProminent)` modifier
    - _Requirements: 6.1, 6.2_
  
  - [x] 3.6 Apply layout and styling
    - Wrap all controls in `Form` with `.padding()` modifier
    - Set form frame to `.frame(width: 420, height: 360)` for proper sizing within 460×400 window
    - Group related controls with `Section` containers for visual organization
    - _Requirements: 1.4_

- [x] 4. Checkpoint - Build and verify PreferencesView
  - Build project with Cmd+B and verify no compilation errors
  - Ensure all tests pass, ask the user if questions arise.

- [x] 5. Modify AppDelegate.swift for preferences window management
  - [x] 5.1 Add preferences window property and openPreferences method
    - Add `var preferencesWindow: NSWindow?` property to AppDelegate class
    - Add `@objc func openPreferences()` method that checks if window exists
    - If window exists: call `window.makeKeyAndOrderFront(nil)` and `NSApp.activate(ignoringOtherApps: true)`
    - If window doesn't exist: create NSHostingController with PreferencesView, create NSWindow with title "Wardlume Preferences", size 460×400, style mask [.titled, .closable, .miniaturizable], center window, set `isReleasedWhenClosed = false`, assign to `preferencesWindow`, show window
    - _Requirements: 1.2, 1.3, 1.4, 1.5, 2.3, 2.4_
  
  - [x] 5.2 Add NSWindowDelegate conformance for cleanup
    - Add `extension AppDelegate: NSWindowDelegate` at end of file
    - Implement `windowWillClose(_ notification: Notification)` that checks if closing window is preferencesWindow and sets `preferencesWindow = nil`
    - Set `window.delegate = self` in openPreferences() method after creating window
    - _Requirements: 1.6_
  
  - [x] 5.3 Add Preferences menu item and remove DEBUG items
    - In `applicationDidFinishLaunching`, after toggleMenuItem, add separator then "Preferences..." menu item with action `#selector(openPreferences)` and key equivalent ","
    - Position menu item before unlockMenuItem
    - Remove (or wrap in `#if DEBUG ... #endif` to delete) the four DEBUG menu items: "Set Pack: Grumpy Old Man", "Set Pack: Wizard", "Set Pack: Silent Professional", "Toggle Reaction Audio"
    - Keep "Test Lock (10s)" DEBUG item
    - Add `#selector(openPreferences)` case to `validateMenuItem` method returning true
    - _Requirements: 2.1, 2.2, 2.5, 2.7, 2.8_

- [x] 6. Final checkpoint - Integration testing and non-regression verification
  - Build project with Cmd+B and verify no compilation errors
  - Run application and test: Cmd+, opens preferences window, changing settings updates ReactionManager properties, clicking "Test Reaction" shows preview, closing and reopening window restores settings
  - Verify non-regression: ward activation/deactivation works, input locking works, reaction system respects cooldown, biometric unlock works, menu bar remains accessible
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks are ordered to build foundation (state management) before UI (SwiftUI views) before integration (window lifecycle)
- Each checkpoint ensures incremental validation with build verification
- SwiftUI's @ObservedObject + @Published provides automatic two-way binding without manual .onChange handlers
- Preview functionality reuses existing showReaction(pack:) method which already handles overlay dismissal
- Settings persistence happens automatically via didSet observers on @Published properties
- Window management follows existing AppDelegate patterns (similar to overlayWindow lifecycle)
- DEBUG menu items are removed in release builds but "Test Lock (10s)" is preserved for testing

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["1.2", "1.3"] },
    { "id": 2, "tasks": ["1.4"] },
    { "id": 3, "tasks": ["3.1"] },
    { "id": 4, "tasks": ["3.2", "3.3", "3.4", "3.5"] },
    { "id": 5, "tasks": ["3.6"] },
    { "id": 6, "tasks": ["5.1", "5.2"] },
    { "id": 7, "tasks": ["5.3"] }
  ]
}
```
