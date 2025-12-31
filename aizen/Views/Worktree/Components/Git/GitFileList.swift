import SwiftUI

struct GitFileList: View {
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
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
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

        ForEach(Array(allFiles).sorted(), id: \.self) { file in
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
        rowContainer(file: file) {
            HStack(spacing: 8) {
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
                    .labelsHidden()
                    .disabled(isOperationPending)
                } else {
                    // Mixed state checkbox (shows dash/minus)
                    Button {
                        // Clicking stages the remaining changes
                        onStageFile(file)
                    } label: {
                        Image(systemName: "minus.square")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(isOperationPending)
                }

                Image(systemName: statusIcon)
                    .font(.system(size: 8))
                    .foregroundStyle(statusColor)

                Text(file)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func conflictRow(file: String) -> some View {
        rowContainer(file: file, leadingPadding: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .frame(width: 14)

                Text(file)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func rowContainer<Content: View>(
        file: String,
        leadingPadding: CGFloat = 0,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .contentShape(Rectangle())
            .onTapGesture {
                onFileClick(file)
            }
            .padding(.vertical, 2)
            .padding(.leading, leadingPadding)
            .background(selectedFile == file ? Color.accentColor.opacity(0.2) : Color.clear)
            .cornerRadius(4)
    }
}
