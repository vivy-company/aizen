import SwiftUI

extension WorktreeDetailView {
    var hasGitChanges: Bool {
        gitSummaryStore.status.additions > 0 ||
        gitSummaryStore.status.deletions > 0 ||
        gitSummaryStore.status.untrackedFiles.count > 0
    }

    @ViewBuilder
    var gitStatusView: some View {
        GitStatusView(
            additions: gitSummaryStore.status.additions,
            deletions: gitSummaryStore.status.deletions,
            untrackedFiles: gitSummaryStore.status.untrackedFiles.count
        )
    }

    var showingGitChanges: Bool {
        gitChangesContext != nil
    }

    var gitStatusIcon: String {
        if gitSummaryStore.repositoryState == .notRepository {
            return "square.and.arrow.up.on.square"
        }
        let status = gitSummaryStore.status
        if !status.conflictedFiles.isEmpty {
            return "square.and.arrow.up.trianglebadge.exclamationmark"
        } else if hasGitChanges {
            return "square.and.arrow.up.badge.clock"
        } else {
            return "square.and.arrow.up.badge.checkmark"
        }
    }

    var gitStatusHelp: String {
        if gitSummaryStore.repositoryState == .notRepository {
            return "Git is not initialized for this environment"
        }
        let status = gitSummaryStore.status
        if !status.conflictedFiles.isEmpty {
            return "Git Changes - \(status.conflictedFiles.count) conflict(s)"
        } else if hasGitChanges {
            return "Git Changes - uncommitted changes"
        } else {
            return "Git Changes - clean"
        }
    }

    var gitStatusColor: Color {
        if gitSummaryStore.repositoryState == .notRepository {
            return .secondary
        }
        let status = gitSummaryStore.status
        if !status.conflictedFiles.isEmpty {
            return .red
        } else if hasGitChanges {
            return .orange
        } else {
            return .green
        }
    }

    @ViewBuilder
    var gitSidebarButton: some View {
        let button = Button(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                if gitChangesContext == nil {
                    gitChangesContext = GitChangesContext(worktree: worktree, runtime: worktreeRuntime)
                } else {
                    gitChangesContext = nil
                }
            }
        }) {
            Label("Git Changes", systemImage: gitStatusIcon)
                .symbolRenderingMode(.palette)
                .foregroundStyle(gitStatusColor, .primary, .clear)
        }
        .labelStyle(.iconOnly)
        .help(gitStatusHelp)

        if #available(macOS 14.0, *) {
            button.symbolEffect(.bounce, value: showingGitChanges)
        } else {
            button
        }
    }
}
