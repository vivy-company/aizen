import SwiftUI

struct GitSidebarHeader: View {
    let gitStatus: GitStatus
    let isOperationPending: Bool
    let hasUnstagedChanges: Bool
    let onStageAll: (@escaping () -> Void) -> Void
    let onUnstageAll: () -> Void
    let onDiscardAll: () -> Void
    let onCleanUntracked: () -> Void

    @State private var showDiscardConfirmation = false
    @State private var showCleanConfirmation = false

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

            Button(hasUnstagedChanges ? String(localized: "git.sidebar.stageAll") : String(localized: "git.sidebar.unstageAll")) {
                if hasUnstagedChanges {
                    onStageAll({})
                } else {
                    onUnstageAll()
                }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .disabled(isOperationPending || (gitStatus.stagedFiles.isEmpty && gitStatus.modifiedFiles.isEmpty && gitStatus.untrackedFiles.isEmpty))

            Menu {
                Button {
                    showDiscardConfirmation = true
                } label: {
                    Label(String(localized: "git.sidebar.discardAll"), systemImage: "arrow.uturn.backward")
                }
                .disabled(gitStatus.stagedFiles.isEmpty && gitStatus.modifiedFiles.isEmpty)

                Button {
                    showCleanConfirmation = true
                } label: {
                    Label(String(localized: "git.sidebar.removeUntracked"), systemImage: "trash")
                }
                .disabled(gitStatus.untrackedFiles.isEmpty)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 20)
            .disabled(isOperationPending)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .alert(String(localized: "git.sidebar.discardAllTitle"), isPresented: $showDiscardConfirmation) {
            Button(String(localized: "general.cancel"), role: .cancel) {}
            Button(String(localized: "git.sidebar.discard"), role: .destructive) {
                onDiscardAll()
            }
        } message: {
            Text(String(localized: "git.sidebar.discardAllMessage"))
        }
        .alert(String(localized: "git.sidebar.removeUntrackedTitle"), isPresented: $showCleanConfirmation) {
            Button(String(localized: "general.cancel"), role: .cancel) {}
            Button(String(localized: "git.sidebar.remove"), role: .destructive) {
                onCleanUntracked()
            }
        } message: {
            Text(String(localized: "git.sidebar.removeUntrackedMessage \(gitStatus.untrackedFiles.count)"))
        }
    }

    private var headerTitle: String {
        let total = gitStatus.stagedFiles.count + gitStatus.modifiedFiles.count + gitStatus.untrackedFiles.count
        if total == 0 {
            return String(localized: "git.sidebar.noChanges")
        } else if total == 1 {
            return String(localized: "git.sidebar.changesSingular")
        } else {
            return String(localized: "git.sidebar.changes \(total)")
        }
    }
}
