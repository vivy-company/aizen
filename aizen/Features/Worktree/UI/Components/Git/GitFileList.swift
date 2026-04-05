import SwiftUI

struct GitFileList: View {
    enum Layout {
        static let rowCornerRadius: CGFloat = 8
        static let rowHorizontalPadding: CGFloat = 6
        static let rowVerticalPadding: CGFloat = 5
        static let rowContentSpacing: CGFloat = 8
        static let checkboxSize: CGFloat = 14
        static let listHorizontalPadding: CGFloat = 8
        static let listVerticalPadding: CGFloat = 8
    }

    let gitStatus: GitStatus
    let isOperationPending: Bool
    let selectedFile: String?
    let onStageFile: (String) -> Void
    let onUnstageFile: (String) -> Void
    let onFileClick: (String) -> Void

    var body: some View {
        ScrollView {
            if gitStatus.stagedFiles.isEmpty && gitStatus.modifiedFiles.isEmpty && gitStatus.untrackedFiles.isEmpty {
                emptyState
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    fileListContent
                }
                .padding(.horizontal, Layout.listHorizontalPadding)
                .padding(.vertical, Layout.listVerticalPadding)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text(String(localized: "git.fileList.noChanges"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: 300)
    }
}
