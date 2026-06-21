//  WardState.swift
//  Wardlume
//
//  AppKit → SwiftUI bridge hub. The single observable mirror of ward-active
//  state plus live (never-persisted) permission flags. Owned by AppDelegate,
//  injected as an .environmentObject into the settings window.
//
//  Holds NO ward-lifecycle logic and NO persisted prefs — AppDelegate stays the
//  authoritative owner (overlayWindow != nil) and MIRRORS isActive into here at
//  the two funnels (end of activateWard / end of deactivateWard), which covers
//  every teardown path (hotkey / sleep / watchdog / unlock / quit) since they all
//  route through deactivateWard(). SwiftUI panes never touch AppKit directly:
//  they call toggle(), which forwards to AppDelegate via onToggle.

import AppKit
import CoreGraphics
import Combine

@MainActor
final class WardState: ObservableObject {

    /// True while the ward overlay is up. Written ONLY by AppDelegate at the two
    /// funnels; read by SwiftUI panes + the contextual right panel.
    @Published var isActive: Bool = false

    /// Live permission flags, refreshed pull-based via recheckPermissions().
    @Published private(set) var screenRecordingGranted: Bool = false
    @Published private(set) var accessibilityGranted: Bool = false
    @Published private(set) var inputMonitoringGranted: Bool = false

    /// Set by AppDelegate to forward toggle() → toggleWard(). [weak self] there.
    var onToggle: (() -> Void)?

    var allPermissionsReady: Bool {
        screenRecordingGranted && accessibilityGranted && inputMonitoringGranted
    }

    /// Forwarded to AppDelegate.toggleWard() so SwiftUI never owns ward lifecycle.
    func toggle() { onToggle?() }

    /// Recompute the three permission flags. Pull-based (no timer): called when
    /// the settings window opens and on windowDidBecomeKey. Screen Recording is
    /// preflight-cached within a process, so a fresh grant may need an app
    /// relaunch — the UI labels that row accordingly.
    func recheckPermissions() {
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
        accessibilityGranted   = InputLockManager.accessibilityGranted()
        inputMonitoringGranted = InputLockManager.inputMonitoringGranted()
    }
}
