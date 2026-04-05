import SwiftUI

extension GitSidebarView {
    var body: some View {
        VStack(spacing: 0) {
            GitSidebarHeader(
                gitStatus: gitStatus,
                isOperationPending: isOperationPending,
                hasUnstagedChanges: hasUnstagedChanges,
                onStageAll: onStageAll,
                onUnstageAll: onUnstageAll,
                onDiscardAll: onDiscardAll,
                onCleanUntracked: onCleanUntracked
            )

            GitFileList(
                gitStatus: gitStatus,
                isOperationPending: isOperationPending,
                selectedFile: selectedDiffFile,
                onStageFile: onStageFile,
                onUnstageFile: onUnstageFile,
                onFileClick: onFileClick
            )

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

    var hasUnstagedChanges: Bool {
        !gitStatus.modifiedFiles.isEmpty || !gitStatus.untrackedFiles.isEmpty
    }
}
