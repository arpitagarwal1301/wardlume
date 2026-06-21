//  Theme.swift
//  Wardlume
//
//  Dark-teal palette + layout metrics for the forced-dark settings window.
//  Colors are EXPLICIT RGB literals (not NSColor semantic colors) so they never
//  flip with system appearance even though the window is pinned to .darkAqua.

import SwiftUI

enum Theme {

    // MARK: — Surfaces
    static let windowBackground  = Color(red: 0.059, green: 0.090, blue: 0.078)  // #0F1714
    static let sidebarBackground = Color(red: 0.043, green: 0.067, blue: 0.059)  // #0B110F
    static let panelBackground   = Color(red: 0.051, green: 0.082, blue: 0.071)  // #0D1512
    static let cardBackground    = Color(red: 0.086, green: 0.129, blue: 0.114)  // #16211D
    static let keycapBackground  = Color(red: 0.110, green: 0.161, blue: 0.145)  // #1C2925

    // MARK: — Accent
    static let accentTeal    = Color(red: 0.204, green: 0.788, blue: 0.557)  // #34C98E
    static let accentTealDim = Color(red: 0.122, green: 0.561, blue: 0.420)  // #1F8F6B

    // MARK: — Text
    static let textPrimary   = Color(red: 0.906, green: 0.937, blue: 0.922)  // #E7EFEB
    static let textSecondary = Color(red: 0.545, green: 0.604, blue: 0.576)  // #8B9A93
    static let textTertiary  = Color(red: 0.373, green: 0.435, blue: 0.408)  // #5F6F68

    // MARK: — Status / lines
    static let statusActive   = Color(red: 0.306, green: 0.827, blue: 0.604)  // #4ED39A
    static let statusInactive = Color(red: 0.545, green: 0.604, blue: 0.576)  // #8B9A93
    static let danger         = Color(red: 0.898, green: 0.541, blue: 0.514)  // #E58A83
    /// Action-needed accent (e.g. an ungranted permission's "Enable") — amber,
    /// deliberately DIFFERENT from the green granted state.
    static let warning        = Color(red: 0.918, green: 0.639, blue: 0.180)  // #EAA32E
    static let separator      = Color.white.opacity(0.08)
    static let borderSubtle   = Color.white.opacity(0.12)

    // MARK: — Layout metrics
    static let sidebarWidth: CGFloat  = 240
    static let detailWidth: CGFloat   = 262
    static let cornerRadius: CGFloat  = 10
    static let cardPadding: CGFloat   = 14
}
