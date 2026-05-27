# Requirements Document

## Introduction

This document specifies the requirements for Phase 2.5c: Settings UI for reaction packs in Wardlume. The feature replaces temporary DEBUG menu items with a proper SwiftUI Settings window that allows users to configure reaction pack behavior. Settings persist to UserDefaults and apply immediately without requiring an application restart.

## Glossary

- **Settings_Window**: The SwiftUI-based preferences window that displays reaction pack configuration options
- **Reaction_Manager**: The singleton instance that manages reaction overlay lifecycle and configuration (activePackID, audioEnabled, cooldown)
- **Menu_Bar**: The macOS status bar menu that provides access to Wardlume commands
- **Active_Pack**: The currently selected reaction pack that will be displayed on the next intrusion trigger
- **Cooldown**: The minimum time interval (in seconds) between consecutive reaction displays
- **Preview_Mode**: A special trigger mode that bypasses cooldown and ward-active checks for testing reactions in the settings UI
- **UserDefaults**: The macOS persistent storage mechanism for application preferences

## Requirements

### Requirement 1: Settings Window Creation

**User Story:** As a Wardlume user, I want to access a preferences window, so that I can configure reaction pack behavior through a proper UI instead of DEBUG menu items.

#### Acceptance Criteria

1. THE Settings_Window SHALL be implemented as a SwiftUI view
2. THE Settings_Window SHALL display the title "Wardlume Preferences"
3. THE Settings_Window SHALL include standard macOS window controls (close button, minimize button, zoom button)
4. THE Settings_Window SHALL have a default size of 460×400 points
5. WHEN the Settings_Window is already open and the user selects the "Preferences..." menu item or presses Cmd+,, THE Settings_Window SHALL come to the front, become the key window, and gain keyboard focus without creating a duplicate window
6. WHEN the user presses Cmd+W while the Settings_Window is focused, THE Settings_Window SHALL close
7. THE Settings_Window SHALL NOT be resizable

### Requirement 2: Menu Bar Integration

**User Story:** As a Wardlume user, I want to open preferences from the menu bar, so that I can easily access settings when I need them.

#### Acceptance Criteria

1. THE Menu_Bar SHALL include a "Preferences..." menu item with key equivalent "," (Cmd+,)
2. THE "Preferences..." menu item SHALL be positioned between "Activate Ward" and "Unlock with Touch ID..." in the status bar dropdown
3. WHEN the user selects "Preferences..." or presses Cmd+, from anywhere in the application, THE Settings_Window SHALL open
4. WHEN the user selects "Preferences..." or presses Cmd+, and the Settings_Window is already open, THE Settings_Window SHALL come to the front, become the key window, and gain keyboard focus
5. THE "Preferences..." menu item SHALL be enabled regardless of whether the ward is active or inactive
6. THE Settings_Window SHALL be non-modal and SHALL allow interaction with other application windows while open
7. THE Menu_Bar SHALL NOT include the DEBUG menu items "Set Pack: Grumpy Old Man", "Set Pack: Wizard", "Set Pack: Silent Professional", or "Toggle Reaction Audio"
8. THE Menu_Bar SHALL continue to include the "Test Lock (10s)" DEBUG menu item

### Requirement 3: Active Pack Selection

**User Story:** As a Wardlume user, I want to select which reaction pack is active, so that I can customize the reaction behavior to my preference.

#### Acceptance Criteria

1. THE Settings_Window SHALL display a Picker control for selecting the active reaction pack
2. THE Picker SHALL display all packs from ReactionPack.all using their name property (not id)
3. WHEN the Settings_Window is displayed, THE Picker SHALL reflect the current value of Reaction_Manager.activePackID
4. IF no previous selection exists in UserDefaults under key "wardlume.activePackID", THEN THE Picker SHALL default to "Silent Professional"
5. IF the stored activePackID does not match any pack in ReactionPack.all or is corrupted, THEN THE Picker SHALL default to "Silent Professional" and SHALL log a warning
6. WHEN the user changes the pack selection, THE Reaction_Manager.activePackID SHALL update synchronously before the selection event handler returns, and IF the update fails, THEN the exception SHALL propagate to the caller
7. WHEN the user changes the pack selection, THE Settings_Window SHALL persist the selected pack's id to UserDefaults under key "wardlume.activePackID"
8. THE Settings_Window SHALL display a footer caption below the pack picker with the text "Custom reaction packs coming in v1.6 — bring your own image and sound."
9. THE footer caption SHALL be rendered in 11-point system font with gray foreground color (NSColor.secondaryLabelColor)

