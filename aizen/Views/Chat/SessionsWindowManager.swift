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
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: contentView)
        window.title = "Sessions"
        window.toolbarStyle = .unified
        window.minSize = NSSize(width: 600, height: 400)
        window.isReleasedWhenClosed = false
        window.center()

        self.window = window
        window.makeKeyAndOrderFront(nil)
    }
}
