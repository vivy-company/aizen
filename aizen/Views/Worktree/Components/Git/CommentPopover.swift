//
//  CommentPopover.swift
//  aizen
//
//  Popover for adding/editing review comments
//

import SwiftUI

struct CommentPopover: View {
    let diffLine: DiffLine
    let filePath: String
    let existingComment: ReviewComment?
    let onSave: (String) -> Void
    let onCancel: () -> Void
    let onDelete: (() -> Void)?

    @State private var commentText: String = ""
    @FocusState private var isFocused: Bool

    init(
        diffLine: DiffLine,
        filePath: String,
        existingComment: ReviewComment?,
        onSave: @escaping (String) -> Void,
        onCancel: @escaping () -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.diffLine = diffLine
        self.filePath = filePath
        self.existingComment = existingComment
        self.onSave = onSave
        self.onCancel = onCancel
        self.onDelete = onDelete
        _commentText = State(initialValue: existingComment?.comment ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text(existingComment != nil ? String(localized: "git.comment.edit") : String(localized: "git.comment.add"))
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                Text("Line \(diffLine.newLineNumber ?? diffLine.oldLineNumber ?? "?")")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            // Code context
            HStack(spacing: 8) {
                Text(diffLine.type.marker)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(diffLine.type.markerColor)

                Text(diffLine.content)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(diffLine.type.backgroundColor.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Comment input
            TextEditor(text: $commentText)
                .font(.system(size: 12))
                .frame(minHeight: 80, maxHeight: 150)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(GitWindowDividerStyle.color(opacity: 0.9), lineWidth: 1)
                )
                .focused($isFocused)

            // Buttons
            HStack {
                if let onDelete = onDelete, existingComment != nil {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }

                Spacer()

                Button(String(localized: "general.cancel")) {
                    onCancel()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button(String(localized: "general.save")) {
                    guard !commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    onSave(commentText.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 350)
        .onAppear {
            isFocused = true
        }
    }
}
