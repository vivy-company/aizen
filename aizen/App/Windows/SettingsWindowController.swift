//
//  SettingsWindowController.swift
//  aizen
//
//  Centralized settings window presenter
//

import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var settingsWindow: NSWindow?

    private init() {}

    func show() {
        if let existingWindow = settingsWindow, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let settingsView = SettingsView()
            .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
            .modifier(AppearanceModifier())
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        window.backgroundColor = AppSurfaceTheme.backgroundNSColor()
        window.setContentSize(NSSize(width: 960, height: 640))
        window.minSize = NSSize(width: 860, height: 500)

        window.center()
        window.makeKeyAndOrderFront(nil)

        settingsWindow = window
    }
}
