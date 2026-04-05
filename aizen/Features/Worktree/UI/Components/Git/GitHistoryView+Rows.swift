import SwiftUI

extension GitHistoryView {
    var workingChangesRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "pencil.circle")
                .font(.system(size: 14))
                .foregroundStyle(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "git.history.workingChanges"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)

                Text(String(localized: "git.history.viewUncommitted"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelectCommit(nil)
        }
    }

    func commitRow(_ commit: GitCommit) -> some View {
        let isSelected = selectedCommit?.id == commit.id
        let isHovered = hoveredCommitID == commit.id

        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? selectedForegroundColor : .secondary)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(commit.message)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? selectedForegroundColor : .primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer()

                    Text(commit.relativeDate)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary.opacity(0.75))
                }

                HStack(spacing: 8) {
                    Text(commit.author)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Text("•")
                        .foregroundStyle(Color.secondary.opacity(0.45))

                    Text(commit.shortHash)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)

                    if commit.filesChanged > 0 {
                        Text("•")
                            .foregroundStyle(Color.secondary.opacity(0.45))

                        HStack(spacing: 4) {
                            Image(systemName: "doc")
                                .font(.system(size: 10))
                            Text("\(commit.filesChanged)")
                                .font(.system(size: 11, design: .monospaced))
                        }
                        .foregroundStyle(.secondary)
                    }

                    if commit.additions > 0 {
                        Text("+\(commit.additions)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.green)
                    }

                    if commit.deletions > 0 {
                        Text("-\(commit.deletions)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            Group {
                if isSelected {
                    Rectangle().fill(selectionFillColor)
                } else if isHovered {
                    Rectangle().fill(Color.white.opacity(0.06))
                } else {
                    Color.clear
                }
            }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelectCommit(commit)
        }
        .onHover { hovering in
            hoveredCommitID = hovering ? commit.id : (hoveredCommitID == commit.id ? nil : hoveredCommitID)
        }
    }
}
