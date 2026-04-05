import SwiftUI

extension BranchSwitchMenu {
    var localBranches: [BranchInfo] {
        availableBranches.filter { !$0.isRemote && $0.name != worktreeBranch }
    }

    var remoteBranches: [BranchInfo] {
        availableBranches.filter(\.isRemote)
    }

    @ViewBuilder
    var content: some View {
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
    var branchButtons: some View {
        ForEach(localBranches) { branch in
            branchButton(branch, isRemote: false)
        }
    }

    @ViewBuilder
    var remoteBranchButtons: some View {
        ForEach(remoteBranches) { branch in
            branchButton(branch, isRemote: true)
        }
    }

    func branchButton(_ branch: BranchInfo, isRemote: Bool) -> some View {
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
