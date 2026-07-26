//
//  aizenApp+Support.swift
//  aizen
//
//  Created by OpenAI Codex on 05.04.26.
//

import AppKit
import SwiftUI

extension aizenApp {
    func showAboutWindow() {
        if let existingWindow = aboutWindow, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil as Any?)
            return
        }

        let aboutView = AboutView()
            .modifier(AppearanceModifier())
        let hostingController = NSHostingController(rootView: aboutView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "About Aizen"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)

        aboutWindow = window
    }

    func installCLIFromMenu() {
        let result = CLISymlinkService.install()
        let alert = NSAlert()
        alert.messageText = "CLI Installation"
        alert.informativeText = result.message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
