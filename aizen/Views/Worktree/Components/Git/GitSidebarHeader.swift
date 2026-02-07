import SwiftUI

struct GitSidebarHeader: View {
    private enum Layout {
        static let horizontalPadding: CGFloat = 10
        static let verticalPadding: CGFloat = 6
        static let chipHeight: CGFloat = 28
        static let menuSize: CGFloat = 28
        static let spacing: CGFloat = 8
    }

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
        HStack(spacing: Layout.spacing) {
            Text(headerTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)

            if isOperationPending {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            }

            Spacer()

            Button {
                if hasUnstagedChanges {
                    onStageAll({})
                } else {
                    onUnstageAll()
                }
            } label: {
                Text(hasUnstagedChanges ? String(localized: "git.sidebar.stageAll") : String(localized: "git.sidebar.unstageAll"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(canPerformBulkAction ? .primary : .tertiary)
                    .padding(.horizontal, 12)
                    .frame(height: Layout.chipHeight)
                    .background(chipBackground)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canPerformBulkAction)

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
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isOperationPending ? .tertiary : .secondary)
                    .frame(width: Layout.menuSize, height: Layout.menuSize)
                    .background(chipBackground)
                    .clipShape(Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .disabled(isOperationPending)
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, Layout.verticalPadding)
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .padding(.bottom, 2)
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

    private var chipBackground: some ShapeStyle {
        Color.white.opacity(0.08)
    }

    private var canPerformBulkAction: Bool {
        !isOperationPending && hasAnyChanges
    }

    private var hasAnyChanges: Bool {
        !(gitStatus.stagedFiles.isEmpty && gitStatus.modifiedFiles.isEmpty && gitStatus.untrackedFiles.isEmpty)
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
