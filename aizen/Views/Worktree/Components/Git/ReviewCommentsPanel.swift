//
//  ReviewCommentsPanel.swift
//  aizen
//
//  Left sidebar panel showing all review comments
//

import SwiftUI

struct ReviewCommentsPanel: View {
    @ObservedObject var reviewManager: ReviewSessionManager
    let onScrollToLine: ((String, Int) -> Void)?
    let onCopyAll: () -> Void
    let onSendToAgent: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if reviewManager.comments.isEmpty {
                emptyState
            } else {
                commentsList

                Divider()
                footerButtons
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Comments")
                .font(.system(size: 13, weight: .medium))

            Spacer()

            if !reviewManager.comments.isEmpty {
                PillBadge(
                    text: "\(reviewManager.comments.count)",
                    color: Color(NSColor.controlBackgroundColor),
                    textColor: .secondary,
                    font: .system(size: 11, weight: .medium, design: .monospaced),
                    horizontalPadding: 6,
                    verticalPadding: 2,
                    backgroundOpacity: 1
                )
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }

    private var footerButtons: some View {
        VStack(spacing: 8) {
            footerButton(
                title: "Copy All",
                systemImage: "doc.on.doc",
                iconSize: 12,
                background: Color(NSColor.controlBackgroundColor),
                foreground: .primary,
                action: onCopyAll
            )

            footerButton(
                title: "Send to Agent",
                systemImage: "paperplane.fill",
                iconSize: 11,
                background: .blue,
                foreground: .white,
                action: onSendToAgent
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func footerButton(
        title: String,
        systemImage: String,
        iconSize: CGFloat,
        background: Color,
        foreground: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: iconSize))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .foregroundStyle(foreground)
    }

    private var emptyState: some View {
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

    private var commentsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(groupedComments, id: \.file) { group in
                    fileSection(group)
                }
            }
        }
    }

    private var groupedComments: [(file: String, comments: [ReviewComment])] {
        let grouped = Dictionary(grouping: reviewManager.comments) { $0.filePath }
        return grouped.map { (file: $0.key, comments: $0.value.sorted { $0.lineNumber < $1.lineNumber }) }
            .sorted { $0.file < $1.file }
    }

    private func fileSection(_ group: (file: String, comments: [ReviewComment])) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // File header
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
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

            // Comments for this file
            ForEach(group.comments) { comment in
                commentRow(comment, filePath: group.file)
            }
        }
    }

    private func commentRow(_ comment: ReviewComment, filePath: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                // Line info
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

                // Code context
                CodePill(
                    text: comment.codeContext,
                    font: .system(size: 10, design: .monospaced),
                    textColor: .secondary,
                    backgroundColor: Color(NSColor.textBackgroundColor).opacity(0.5),
                    horizontalPadding: 8,
                    verticalPadding: 4,
                    lineLimit: 2,
                    truncationMode: .tail
                )

                // Comment text
                Text(comment.comment)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture {
                onScrollToLine?(filePath, comment.lineNumber)
            }

            Divider()
                .padding(.leading, 12)
        }
    }

    private func formatSingleComment(_ comment: ReviewComment, filePath: String) -> String {
        """
        \(filePath):\(comment.displayLineNumber)
        ```
        \(comment.codeContext)
        ```
        \(comment.comment)
        """
    }

    private func lineTypeBadge(_ type: DiffLineType) -> some View {
        Group {
            if type == .header || type.marker.isEmpty {
                EmptyView()
            } else {
                Text(type.marker)
                    .foregroundStyle(type.markerColor)
            }
        }
        .font(.system(size: 10, weight: .bold, design: .monospaced))
    }
}
