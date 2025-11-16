//
//  FileContentView.swift
//  aizen
//
//  View for displaying and editing file content
//

import SwiftUI

struct FileContentView: View {
    let file: OpenFileInfo
    let onContentChange: (String) -> Void
    let onSave: () -> Void
    let onRevert: () -> Void

    @State private var showPreview = true

    private var isMarkdown: Bool {
        let ext = (file.path as NSString).pathExtension.lowercased()
        return ext == "md" || ext == "markdown"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Breadcrumb bar
            HStack(spacing: 6) {
                // Breadcrumb path
                HStack(spacing: 4) {
                    let pathComponents = file.path.split(separator: "/").map(String.init)
                    ForEach(Array(pathComponents.enumerated()), id: \.offset) { index, component in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                        Text(component)
                            .font(.system(size: 11))
                            .foregroundColor(index == pathComponents.count - 1 ? .primary : .secondary)
                    }
                }
                .textSelection(.enabled)

                CopyButton(text: file.path, iconSize: 10)

                Spacer()

                // Markdown preview toggle
                if isMarkdown {
                    Button(action: { showPreview.toggle() }) {
                        Image(systemName: showPreview ? "doc.plaintext" : "doc.richtext")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    .help(showPreview ? "Show Editor" : "Show Preview")
                }

                if file.hasUnsavedChanges {
                    Button("Revert") {
                        onRevert()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                    .keyboardShortcut("r", modifiers: [.command])

                    Button("Save") {
                        onSave()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .keyboardShortcut("s", modifiers: [.command])
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Content
            if isMarkdown && showPreview {
                // Markdown preview
                ScrollView {
                    MarkdownRenderedView(content: file.content, isStreaming: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            } else {
                // Code editor
                CodeEditorView(
                    content: file.content,
                    language: detectLanguage(from: file.path),
                    isEditable: true,
                    onContentChange: onContentChange
                )
                .id(file.id)
            }
        }
        .id(file.id)
    }

    private func detectLanguage(from path: String) -> String? {
        let ext = (path as NSString).pathExtension.lowercased()
        return ext.isEmpty ? nil : ext
    }
}

