import SwiftUI

extension GitFileList {
    @ViewBuilder
    var fileListContent: some View {
        if !gitStatus.conflictedFiles.isEmpty {
            ForEach(gitStatus.conflictedFiles, id: \.self) { file in
                conflictRow(file: file)
            }
        }

        let allFiles = Set(gitStatus.stagedFiles + gitStatus.modifiedFiles + gitStatus.untrackedFiles)

        ForEach(Array(allFiles).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }, id: \.self) { file in
            let isStaged = gitStatus.stagedFiles.contains(file)
            let isModified = gitStatus.modifiedFiles.contains(file)
            let isUntracked = gitStatus.untrackedFiles.contains(file)

            if isStaged && isModified {
                fileRow(
                    file: file,
                    isStaged: nil,
                    statusColor: .orange,
                    statusIcon: "circle.lefthalf.filled"
                )
            } else if isStaged {
                fileRow(
                    file: file,
                    isStaged: true,
                    statusColor: .green,
                    statusIcon: "checkmark.circle.fill"
                )
            } else if isModified {
                fileRow(
                    file: file,
                    isStaged: false,
                    statusColor: .orange,
                    statusIcon: "circle.fill"
                )
            } else if isUntracked {
                fileRow(
                    file: file,
                    isStaged: false,
                    statusColor: .blue,
                    statusIcon: "circle.fill"
                )
            }
        }
    }

    func fileRow(file: String, isStaged: Bool?, statusColor: Color, statusIcon: String) -> some View {
        rowContainer(file: file) { isSelected in
            HStack(spacing: Layout.rowContentSpacing) {
                if let staged = isStaged {
                    Toggle(isOn: Binding(
                        get: { staged },
                        set: { newValue in
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
                    Button {
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

    func conflictRow(file: String) -> some View {
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

    func rowContainer<Content: View>(
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
