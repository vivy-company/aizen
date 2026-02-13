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
    private let crossProjectRepositoryMarker = "__aizen.cross_project.workspace_repo__"

    private init() {}

    func show(context: NSManagedObjectContext, worktreeId: UUID? = nil) {
        let (resumeWorktreeId, workspaceId) = resolveScope(
            in: context,
            worktreeId: worktreeId
        )
        let contentView = SessionsListView(
            worktreeId: resumeWorktreeId,
            workspaceId: workspaceId
        )
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

    private func resolveScope(
        in context: NSManagedObjectContext,
        worktreeId: UUID?
    ) -> (resumeWorktreeId: UUID?, workspaceId: UUID?) {
        guard let worktreeId else {
            return (nil, nil)
        }

        let request: NSFetchRequest<Worktree> = Worktree.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", worktreeId as CVarArg)

        guard let worktree = try? context.fetch(request).first,
              let repository = worktree.repository else {
            return (worktreeId, nil)
        }

        let isCrossProject = repository.isCrossProject || repository.note == crossProjectRepositoryMarker
        if isCrossProject, let workspaceId = repository.workspace?.id {
            return (worktreeId, workspaceId)
        }

        return (worktreeId, nil)
    }
}
