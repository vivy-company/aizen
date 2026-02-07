//
//  ReviewCommentsPanel.swift
//  aizen
//
//  Left sidebar panel showing all review comments
//

import SwiftUI

struct ReviewCommentsPanel: View {
    private enum Layout {
        static let panelPadding: CGFloat = 8
        static let sectionSpacing: CGFloat = 8
        static let cardCornerRadius: CGFloat = 10
        static let footerButtonCornerRadius: CGFloat = 12
        static let contentPadding: CGFloat = 10
        static let rowSpacing: CGFloat = 6
        static let footerButtonHeight: CGFloat = 30
        static let footerButtonSpacing: CGFloat = 10
        static let footerTopPadding: CGFloat = 6
        static let footerBottomPadding: CGFloat = 12
    }

    @ObservedObject var reviewManager: ReviewSessionManager
    let onScrollToLine: ((String, Int) -> Void)?
    let onCopyAll: () -> Void
    let onSendToAgent: () -> Void

    var body: some View {
        VStack(spacing: Layout.sectionSpacing) {
            if reviewManager.comments.isEmpty {
                emptyState
            } else {
                commentsList
                footerButtons
            }
        }
        .padding(.horizontal, Layout.panelPadding)
        .padding(.vertical, Layout.panelPadding)
    }

    private var footerButtons: some View {
        VStack(spacing: Layout.footerButtonSpacing) {
            footerButton(
                title: "Copy All",
                systemImage: "doc.on.doc",
                iconSize: 12,
                prominent: false,
                action: onCopyAll
            )

            footerButton(
                title: "Send to Agent",
                systemImage: "paperplane.fill",
                iconSize: 11,
                prominent: true,
                action: onSendToAgent
            )
        }
        .padding(.horizontal, Layout.contentPadding)
        .padding(.top, Layout.footerTopPadding)
        .padding(.bottom, Layout.footerBottomPadding)
    }

    private func footerButton(
        title: String,
        systemImage: String,
        iconSize: CGFloat,
        prominent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: iconSize))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: Layout.footerButtonHeight)
            .background(
                RoundedRectangle(cornerRadius: Layout.footerButtonCornerRadius, style: .continuous)
                    .fill(prominent ? Color.accentColor : Color.white.opacity(0.08))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(prominent ? Color.white : Color.primary)
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
            LazyVStack(spacing: Layout.sectionSpacing) {
                ForEach(groupedComments, id: \.file) { group in
                    fileSection(group)
                }
            }
            .padding(.vertical, 2)
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
            .padding(.horizontal, Layout.contentPadding)
            .padding(.top, 8)
            .padding(.bottom, 6)

            // Comments for this file
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

    private func commentRow(_ comment: ReviewComment, filePath: String) -> some View {
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
                backgroundColor: Color(NSColor.textBackgroundColor).opacity(0.35),
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

    @ViewBuilder
    private func cardBackground(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            GlassEffectContainer {
                shape
                    .fill(.white.opacity(0.001))
                    .glassEffect(.regular, in: shape)
                shape
                    .fill(.white.opacity(0.03))
            }
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }
}
