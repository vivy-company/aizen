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
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
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

// MARK: - Popover Wrapper

struct CommentPopoverWrapper: NSViewRepresentable {
    @Binding var isPresented: Bool
    let diffLine: DiffLine
    let filePath: String
    let existingComment: ReviewComment?
    let anchorView: NSView
    let onSave: (String) -> Void
    let onDelete: (() -> Void)?

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if isPresented && context.coordinator.popover == nil {
            let popover = NSPopover()
            popover.behavior = .transient
            popover.contentSize = NSSize(width: 350, height: 250)
            popover.delegate = context.coordinator

            let content = CommentPopover(
                diffLine: diffLine,
                filePath: filePath,
                existingComment: existingComment,
                onSave: { text in
                    onSave(text)
                    isPresented = false
                },
                onCancel: {
                    isPresented = false
                },
                onDelete: onDelete.map { delete in
                    {
                        delete()
                        isPresented = false
                    }
                }
            )

            popover.contentViewController = NSHostingController(rootView: content)
            context.coordinator.popover = popover

            popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .maxX)
        } else if !isPresented, let popover = context.coordinator.popover {
            popover.close()
            context.coordinator.popover = nil
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented)
    }

    class Coordinator: NSObject, NSPopoverDelegate {
        @Binding var isPresented: Bool
        var popover: NSPopover?

        init(isPresented: Binding<Bool>) {
            _isPresented = isPresented
        }

        func popoverDidClose(_ notification: Notification) {
            isPresented = false
            popover = nil
        }
    }
}
