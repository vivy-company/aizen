import SwiftUI

struct GitFileList: View {
    private enum Layout {
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

    @ViewBuilder
    private var fileListContent: some View {
        // Conflicted files (red indicator, non-toggleable)
        if !gitStatus.conflictedFiles.isEmpty {
            ForEach(gitStatus.conflictedFiles, id: \.self) { file in
                conflictRow(file: file)
            }
        }

        // Get all unique files
        let allFiles = Set(gitStatus.stagedFiles + gitStatus.modifiedFiles + gitStatus.untrackedFiles)

        ForEach(Array(allFiles).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }, id: \.self) { file in
            let isStaged = gitStatus.stagedFiles.contains(file)
            let isModified = gitStatus.modifiedFiles.contains(file)
            let isUntracked = gitStatus.untrackedFiles.contains(file)

            if isStaged && isModified {
                // File has both staged and unstaged changes - show mixed state
                fileRow(
                    file: file,
                    isStaged: nil,  // Mixed state
                    statusColor: .orange,
                    statusIcon: "circle.lefthalf.filled"
                )
            } else if isStaged {
                // File is only staged
                fileRow(
                    file: file,
                    isStaged: true,
                    statusColor: .green,
                    statusIcon: "checkmark.circle.fill"
                )
            } else if isModified {
                // File is only modified (not staged)
                fileRow(
                    file: file,
                    isStaged: false,
                    statusColor: .orange,
                    statusIcon: "circle.fill"
                )
            } else if isUntracked {
                // File is untracked
                fileRow(
                    file: file,
                    isStaged: false,
                    statusColor: .blue,
                    statusIcon: "circle.fill"
                )
            }
        }
    }

    private func fileRow(file: String, isStaged: Bool?, statusColor: Color, statusIcon: String) -> some View {
        rowContainer(file: file) { isSelected in
            HStack(spacing: Layout.rowContentSpacing) {
                if let staged = isStaged {
                    // Normal checkbox for fully staged or unstaged files
                    Toggle(isOn: Binding(
                        get: { staged },
                        set: { newValue in
                            // No optimistic updates - just call the operation
                            if newValue {
                                onStageFile(file)
                            } else {
                                onUnstageFile(file)
                            }
                        }
                    )) {
                        EmptyView()
                    }
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .labelsHidden()
                    .frame(width: Layout.checkboxSize, height: Layout.checkboxSize)
                    .disabled(isOperationPending)
                } else {
                    // Mixed state checkbox (shows dash/minus)
                    Button {
                        // Clicking stages the remaining changes
                        onStageFile(file)
                    } label: {
                        Image(systemName: "minus.square")
                            .font(.system(size: 14))
                            .foregroundStyle(isSelected ? Color(nsColor: .controlAccentColor) : .secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: Layout.checkboxSize, height: Layout.checkboxSize)
                    .disabled(isOperationPending)
                }

                Image(systemName: statusIcon)
                    .font(.system(size: 8))
                    .foregroundStyle(isSelected ? Color(nsColor: .controlAccentColor) : statusColor)

                Text(file)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(isSelected ? Color(nsColor: .controlAccentColor) : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func conflictRow(file: String) -> some View {
        rowContainer(file: file, leadingPadding: 8) { isSelected in
            HStack(spacing: Layout.rowContentSpacing) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? Color(nsColor: .controlAccentColor) : .red)
                    .frame(width: 14)

                Text(file)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(isSelected ? Color(nsColor: .controlAccentColor) : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func rowContainer<Content: View>(
        file: String,
        leadingPadding: CGFloat = 0,
        @ViewBuilder content: (_ isSelected: Bool) -> Content
    ) -> some View {
        let isSelected = selectedFile == file

        return content(isSelected)
            .contentShape(Rectangle())
            .onTapGesture {
                onFileClick(file)
            }
            .padding(.horizontal, Layout.rowHorizontalPadding)
            .padding(.vertical, Layout.rowVerticalPadding)
            .padding(.leading, leadingPadding)
            .background(
                RoundedRectangle(cornerRadius: Layout.rowCornerRadius, style: .continuous)
                    .fill(isSelected ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor).opacity(0.65) : .clear)
            )
    }
}
