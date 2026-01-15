//
//  SessionsWindowManager.swift
//  aizen
//
//  Window to manage chat sessions
//

import AppKit
import CoreData
import SwiftUI

final class SessionsWindowManager {
    static let shared = SessionsWindowManager()

    private var window: NSWindow?

    private init() {}

    func show(context: NSManagedObjectContext) {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let contentView = SessionsListView()
            .environment(\.managedObjectContext, context)
            .modifier(AppearanceModifier())

        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Chat Sessions"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        window.setContentSize(NSSize(width: 800, height: 600))
        window.minSize = NSSize(width: 600, height: 400)

        let toolbar = NSToolbar(identifier: "SessionsToolbar")
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        window.center()

        self.window = window
        window.makeKeyAndOrderFront(nil)
    }
}
