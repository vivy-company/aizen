import SwiftUI

struct GitSidebarHeader: View {
    let gitStatus: GitStatus
    let isOperationPending: Bool
    let hasUnstagedChanges: Bool
    let onStageAll: (@escaping () -> Void) -> Void
    let onUnstageAll: () -> Void

    var body: some View {
        HStack {
            Text(headerTitle)
                .font(.system(size: 13, weight: .semibold))

            if isOperationPending {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            }

            Spacer()

            Button(hasUnstagedChanges ? "Stage All" : "Unstage All") {
                if hasUnstagedChanges {
                    onStageAll({})
                } else {
                    onUnstageAll()
                }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .disabled(isOperationPending || (gitStatus.stagedFiles.isEmpty && gitStatus.modifiedFiles.isEmpty && gitStatus.untrackedFiles.isEmpty))
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }

    private var headerTitle: String {
        let total = gitStatus.stagedFiles.count + gitStatus.modifiedFiles.count + gitStatus.untrackedFiles.count
        return total == 0 ? "No Changes" : "\(total) Change\(total == 1 ? "" : "s")"
    }
}
