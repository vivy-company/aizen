//
//  WorktreeViewModel.swift
//  aizen
//
//  ViewModel for worktree detail view managing session selection
//

import ACP
import Combine
import Foundation
import SwiftUI

@MainActor
class WorktreeViewModel: ObservableObject {
    @Published var selectedChatSessionId: UUID?
    @Published var selectedTerminalSessionId: UUID?
    @Published var selectedFileSessionId: UUID?
    @Published var selectedBrowserSessionId: UUID?

    private let worktree: Worktree
    private let repositoryManager: RepositoryManager

    init(worktree: Worktree, repositoryManager: RepositoryManager) {
        self.worktree = worktree
        self.repositoryManager = repositoryManager
    }
}
