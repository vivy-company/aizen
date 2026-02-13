//
//  SessionsWindowManager.swift
//  aizen
//
//  Window to manage chat sessions
//

import AppKit
import CoreData
import SwiftUI

@MainActor
final class SessionsWindowManager {
    static let shared = SessionsWindowManager()

    private var window: NSWindow?

    private init() {}

    func show(context: NSManagedObjectContext, worktreeId: UUID? = nil) {
        let contentView = SessionsListView(worktreeId: worktreeId)
            .environment(\.managedObjectContext, context)
            .modifier(AppearanceModifier())

        if let existing = window {
            existing.contentView = NSHostingView(rootView: contentView)
            existing.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            existing.titlebarAppearsTransparent = true
            existing.toolbarStyle = .unified
            existing.backgroundColor = .windowBackgroundColor
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Sessions"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.backgroundColor = .windowBackgroundColor
        window.minSize = NSSize(width: 600, height: 400)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 800, height: 600))
        window.center()

        self.window = window
        window.makeKeyAndOrderFront(nil)
    }
}
