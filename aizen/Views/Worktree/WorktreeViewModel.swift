//
//  WorktreeViewModel.swift
//  aizen
//
//  ViewModel for worktree detail view managing session selection
//

import Foundation
import SwiftUI
import Combine

@MainActor
class WorktreeViewModel: ObservableObject {
    @Published var selectedChatSessionId: UUID?
    @Published var selectedTerminalSessionId: UUID?
    @Published var selectedFileSessionId: UUID?
    @Published var selectedBrowserSessionId: UUID?
    @Published var selectedDiffFile: String?

    private let worktree: Worktree
    private let repositoryManager: RepositoryManager

    init(worktree: Worktree, repositoryManager: RepositoryManager) {
        self.worktree = worktree
        self.repositoryManager = repositoryManager
    }

    // MARK: - Diff Viewing

    func selectFileForDiff(_ filePath: String?) {
        selectedDiffFile = filePath
    }

    func closeDiffView() {
        selectedDiffFile = nil
    }
}
