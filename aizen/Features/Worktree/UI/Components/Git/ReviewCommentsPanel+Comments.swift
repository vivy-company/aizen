import SwiftUI

extension ReviewCommentsPanel {
    var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "plus.bubble")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)

            Text("No comments yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Text("Hover over a line in the diff\nand click + to add a comment")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    var commentsList: some View {
        ScrollView {
            LazyVStack(spacing: Layout.sectionSpacing) {
                ForEach(groupedComments, id: \.file) { group in
                    fileSection(group)
                }
            }
            .padding(.vertical, 2)
        }
    }

    var groupedComments: [(file: String, comments: [ReviewComment])] {
        let grouped = Dictionary(grouping: reviewManager.comments) { $0.filePath }
        return grouped.map { (file: $0.key, comments: $0.value.sorted { $0.lineNumber < $1.lineNumber }) }
            .sorted { $0.file < $1.file }
    }

    func fileSection(_ group: (file: String, comments: [ReviewComment])) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Text(group.file)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Text("\(group.comments.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Layout.contentPadding)
            .padding(.top, 8)
            .padding(.bottom, 6)

            VStack(spacing: Layout.rowSpacing) {
                ForEach(group.comments) { comment in
                    commentRow(comment, filePath: group.file)
                }
            }
            .padding(.horizontal, Layout.contentPadding)
            .padding(.bottom, 10)
        }
        .background { cardBackground(cornerRadius: Layout.cardCornerRadius) }
        .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius, style: .continuous))
    }

    func commentRow(_ comment: ReviewComment, filePath: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("Line \(comment.displayLineNumber)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)

                lineTypeBadge(comment.lineType)

                Spacer()

                CopyButton(text: formatSingleComment(comment, filePath: filePath), iconSize: 10)

                Button {
                    reviewManager.deleteComment(id: comment.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(0.6)
                .help("Delete comment")
            }

            CodePill(
                text: comment.codeContext,
                font: .system(size: 10, design: .monospaced),
                textColor: .secondary,
                backgroundColor: Color(NSColor.textBackgroundColor).opacity(0.35),
                horizontalPadding: 8,
                verticalPadding: 4,
                lineLimit: 2,
                truncationMode: .tail
            )

            Text(comment.comment)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(4)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onScrollToLine?(filePath, comment.lineNumber)
        }
    }

}
