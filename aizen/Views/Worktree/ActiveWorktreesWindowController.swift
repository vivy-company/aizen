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
        let contentView = ActiveWorktreesView()
            .environment(\.managedObjectContext, context)
            .modifier(AppearanceModifier())

        if let existing = window {
            existing.contentView = NSHostingView(rootView: contentView)
            existing.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            existing.titlebarAppearsTransparent = true
            existing.toolbarStyle = .unified
            existing.backgroundColor = .windowBackgroundColor
            existing.title = "Activity Monitor"
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Activity Monitor"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        window.backgroundColor = .windowBackgroundColor
        window.setContentSize(NSSize(width: 980, height: 620))
        window.minSize = NSSize(width: 860, height: 540)
        window.center()

        self.window = window
        window.makeKeyAndOrderFront(nil)
    }
}
