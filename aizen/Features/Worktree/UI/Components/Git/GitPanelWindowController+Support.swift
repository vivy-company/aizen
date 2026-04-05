import SwiftUI
import VVCode

extension GitPanelWindowContentWithToolbar {
    var worktree: Worktree { context.worktree }
    var gitStatus: GitStatus { gitSummaryStore.status }
    var isOperationPending: Bool { gitOperationService.isOperationPending }
    var gitFeaturesAvailable: Bool { gitSummaryStore.repositoryState == .ready }

    var diffRenderStyleBinding: Binding<VVDiffRenderStyle> {
        Binding(
            get: {
                AppearanceSettings.gitDiffRenderStyle(from: diffRenderStyleRawValue)
            },
            set: { newValue in
                diffRenderStyleRawValue = AppearanceSettings.gitDiffRenderStyleRawValue(for: newValue)
            }
        )
    }

    var gitOperations: WorktreeGitOperations {
        WorktreeGitOperations(
            gitOperationService: gitOperationService,
            repositoryManager: repositoryManager,
            worktree: worktree,
            logger: logger
        )
    }

    enum GitToolbarOperation: String {
        case fetch = "Fetching..."
        case pull = "Pulling..."
        case push = "Pushing..."
        case createPR = "Creating PR..."
        case mergePR = "Merging..."
    }
}
