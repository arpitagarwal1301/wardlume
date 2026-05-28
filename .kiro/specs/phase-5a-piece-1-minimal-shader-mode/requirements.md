# Requirements Document

## Introduction

This document specifies the requirements for adding a minimal shader mode to Wardlume. The minimal shader mode will display only the glass refraction effect over the live desktop, removing all decorative visual effects (rainbow border, sigils, motes, chromatic aberration, sheen, and shimmer). The silentProfessional reaction pack will use this minimal mode to provide a calm, unobtrusive productivity shield, while grumpyOldMan and wizard packs will continue using the full shader with all effects.

## Glossary

- **Shader**: The Metal fragment shader (WardShader.metal) that renders the visual ward overlay
- **Minimal_Mode**: A shader rendering mode that shows only glass refraction over the live desktop
- **Full_Mode**: The existing shader rendering mode with all seven visual effects active
- **Reaction_Pack**: A themed bundle (ReactionPack struct) that defines visual and audio behavior
- **ShaderParams**: The uniform buffer struct shared between Swift and Metal code
- **Base_Image**: The static image displayed over the Metal shader when a pack provides one
- **Metal_Overlay_View**: The MTKView subclass (MetalOverlayView.swift) that renders the shader
- **App_Delegate**: The application controller (AppDelegate.swift) that manages ward activation
- **Byte_Alignment**: The memory layout requirement that Swift and Metal structs must match exactly

## Requirements

### Requirement 1: Shader Style Configuration

**User Story:** As a developer, I want reaction packs to declare their shader style, so that each pack can choose between minimal and full visual effects.

#### Acceptance Criteria

1. THE Reaction_Pack SHALL include a shaderStyle property of type ShaderStyle enum
2. THE ShaderStyle enum SHALL define two cases: full and minimal
3. THE grumpyOldMan pack SHALL have shaderStyle set to full
4. THE wizard pack SHALL have shaderStyle set to full
5. THE silentProfessional pack SHALL have shaderStyle set to minimal

### Requirement 2: Shader Mode Uniform

**User Story:** As a shader developer, I want the Metal shader to receive the current mode, so that it can branch between minimal and full rendering paths.

#### Acceptance Criteria

1. THE ShaderParams struct in WardShader.metal SHALL include a minimalMode field of type float
2. THE minimalMode field SHALL be positioned at index 11 in the Metal ShaderParams struct (after lastIntrusionT, before any padding)
3. THE ShaderParams struct in MetalOverlayView.swift SHALL include a minimalMode field of type Float
4. THE minimalMode field SHALL be positioned at index 11 in the Swift ShaderParams struct (after lastIntrusionT, before reduceMotion)
5. WHEN minimalMode is 1.0, THE Shader SHALL render in minimal mode
6. WHEN minimalMode is 0.0, THE Shader SHALL render in full mode

### Requirement 3: Minimal Mode Desktop Sampling

**User Story:** As a user with silentProfessional active, I want to see simple refraction without chromatic aberration, so that the desktop remains clearly readable.

#### Acceptance Criteria

1. WHEN minimalMode is 1.0, THE Shader SHALL sample the desktop texture using only uvDisp coordinates for all three RGB channels
2. WHEN minimalMode is 0.0, THE Shader SHALL sample the desktop texture using uvR for red, uvDisp for green, and uvB for blue (chromatic aberration)
3. THE uvDisp coordinates SHALL apply the existing ripple displacement field in both modes

### Requirement 4: Minimal Mode Effect Composition

**User Story:** As a user with silentProfessional active, I want to see only the refracted desktop without decorative effects, so that I have a calm, distraction-free productivity shield.

#### Acceptance Criteria

1. WHEN minimalMode is 1.0, THE Shader SHALL output only the refracted desktop color (no sheen, shimmer, sigils, motes, or rainbow border)
2. WHEN minimalMode is 0.0, THE Shader SHALL output the desktop color plus all existing effects (sheen, shimmer, sigils, motes, rainbow border)
3. THE Shader SHALL preserve the intrusion pulse effect on the rainbow border in full mode
4. THE Shader SHALL NOT remove or restructure the effect computation sections (sheen, shimmer, sigils, motes, border)

### Requirement 5: Mode Activation

**User Story:** As a user activating the ward, I want the shader to automatically use the correct mode for my active pack, so that I see the intended visual style without manual configuration.

#### Acceptance Criteria

1. WHEN the ward activates, THE App_Delegate SHALL read the active pack's shaderStyle property
2. WHEN the shaderStyle is minimal, THE App_Delegate SHALL set Metal_Overlay_View.params.minimalMode to 1.0
3. WHEN the shaderStyle is full, THE App_Delegate SHALL set Metal_Overlay_View.params.minimalMode to 0.0
4. THE App_Delegate SHALL set minimalMode before starting the desktop capture
5. THE App_Delegate SHALL NOT modify minimalMode when a base image is present (base image rendering is independent of shader mode)

### Requirement 6: Struct Alignment Preservation

**User Story:** As a developer, I want the Swift and Metal ShaderParams structs to remain byte-aligned, so that uniform buffer uploads work correctly without GPU crashes.

#### Acceptance Criteria

1. THE minimalMode field SHALL be positioned at the same byte offset in both Swift and Metal ShaderParams structs
2. THE reduceMotion field SHALL remain at its current position in the Swift ShaderParams struct
3. THE Swift ShaderParams struct SHALL NOT remove or reorder any existing fields
4. THE Metal ShaderParams struct SHALL NOT remove or reorder any existing fields except for adding minimalMode

### Requirement 7: Backward Compatibility

**User Story:** As a developer, I want existing Phase 4 functionality to remain unchanged, so that base image rendering, user overrides, and accessibility features continue working.

#### Acceptance Criteria

1. WHEN a pack provides a base image, THE App_Delegate SHALL render the base image and pause Metal rendering (existing Phase 4b behavior)
2. WHEN UserAssetManager provides a base image override, THE App_Delegate SHALL use the override (existing Phase 4b behavior)
3. WHEN Reduce Motion is enabled, THE Metal_Overlay_View SHALL apply reduced motion settings (existing Phase 4c behavior)
4. THE Shader SHALL NOT produce per-frame console spam (existing Phase 4d cleanup)

### Requirement 8: Build Verification

**User Story:** As a developer, I want the project to build cleanly after each file change, so that I can verify correctness incrementally.

#### Acceptance Criteria

1. WHEN ReactionPack.swift is modified, THE project SHALL build without errors
2. WHEN WardShader.metal is modified, THE project SHALL build without errors
3. WHEN MetalOverlayView.swift is modified, THE project SHALL build without errors
4. WHEN AppDelegate.swift is modified, THE project SHALL build without errors

### Requirement 9: Visual Verification

**User Story:** As a user, I want to verify that each pack displays the correct shader mode, so that I can confirm the feature works as intended.

#### Acceptance Criteria

1. WHEN silentProfessional is active and the ward is activated, THE overlay SHALL show refracted glass over the desktop with no rainbow border, sigils, motes, or chromatic aberration
2. WHEN grumpyOldMan is active and the ward is activated, THE overlay SHALL show the base image (Metal paused, existing Phase 4b behavior)
3. WHEN wizard is active and the ward is activated, THE overlay SHALL show the base image (Metal paused, existing Phase 4b behavior)
4. WHEN a user base image override is set, THE override SHALL display regardless of pack (existing Phase 4b behavior)
