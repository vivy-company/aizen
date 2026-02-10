//
//  ActiveWorktreesWindowController.swift
//  aizen
//
//  Window to manage active worktrees
//

import AppKit
import CoreData
import SwiftUI

final class ActiveWorktreesWindowManager {
    static let shared = ActiveWorktreesWindowManager()

    private var window: NSWindow?

    private init() {}

    func show(context: NSManagedObjectContext) {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let contentView = ActiveWorktreesView()
            .environment(\.managedObjectContext, context)
            .modifier(AppearanceModifier())

        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Active Environments"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        window.setContentSize(NSSize(width: 980, height: 620))
        window.minSize = NSSize(width: 860, height: 540)

        let toolbar = NSToolbar(identifier: "ActiveWorktreesToolbar")
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        window.center()

        self.window = window
        window.makeKeyAndOrderFront(nil)
    }
}
