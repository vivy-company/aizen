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

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 720, height: 520)

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Active Worktrees"
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.center()

        self.window = window
        window.makeKeyAndOrderFront(nil)
    }
}

