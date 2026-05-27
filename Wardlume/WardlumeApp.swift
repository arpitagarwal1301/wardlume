//
//  WardlumeApp.swift
//  Wardlume
//
//  Created by Arpit  on 27/05/26.
//

import SwiftUI

@main
struct WardlumeApp: App {
    // Links our SwiftUI App lifecycle with AppKit's AppDelegate.
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Using a Settings scene instead of WindowGroup prevents a window from spawning at startup.
        Settings {
            EmptyView()
        }
    }
}


