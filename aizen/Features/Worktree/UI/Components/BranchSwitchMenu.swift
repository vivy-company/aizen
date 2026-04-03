import SwiftUI

struct BranchSwitchMenu: View {
    let worktreeBranch: String?
    let availableBranches: [BranchInfo]
    let isLoadingBranches: Bool
    let onLoadBranches: () -> Void
    let onSelectBranch: (BranchInfo) -> Void
    let onOpenSelector: () -> Void

    private var localBranches: [BranchInfo] {
        availableBranches.filter { !$0.isRemote && $0.name != worktreeBranch }
    }

    private var remoteBranches: [BranchInfo] {
        availableBranches.filter(\.isRemote)
    }

    var body: some View {
        Menu {
            content
        } label: {
            Label(String(localized: "worktree.branch.switch"), systemImage: "arrow.triangle.swap")
        }
    }

    @ViewBuilder
    private var content: some View {
        if availableBranches.isEmpty && !isLoadingBranches {
            Text(String(localized: "general.loading"))
                .foregroundStyle(.secondary)
                .onAppear(perform: onLoadBranches)
        } else if isLoadingBranches {
            Text(String(localized: "general.loading"))
                .foregroundStyle(.secondary)
        } else {
            branchButtons

            if !remoteBranches.isEmpty {
                Divider()
                remoteBranchButtons
            }

            Divider()
            Button {
                onOpenSelector()
            } label: {
                Label(String(localized: "worktree.branch.browseOrCreate"), systemImage: "ellipsis.circle")
            }
        }
    }

    @ViewBuilder
    private var branchButtons: some View {
        ForEach(localBranches) { branch in
            branchButton(branch, isRemote: false)
        }
    }

    @ViewBuilder
    private var remoteBranchButtons: some View {
        ForEach(remoteBranches) { branch in
            branchButton(branch, isRemote: true)
        }
    }

    private func branchButton(_ branch: BranchInfo, isRemote: Bool) -> some View {
        Button {
            onSelectBranch(branch)
        } label: {
            HStack {
                Image(systemName: "arrow.triangle.branch")
                    .font(.caption)
                Text(branch.name)
                if isRemote {
                    Text(String(localized: "worktree.branch.remote"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
