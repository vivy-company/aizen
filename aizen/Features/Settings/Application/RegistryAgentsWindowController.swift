//
//  RegistryAgentsWindowController.swift
//  aizen
//

import AppKit
import SwiftUI

@MainActor
final class RegistryAgentsWindowController {
    static let shared = RegistryAgentsWindowController()

    private var window: NSWindow?

    private init() {}

    func show() {
        let contentView = RegistryAgentPickerView()
            .modifier(AppearanceModifier())

        if let existing = window {
            existing.contentView = NSHostingView(rootView: contentView)
            existing.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            existing.titlebarAppearsTransparent = true
            existing.toolbarStyle = .unified
            existing.backgroundColor = AppSurfaceTheme.backgroundNSColor()
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Add From Registry"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.backgroundColor = AppSurfaceTheme.backgroundNSColor()
        window.minSize = NSSize(width: 640, height: 480)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 760, height: 760))
        window.center()

        self.window = window
        window.makeKeyAndOrderFront(nil)
    }
}