### Requirement 4: Audio Toggle

**User Story:** As a Wardlume user, I want to enable or disable reaction audio, so that I can control whether sounds play when the ward is breached.

#### Acceptance Criteria

1. THE Settings_Window SHALL display a Toggle control for enabling or disabling reaction audio
2. WHEN the Settings_Window is displayed, THE Toggle SHALL reflect the current value of Reaction_Manager.audioEnabled
3. IF no previous setting exists in UserDefaults under key "wardlume.audioEnabled", THEN THE Toggle SHALL default to OFF (false)
4. THE Toggle SHALL display the label "Play reaction sound when ward is breached"
5. THE Toggle SHALL display the subtitle "Plays the pack's audio file if available. Some packs are silent by design."
6. WHEN the user toggles the audio setting, THE Reaction_Manager.audioEnabled SHALL update within 100 milliseconds
7. WHEN the user toggles the audio setting, THE Settings_Window SHALL persist the new value to UserDefaults under key "wardlume.audioEnabled"
8. IF a reaction overlay is currently playing audio when the user disables the audio toggle, THEN THE audio playback SHALL stop immediately
9. WHILE a reaction overlay is playing audio and the audio toggle is disabled, THE system SHALL prevent new reactions from starting audio until the current reaction overlay dismisses

### Requirement 5: Cooldown Duration Selection

**User Story:** As a Wardlume user, I want to configure the cooldown duration between reactions, so that I can control how frequently reactions appear.

#### Acceptance Criteria

1. THE Settings_Window SHALL display a segmented control for selecting cooldown duration
2. THE segmented control SHALL offer exactly four options: "1 second", "3 seconds", "5 seconds", "10 seconds"
3. WHEN the Settings_Window is displayed, THE segmented control SHALL reflect the current value of Reaction_Manager.cooldown
4. IF no previous setting exists in UserDefaults under key "wardlume.cooldown", THEN THE segmented control SHALL default to "5 seconds"
5. THE segmented control SHALL display the subtitle "Minimum time between reactions. Prevents reaction spam from rapid input."
6. WHEN the user changes the cooldown selection, THE Reaction_Manager.cooldown SHALL update synchronously before the selection event handler returns
7. WHEN the user changes the cooldown selection, THE Settings_Window SHALL persist the selected value to UserDefaults under key "wardlume.cooldown" such that it is restored on subsequent application launches
8. IF Reaction_Manager.cooldown is set to a value other than 1.0, 3.0, 5.0, or 10.0 seconds, THEN THE segmented control SHALL automatically display and select the option corresponding to the closest valid value

### Requirement 6: Reaction Preview

**User Story:** As a Wardlume user, I want to test my reaction settings, so that I can see how the reaction will appear without triggering the ward.

#### Acceptance Criteria

1. THE Settings_Window SHALL display a Button labeled "Test Reaction"
2. WHEN the user clicks "Test Reaction", THE Reaction_Manager SHALL call triggerForPreview()
3. THE triggerForPreview() method SHALL display the reaction overlay even when the ward is not active
4. THE triggerForPreview() method SHALL bypass the cooldown check entirely such that consecutive preview button clicks trigger reactions with no minimum interval, regardless of whether a cooldown period is active for real intrusions
5. THE triggerForPreview() method SHALL NOT update the lastFiredAt timestamp such that preview does not consume the user's cooldown budget for real intrusions
6. THE reaction preview SHALL use the currently selected Active_Pack, audio setting, and display duration
7. THE reaction preview overlay SHALL auto-dismiss after the pack's duration elapses
8. IF triggerForPreview() is called while a previous preview reaction is still visible, THEN THE previous preview SHALL be dismissed immediately before the new preview is displayed
9. WHILE a preview reaction is visible, THE Settings_Window SHALL remain interactive and SHALL NOT be blocked or obscured
10. IF triggerForPreview() encounters an error loading the pack assets, THEN THE system SHALL log the error and SHALL display the pack's placeholder rendering

