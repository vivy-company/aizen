import SwiftUI

struct BranchSwitchMenu: View {
    let worktreeBranch: String?
    let availableBranches: [BranchInfo]
    let isLoadingBranches: Bool
    let onLoadBranches: () -> Void
    let onSelectBranch: (BranchInfo) -> Void
    let onOpenSelector: () -> Void

    var body: some View {
        Menu {
            content
        } label: {
            Label(String(localized: "worktree.branch.switch"), systemImage: "arrow.triangle.swap")
        }
    }
}
