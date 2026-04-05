import Foundation
import VVCode

extension GitPanelWindowContent {
    var gitOperations: WorktreeGitOperations {
        WorktreeGitOperations(
            gitOperationService: gitOperationService,
            repositoryManager: repositoryManager,
            worktree: worktree,
            logger: logger
        )
    }

    var gitStatus: GitStatus { gitSummaryStore.status }

    var allChangedFiles: [String] {
        cachedChangedFiles
    }

    func initializeGit() {
        guard !isInitializingGit else { return }
        guard !worktreePath.isEmpty else { return }

        isInitializingGit = true
        gitInitializationError = nil

        Task {
            do {
                try await repositoryManager.initializeGit(at: worktreePath)
                if let repository = worktree.repository {
                    try await repositoryManager.refreshRepository(repository)
                }

                await MainActor.run {
                    runtime.refreshSummary(lightweight: false)
                    runtime.refreshWorkingDiffNow()
                    isInitializingGit = false
                }
            } catch {
                await MainActor.run {
                    gitInitializationError = error.localizedDescription
                    isInitializingGit = false
                }
            }
        }
    }

    var effectiveDiffOutput: String {
        selectedHistoryCommit == nil ? gitDiffStore.diffOutput : historyDiffOutput
    }
}
