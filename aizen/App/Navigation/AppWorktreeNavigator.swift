//
//  AppWorktreeNavigator.swift
//  aizen
//
//  Created by Codex on 03.04.26.
//

import Combine
import Combine
import CoreData
import SwiftUI

@MainActor
final class AppWorktreeNavigator: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    private var commandPaletteController: CommandPaletteWindowController?

    func showCommandPalette(
        viewContext: NSManagedObjectContext,
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
            currentRepositoryId: currentRepositoryId,
            currentWorkspaceId: currentWorkspaceId,
            onNavigate: onNavigate
        )
        commandPaletteController = controller
        controller.showWindow(nil)
    }

    func navigateToChatSession(
        chatSessionId: UUID,
        viewContext: NSManagedObjectContext,
        navigateToWorktree: @escaping (UUID, UUID, UUID) -> Void
    ) {
        let request: NSFetchRequest<ChatSession> = ChatSession.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", chatSessionId as CVarArg)
        request.fetchLimit = 1

        guard let chatSession = try? viewContext.fetch(request).first,
              let worktree = chatSession.worktree,
              let worktreeId = worktree.id,
              let repository = worktree.repository,
              let repoId = repository.id,
              let workspace = repository.workspace,
              let workspaceId = workspace.id else {
            return
        }

        navigateToWorktree(workspaceId, repoId, worktreeId)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(
                name: .switchToChatSession,
                object: nil,
                userInfo: ["chatSessionId": chatSessionId]
            )
        }
    }

    func handleCommandPaletteNavigation(
        _ action: CommandPaletteNavigationAction,
        navigateToWorktree: @escaping (UUID, UUID, UUID) -> Void
    ) {
        switch action {
        case .worktree(let workspaceId, let repoId, let worktreeId):
            navigateToWorktree(workspaceId, repoId, worktreeId)
        case .tab(let workspaceId, let repoId, let worktreeId, let tabId):
            navigateToWorktree(workspaceId, repoId, worktreeId)
            postNavigationNotification(
                name: .switchToWorktreeTab,
                userInfo: [
                    "worktreeId": worktreeId,
                    "tabId": tabId
                ],
                primaryDelay: 0.08,
                retryDelay: 0.22
            )
        case .chatSession(let workspaceId, let repoId, let worktreeId, let sessionId):
            navigateToWorktree(workspaceId, repoId, worktreeId)
            postNavigationNotification(
                name: .switchToChatSession,
                userInfo: ["chatSessionId": sessionId],
                primaryDelay: 0.1,
                retryDelay: 0.24
            )
        case .terminalSession(let workspaceId, let repoId, let worktreeId, let sessionId):
            navigateToWorktree(workspaceId, repoId, worktreeId)
            postNavigationNotification(
                name: .switchToTerminalSession,
                userInfo: [
                    "worktreeId": worktreeId,
                    "sessionId": sessionId
                ],
                primaryDelay: 0.1,
                retryDelay: 0.24
            )
        case .browserSession(let workspaceId, let repoId, let worktreeId, let sessionId):
            navigateToWorktree(workspaceId, repoId, worktreeId)
            postNavigationNotification(
                name: .switchToBrowserSession,
                userInfo: [
                    "worktreeId": worktreeId,
                    "sessionId": sessionId
                ],
                primaryDelay: 0.1,
                retryDelay: 0.24
            )
        }
    }

    private func postNavigationNotification(
        name: Notification.Name,
        userInfo: [String: Any],
        primaryDelay: TimeInterval,
        retryDelay: TimeInterval
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + primaryDelay) {
            NotificationCenter.default.post(name: name, object: nil, userInfo: userInfo)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) {
            NotificationCenter.default.post(name: name, object: nil, userInfo: userInfo)
        }
    }
}
