//
//  AppWorktreeNavigator.swift
//  aizen
//
//  Created by Codex on 03.04.26.
//

import Combine
import CoreData
import SwiftUI

@MainActor
final class AppWorktreeNavigator: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    private var commandPaletteController: CommandPaletteWindowController?

    func showCommandPalette(
        viewContext: NSManagedObjectContext,
        workspaceGraphQueryController: WorkspaceGraphQueryController,
        currentRepositoryId: String?,
        currentWorkspaceId: String?,
        onNavigate: @escaping (CommandPaletteNavigationAction) -> Void
    ) {
        if let existing = commandPaletteController, existing.window?.isVisible == true {
            existing.closeWindow()
            commandPaletteController = nil
            return
        }

        let controller = CommandPaletteWindowController(
            managedObjectContext: viewContext,
            workspaceGraphQueryController: workspaceGraphQueryController,
            currentRepositoryId: currentRepositoryId,
            currentWorkspaceId: currentWorkspaceId,
            onNavigate: onNavigate
        )
        commandPaletteController = controller
        controller.showWindow(nil)
    }

    func navigateToChatSession(
        chatSessionId: UUID,
        workspaceGraphQueryController: WorkspaceGraphQueryController,
        selectionStore: AppNavigationSelectionStore,
        navigateToWorktree: @escaping (UUID, UUID, UUID) -> Void
    ) {
        guard let route = workspaceGraphQueryController.route(for: chatSessionId) else {
            return
        }

        navigateToWorktree(route.workspaceId, route.repoId, route.worktreeId)
        selectionStore.pendingWorktreeDestination = .chatSession(
            worktreeId: route.worktreeId,
            sessionId: chatSessionId
        )
    }

    func handleCommandPaletteNavigation(
        _ action: CommandPaletteNavigationAction,
        selectionStore: AppNavigationSelectionStore,
        navigateToWorktree: @escaping (UUID, UUID, UUID) -> Void
    ) {
        switch action {
        case .worktree(let workspaceId, let repoId, let worktreeId):
            navigateToWorktree(workspaceId, repoId, worktreeId)
        case .tab(let workspaceId, let repoId, let worktreeId, let tabId):
            navigateToWorktree(workspaceId, repoId, worktreeId)
            selectionStore.pendingWorktreeDestination = .tab(
                worktreeId: worktreeId,
                tabId: tabId
            )
        case .chatSession(let workspaceId, let repoId, let worktreeId, let sessionId):
            navigateToWorktree(workspaceId, repoId, worktreeId)
            selectionStore.pendingWorktreeDestination = .chatSession(
                worktreeId: worktreeId,
                sessionId: sessionId
            )
        case .terminalSession(let workspaceId, let repoId, let worktreeId, let sessionId):
            navigateToWorktree(workspaceId, repoId, worktreeId)
            selectionStore.pendingWorktreeDestination = .terminalSession(
                worktreeId: worktreeId,
                sessionId: sessionId
            )
        case .browserSession(let workspaceId, let repoId, let worktreeId, let sessionId):
            navigateToWorktree(workspaceId, repoId, worktreeId)
            selectionStore.pendingWorktreeDestination = .browserSession(
                worktreeId: worktreeId,
                sessionId: sessionId
            )
        }
    }
}
