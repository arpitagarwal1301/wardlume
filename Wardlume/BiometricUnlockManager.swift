//
//  BiometricUnlockManager.swift
//  Wardlume
//
//  Created by Antigravity on 27/05/26.
//

import LocalAuthentication
import AppKit

/// Handles biometric (Touch ID) and device passcode authentication
/// using the LocalAuthentication framework.
///
/// CRITICAL DESIGN NOTE:
/// The LocalAuthentication prompt (rendered by the macOS SecurityAgent/system process)
/// bypasses our CGEventTap completely because it is displayed by a system-level
/// secure process. Since the OS intercepts and handles all keyboard, mouse, and
/// biometric input for this dialog at a higher system window level, the user can
/// type their password or touch the Touch ID sensor without the event tap blocking
/// or consuming the input.
final class BiometricUnlockManager {
    static let shared = BiometricUnlockManager()

    private var activeContext: LAContext?

    /// True while an evaluateUnlock call is in flight. Cmd+Shift+U is dispatched
    /// from the CGEventTap callback, so a burst of presses could otherwise stack
    /// multiple SecurityAgent prompts. We ignore re-entrant calls until the
    /// current evaluation finishes. Touched only on the main thread.
    private var isEvaluating = false

    private init() {}

    /// Checks if biometrics (Touch ID) are available and enrolled on the device.
    func isBiometricAvailable() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// Evaluates biometric or passcode authentication to deactivate the ward.
    ///
    /// - Parameters:
    ///   - reason: The localized text displayed to the user explaining why authentication is requested.
    ///   - completion: Callback executed on the main thread with a boolean result (success) and an optional error.
    func evaluateUnlock(reason: String, completion: @escaping (Bool, Error?) -> Void) {
        // Debounce re-entrant presses (Cmd+Shift+U is dispatched from the tap
        // callback and could fire in a burst). Ignore while a prompt is in flight.
        if isEvaluating {
            print("Wardlume [BiometricUnlockManager]: unlock already in progress — ignoring repeat request.")
            return
        }
        isEvaluating = true

        // Invalidate any active context to dismiss stuck or redundant prompts
        activeContext?.invalidate()

        let context = LAContext()
        activeContext = context

        var error: NSError?
        let canBiometric = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)

        let policy: LAPolicy
        if canBiometric {
            policy = .deviceOwnerAuthenticationWithBiometrics
        } else if let laError = error as? LAError, laError.code == .biometryLockout {
            // Touch ID is locked out due to too many failed attempts.
            // Fall back to device owner authentication (passcode/password prompt).
            policy = .deviceOwnerAuthentication
        } else {
            // Biometrics are unavailable or not enrolled. Fall back to passcode policy.
            var fallbackError: NSError?
            if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &fallbackError) {
                policy = .deviceOwnerAuthentication
            } else {
                // Neither biometrics nor passcode/password is set up on this Mac.
                // Call completion with false and the underlying error.
                DispatchQueue.main.async { [weak self] in
                    self?.isEvaluating = false
                    completion(false, error ?? fallbackError)
                }
                return
            }
        }

        context.evaluatePolicy(policy, localizedReason: reason) { success, evalError in
            DispatchQueue.main.async { [weak self] in
                self?.isEvaluating = false
                // Clear active context reference if it's the current one
                if self?.activeContext === context {
                    self?.activeContext = nil
                }
                completion(success, evalError)
            }
        }
    }

    /// Explicitly cancels any active authentication prompt.
    func cancelActiveAuthentication() {
        activeContext?.invalidate()
        activeContext = nil
        isEvaluating = false
    }
}
