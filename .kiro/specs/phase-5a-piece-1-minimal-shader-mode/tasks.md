# Implementation Plan: Minimal Shader Mode

## Overview

This implementation adds a minimal shader rendering mode to Wardlume that displays only glass refraction over the live desktop, removing all decorative visual effects. The feature enables reaction packs to choose between two rendering modes: minimal (simple refraction only) and full (all seven visual effects). The implementation follows a strict file-by-file sequence with build verification after each change to ensure incremental correctness.

## Tasks

- [ ] 1. Add ShaderStyle enum and property to ReactionPack.swift
  - [x] 1.1 Add ShaderStyle enum definition
    - Add `enum ShaderStyle { case full; case minimal }` before the `PackStyle` enum definition
    - Place enum at file scope (not nested inside ReactionPack struct)
    - Add documentation comment explaining the two rendering modes
    - _Requirements: 1.1, 1.2_
  
  - [x] 1.2 Add shaderStyle property to ReactionPack struct
    - Add `let shaderStyle: ShaderStyle` as the last property in the struct (after `style: PackStyle`)
    - Add documentation comment explaining the property's purpose
    - _Requirements: 1.1_
  
  - [x] 1.3 Update grumpyOldMan pack definition with shaderStyle
    - Add `shaderStyle: .full` parameter to `ReactionPack.grumpyOldMan` static initializer
    - Place parameter after `style: .image` parameter
    - _Requirements: 1.3_
  
  - [x] 1.4 Update wizard pack definition with shaderStyle
    - Add `shaderStyle: .full` parameter to `ReactionPack.wizard` static initializer
    - Place parameter after `style: .image` parameter
    - _Requirements: 1.4_
  
  - [x] 1.5 Update silentProfessional pack definition with shaderStyle
    - Add `shaderStyle: .minimal` parameter to `ReactionPack.silentProfessional` static initializer
    - Place parameter after `style: .minimal` parameter
    - _Requirements: 1.5_
  
  - [x] 1.6 Build and verify ReactionPack.swift changes
    - Run `xcodebuild -project Wardlume.xcodeproj -scheme Wardlume build` to verify no compilation errors
    - Verify all three pack definitions compile successfully
    - _Requirements: 8.1_

- [ ] 2. Checkpoint - Verify ReactionPack changes
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 3. Add minimalMode field to MetalOverlayView.swift ShaderParams
  - [x] 3.1 Add minimalMode field to ShaderParams struct
    - Add `var minimalMode: Float = 0.0` at position 11 in the struct (after `lastIntrusionT`, before `reduceMotion`)
    - Add inline comment: `// Phase 5a: 1.0 = minimal mode, 0.0 = full mode`
    - Verify byte offset is 40 (10 fields × 4 bytes before it)
    - _Requirements: 2.3, 2.4, 6.1_
  
  - [x] 3.2 Build and verify MetalOverlayView.swift changes
    - Run `xcodebuild -project Wardlume.xcodeproj -scheme Wardlume build` to verify no compilation errors
    - Verify ShaderParams struct size is 48 bytes (12 fields × 4 bytes)
    - _Requirements: 8.3_

- [ ] 4. Checkpoint - Verify ShaderParams struct alignment
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 5. Add minimalMode field and conditional branching to WardShader.metal
  - [x] 5.1 Add minimalMode field to Metal ShaderParams struct
    - Add `float minimalMode;` at position 11 in the struct (after `lastIntrusionT`)
    - Add comment: `// Phase 5a: 1.0 = minimal mode, 0.0 = full mode`
    - Verify byte offset matches Swift struct (40 bytes)
    - Do NOT add `reduceMotion` field (Metal struct can be shorter than Swift struct)
    - _Requirements: 2.1, 2.2, 6.1, 6.4_
  
  - [x] 5.2 Add conditional desktop sampling logic
    - Locate section 3b (DESKTOP TEXTURE) around line 180-195
    - Wrap existing chromatic aberration code in `if (p.minimalMode > 0.5) { ... } else { ... }`
    - Minimal mode branch: `desktop = desktopTex.sample(tex_s, uvDisp).rgb;`
    - Full mode branch: preserve existing chromatic aberration code (uvR, uvB, three-channel sampling)
    - Ensure `uvDisp` is used in both branches (refraction applies in both modes)
    - _Requirements: 3.1, 3.2, 3.3_
  
  - [x] 5.3 Add conditional effect composition logic
    - Locate section 8 (FINAL COLOR) around line 380-395
    - Wrap existing composition code in `if (p.minimalMode > 0.5) { ... } else { ... }`
    - Minimal mode branch: `colour = desktop;` (no effects)
    - Full mode branch: preserve existing composition code (desktop + sheen + shimmer + sigilColor + moteColor + border)
    - Move `pulseAge` and `pulseMult` calculation inside the full mode branch (only needed for border)
    - Keep `clamp()` and `return` statements outside the branch (apply to both modes)
    - _Requirements: 4.1, 4.2, 4.3, 4.4_
  
  - [x] 5.4 Build and verify WardShader.metal changes
    - Run `xcodebuild -project Wardlume.xcodeproj -scheme Wardlume build` to verify no Metal compilation errors
    - Verify shader compiles successfully with new conditional branches
    - _Requirements: 8.2_

