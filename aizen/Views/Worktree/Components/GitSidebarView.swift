import SwiftUI

struct GitSidebarView: View {
    let worktreePath: String
    let repository: Repository
    let repositoryManager: RepositoryManager
    let onClose: () -> Void

    // Single source of truth - no bindings, no optimistic updates
    let gitStatus: GitStatus
    let isOperationPending: Bool
    let selectedDiffFile: String?

    // Callbacks for operations
    var onStageFile: (String) -> Void
    var onUnstageFile: (String) -> Void
    var onStageAll: (@escaping () -> Void) -> Void  // Now takes completion callback
    var onUnstageAll: () -> Void
    var onCommit: (String) -> Void
    var onAmendCommit: (String) -> Void
    var onCommitWithSignoff: (String) -> Void
    var onSwitchBranch: (String) -> Void
    var onCreateBranch: (String) -> Void
    var onFetch: () -> Void
    var onPull: () -> Void
    var onPush: () -> Void
    var onFileClick: (String) -> Void

    @State private var commitMessage: String = ""
    @State private var selectedBranchInfo: BranchInfo?
    @State private var showingBranchPicker: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            GitSidebarHeader(
                gitStatus: gitStatus,
                isOperationPending: isOperationPending,
                hasUnstagedChanges: hasUnstagedChanges,
                onStageAll: onStageAll,
                onUnstageAll: onUnstageAll
            )

            Divider()

            // File list
            GitFileList(
                gitStatus: gitStatus,
                isOperationPending: isOperationPending,
                selectedFile: selectedDiffFile,
                onStageFile: onStageFile,
                onUnstageFile: onUnstageFile,
                onFileClick: onFileClick
            )

            Divider()

            // Commit section
            GitCommitSection(
                repository: repository,
                repositoryManager: repositoryManager,
                gitStatus: gitStatus,
                isOperationPending: isOperationPending,
                commitMessage: $commitMessage,
                selectedBranchInfo: $selectedBranchInfo,
                showingBranchPicker: $showingBranchPicker,
                onCommit: onCommit,
                onAmendCommit: onAmendCommit,
                onCommitWithSignoff: onCommitWithSignoff,
                onStageAll: onStageAll,
                onFetch: onFetch,
                onPull: onPull,
                onPush: onPush
            )
            .padding(12)
        }
        .background(.ultraThinMaterial)
        .sheet(isPresented: $showingBranchPicker) {
            BranchSelectorView(
                repository: repository,
                repositoryManager: repositoryManager,
                selectedBranch: $selectedBranchInfo,
                allowCreation: true,
                onCreateBranch: { branchName in
                    onCreateBranch(branchName)
                }
            )
        }
        .onChange(of: selectedBranchInfo) { newBranch in
            if let branch = newBranch {
                onSwitchBranch(branch.name)
            }
        }
    }

    private var hasUnstagedChanges: Bool {
        !gitStatus.modifiedFiles.isEmpty || !gitStatus.untrackedFiles.isEmpty
    }
}

// MARK: - Preview

#Preview {
    GitSidebarView(
        worktreePath: "/path/to/worktree",
        repository: Repository(),
        repositoryManager: RepositoryManager(viewContext: PersistenceController.preview.container.viewContext),
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
        onCommit: { _ in },
        onAmendCommit: { _ in },
        onCommitWithSignoff: { _ in },
        onSwitchBranch: { _ in },
        onCreateBranch: { _ in },
        onFetch: {},
        onPull: {},
        onPush: {},
        onFileClick: { _ in }
    )
}
