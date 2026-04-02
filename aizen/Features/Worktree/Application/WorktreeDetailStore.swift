//
//  WorktreeDetailStore.swift
//  aizen
//
//  Application store for worktree detail session selection
//

import ACP
import Combine
import Foundation
import SwiftUI

@MainActor
class WorktreeDetailStore: ObservableObject {
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
