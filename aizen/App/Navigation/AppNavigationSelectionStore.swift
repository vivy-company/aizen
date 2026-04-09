//
//  AppNavigationSelectionStore.swift
//  aizen
//
//  Created by Codex on 03.04.26.
//

import CoreData
import Combine

enum PendingWorktreeDestination: Equatable {
    case tab(worktreeId: UUID, tabId: String)
    case chatSession(worktreeId: UUID, sessionId: UUID)
    case terminalSession(worktreeId: UUID, sessionId: UUID)
    case browserSession(worktreeId: UUID, sessionId: UUID)

    var worktreeId: UUID {
        switch self {
        case .tab(let worktreeId, _),
             .chatSession(let worktreeId, _),
             .terminalSession(let worktreeId, _),
             .browserSession(let worktreeId, _):
            return worktreeId
        }
    }
}

@MainActor
final class AppNavigationSelectionStore: ObservableObject {
    @Published var selectedWorkspace: Workspace?
    @Published var isCrossProjectSelected = false
    @Published var selectedRepository: Repository?
    @Published var selectedWorktree: Worktree?
    @Published var crossProjectWorktree: Worktree?
    @Published var zenModeBeforeCrossProjectSelection: Bool?
    @Published var suppressWorkspaceAutoSelection = false
    @Published var pendingWorktreeDestination: PendingWorktreeDestination?

    func consumePendingWorktreeDestination(for worktreeId: UUID) -> PendingWorktreeDestination? {
        guard let destination = pendingWorktreeDestination,
              destination.worktreeId == worktreeId else {
            return nil
        }

        pendingWorktreeDestination = nil
        return destination
    }
}