- [ ] 6. Checkpoint - Verify shader compilation
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 7. Add mode activation logic to AppDelegate.swift
  - [x] 7.1 Add minimalMode setting in toggleWard() activation path
    - Locate the ward activation section in `toggleWard()` (around line 200-250)
    - Find the line `let activePack = reactionManager?.activePack ?? .silentProfessional`
    - Add immediately after: `metalView.params.minimalMode = (activePack.shaderStyle == .minimal) ? 1.0 : 0.0`
    - Place this line BEFORE the base image check (`if let baseURL = ReactionPack.resolvedBaseImageURL...`)
    - Place this line BEFORE starting desktop capture (`capture.startCapture(excludingWindow: window)`)
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5_
  
  - [x] 7.2 Add debug logging for mode verification
    - Add after setting minimalMode: `print("Wardlume [AppDelegate]: shader mode = \(metalView.params.minimalMode) for pack \(activePack.id)")`
    - This logging is temporary for verification and can be removed after testing
    - _Requirements: 5.1_
  
  - [x] 7.3 Build and verify AppDelegate.swift changes
    - Run `xcodebuild -project Wardlume.xcodeproj -scheme Wardlume build` to verify no compilation errors
    - Verify the project builds cleanly with all changes integrated
    - _Requirements: 8.4_

- [ ] 8. Checkpoint - Verify complete build
  - Ensure all tests pass, ask the user if questions arise.

- [x] 9. Visual verification testing
  - [x] 9.1 Test silentProfessional minimal mode rendering
    - Launch Wardlume application
    - Set active pack to silentProfessional in Preferences
    - Activate ward (click "Activate Ward" in menu bar)
    - Verify overlay shows refracted glass over desktop (desktop content clearly visible)
    - Verify NO rainbow border visible at screen edges
    - Verify NO sigils (floating ghost symbols) visible
    - Verify NO motes (floating particles) visible
    - Verify NO chromatic color fringing at edges (simple refraction, not chromatic aberration)
    - Trigger intrusion event (type on keyboard) and verify no visual change (no border pulse)
    - Deactivate ward
    - _Requirements: 9.1_
  
  - [x] 9.2 Test grumpyOldMan base image rendering (Phase 4b compatibility)
    - Set active pack to grumpyOldMan in Preferences
    - Activate ward
    - Verify base image is displayed (Metal shader paused)
    - Verify shader mode setting does not affect base image rendering
    - Deactivate ward
    - _Requirements: 7.1, 9.2_
  
  - [x] 9.3 Test wizard base image rendering (Phase 4b compatibility)
    - Set active pack to wizard in Preferences
    - Activate ward
    - Verify base image is displayed (Metal shader paused)
    - Verify shader mode setting does not affect base image rendering
    - Deactivate ward
    - _Requirements: 7.1, 9.3_
  
  - [x] 9.4 Test user base image override (Phase 4b compatibility)
    - Open Preferences window
    - Drag and drop a custom base image into the Base Image slot
    - Set active pack to silentProfessional
    - Activate ward
    - Verify user override base image is displayed (not Metal shader)
    - Deactivate ward
    - Remove user override base image
    - _Requirements: 7.2, 9.4_

- [ ] 10. Final checkpoint - Complete feature verification
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks are ordered by file dependency: ReactionPack.swift → MetalOverlayView.swift → WardShader.metal → AppDelegate.swift
- Build verification after each file ensures incremental correctness and early error detection
- Checkpoints are placed after each major file change to allow user review
- Visual verification tasks (9.1-9.4) are NOT marked optional — they are critical for confirming correct rendering
- The minimalMode field MUST be at byte offset 40 in both Swift and Metal structs (position 11)
- Conditional branching uses `p.minimalMode > 0.5` (not `== 1.0`) for floating-point safety
- Effect computation sections (sheen, shimmer, sigils, motes, border) remain unchanged — only composition is gated
- Base image rendering (Phase 4b) is independent of shader mode — base images always occlude Metal shader
- Debug logging in task 7.2 is temporary and can be removed after verification

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["1.2"] },
    { "id": 2, "tasks": ["1.3", "1.4", "1.5"] },
    { "id": 3, "tasks": ["1.6"] },
    { "id": 4, "tasks": ["3.1"] },
    { "id": 5, "tasks": ["3.2"] },
    { "id": 6, "tasks": ["5.1"] },
    { "id": 7, "tasks": ["5.2", "5.3"] },
    { "id": 8, "tasks": ["5.4"] },
    { "id": 9, "tasks": ["7.1", "7.2"] },
    { "id": 10, "tasks": ["7.3"] },
    { "id": 11, "tasks": ["9.1", "9.2", "9.3", "9.4"] }
  ]
}
```
