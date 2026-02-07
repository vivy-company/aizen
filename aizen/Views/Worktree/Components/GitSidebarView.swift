import SwiftUI

struct GitSidebarView: View {
    let worktreePath: String
    let onClose: () -> Void

    // Single source of truth - no bindings, no optimistic updates
    let gitStatus: GitStatus
    let isOperationPending: Bool
    let selectedDiffFile: String?

    // Callbacks for operations
    var onStageFile: (String) -> Void
    var onUnstageFile: (String) -> Void
    var onStageAll: (@escaping () -> Void) -> Void
    var onUnstageAll: () -> Void
    var onDiscardAll: () -> Void
    var onCleanUntracked: () -> Void
    var onCommit: (String) -> Void
    var onAmendCommit: (String) -> Void
    var onCommitWithSignoff: (String) -> Void
    var onFileClick: (String) -> Void

    @State private var commitMessage: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            GitSidebarHeader(
                gitStatus: gitStatus,
                isOperationPending: isOperationPending,
                hasUnstagedChanges: hasUnstagedChanges,
                onStageAll: onStageAll,
                onUnstageAll: onUnstageAll,
                onDiscardAll: onDiscardAll,
                onCleanUntracked: onCleanUntracked
            )

            // File list
            GitFileList(
                gitStatus: gitStatus,
                isOperationPending: isOperationPending,
                selectedFile: selectedDiffFile,
                onStageFile: onStageFile,
                onUnstageFile: onUnstageFile,
                onFileClick: onFileClick
            )

            // Commit section
            GitCommitSection(
                gitStatus: gitStatus,
                isOperationPending: isOperationPending,
                commitMessage: $commitMessage,
                onCommit: onCommit,
                onAmendCommit: onAmendCommit,
                onCommitWithSignoff: onCommitWithSignoff,
                onStageAll: onStageAll
            )
            .padding(12)
        }
        .frame(maxHeight: .infinity)
        .animation(nil, value: gitStatus)
    }

    private var hasUnstagedChanges: Bool {
        !gitStatus.modifiedFiles.isEmpty || !gitStatus.untrackedFiles.isEmpty
    }
}

// MARK: - Preview

#Preview {
    GitSidebarView(
        worktreePath: "/path/to/worktree",
        onClose: {},
        gitStatus: GitStatus(
            stagedFiles: ["src/main.swift", "src/views/GitSidebarView.swift"],
            modifiedFiles: ["README.md", "Package.swift"],
            untrackedFiles: ["newfile.txt"],
            conflictedFiles: [],
            currentBranch: "main",
            aheadCount: 2,
            behindCount: 1,
            additions: 45,
            deletions: 12
        ),
        isOperationPending: false,
        selectedDiffFile: nil,
        onStageFile: { _ in },
        onUnstageFile: { _ in },
        onStageAll: { completion in completion() },
        onUnstageAll: {},
        onDiscardAll: {},
        onCleanUntracked: {},
        onCommit: { _ in },
        onAmendCommit: { _ in },
        onCommitWithSignoff: { _ in },
        onFileClick: { _ in }
    )
}