### Requirement 7: Settings Persistence

**User Story:** As a Wardlume user, I want my settings to persist across application launches, so that I don't have to reconfigure preferences every time I start Wardlume.

#### Acceptance Criteria

1. WHEN the user changes the active reaction pack selection, THE System SHALL save the pack identifier to UserDefaults under key "wardlume.activePackID"
2. WHEN the user changes the audio enabled setting, THE System SHALL save the audio enabled state to UserDefaults under key "wardlume.audioEnabled"
3. WHEN the user changes the cooldown duration, THE System SHALL save the cooldown value in seconds to UserDefaults under key "wardlume.cooldown"
4. WHEN the application launches, THE System SHALL restore the active reaction pack identifier from UserDefaults key "wardlume.activePackID"
5. WHEN the application launches, THE System SHALL restore the audio enabled state from UserDefaults key "wardlume.audioEnabled"
6. WHEN the application launches, THE System SHALL restore the cooldown duration in seconds from UserDefaults key "wardlume.cooldown"
7. IF no saved settings exist at application launch, THEN THE System SHALL use default values: silentProfessional pack identifier, audio disabled (false), and 5.0 seconds cooldown
8. IF saved settings data is corrupted or invalid at application launch or during runtime, THEN THE System SHALL reset the corrupted setting to its default value and SHALL log an error message indicating the corruption
9. IF a setting value is outside valid bounds during restoration or runtime validation, THEN THE System SHALL reset that setting to its corresponding default value

### Requirement 8: Live Settings Application

**User Story:** As a Wardlume user, I want settings changes to apply immediately, so that I don't have to restart the application to see my new configuration.

#### Acceptance Criteria

1. WHEN the user changes any setting in the Settings_Window, THE change SHALL take effect within 100 milliseconds
2. THE next reaction trigger after a settings change SHALL use the updated configuration
3. THE application SHALL NOT require a restart for settings changes to take effect
4. IF the ward is currently active when settings change, THE new settings SHALL apply to the next intrusion event
5. IF a reaction overlay is currently visible when the user changes the active pack or cooldown settings, THEN THE visible reaction SHALL continue using the original settings until it dismisses
6. IF the user changes the cooldown setting while a cooldown period is active, THEN THE remaining cooldown time SHALL be recalculated based on the new cooldown value and the time elapsed since lastFiredAt

### Requirement 9: Non-Regression

**User Story:** As a Wardlume user, I want existing functionality to continue working, so that the settings UI addition does not break current features.

#### Acceptance Criteria

1. WHEN the user activates the ward, THE system SHALL install the CGEventTap, display the Metal overlay window at screenSaver level, and begin blocking non-whitelisted input events
2. WHEN the user deactivates the ward, THE system SHALL uninstall the CGEventTap, close the Metal overlay window, dismiss any visible reaction overlay, and resume normal input processing
3. WHILE the ward is active, THE Metal shader SHALL render the full-screen overlay and SHALL pulse the border visual effect when an intrusion event occurs with a maximum frequency of once per 500 milliseconds
4. WHILE the ward is active, THE input locking mechanism SHALL block all keyboard, mouse, trackpad, and gesture events except events targeting the menu bar strip or Wardlume-owned windows other than the ward overlay
5. WHEN the user presses Cmd+Shift+U while the ward is active, THE system SHALL trigger biometric authentication, and IF authentication succeeds, THEN THE system SHALL deactivate the ward
6. WHEN an intrusion event occurs while the ward is active and the reaction cooldown has elapsed, THE system SHALL display the reaction overlay at window level screenSaver+1 using the active pack configuration
7. WHEN ReactionManager.trigger() is called within the cooldown period, THE system SHALL ignore the trigger and SHALL NOT display a reaction overlay
8. WHEN the ward is deactivated, THE system SHALL immediately dismiss any visible reaction overlay by canceling the auto-dismiss timer, stopping audio playback, and closing the reaction window
