//
//  SettingsWindowManager.swift
//  aizen
//
//  Centralized settings window presenter
//

import SwiftUI

@MainActor
final class SettingsWindowManager {
    static let shared = SettingsWindowManager()

    private var settingsWindow: NSWindow?

    private init() {}

    func show() {
        if let existingWindow = settingsWindow, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        window.setContentSize(NSSize(width: 800, height: 550))

        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.displayMode = .iconAndLabel
        window.toolbar = toolbar

        window.center()
        window.makeKeyAndOrderFront(nil)

        settingsWindow = window
    }
}
