//
//  FileContentView.swift
//  aizen
//
//  View for displaying and editing file content
//

import AppKit
import SwiftUI

struct FileContentView: View {
    let file: OpenFileInfo
    let repoPath: String?
    let onContentChange: (String) -> Void
    let onSave: () -> Void
    let onRevert: () -> Void

    @State private var showPreview = true
    @State private var breadcrumbWidth: CGFloat = 0

    private var isMarkdown: Bool {
        let ext = (file.path as NSString).pathExtension.lowercased()
        return ext == "md" || ext == "markdown"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Breadcrumb bar
            HStack(spacing: 6) {
                // Breadcrumb path
                let displayPath = relativePath(for: file.path, basePath: repoPath)
                let pathComponents = displayPath.isEmpty
                    ? [URL(fileURLWithPath: file.path).lastPathComponent]
                    : displayPath.split(separator: "/").map(String.init)
                let components = collapsedComponents(pathComponents, availableWidth: breadcrumbWidth)
                HStack(spacing: 4) {
                    ForEach(Array(components.enumerated()), id: \.offset) { index, component in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                        Text(component)
                            .font(.system(size: 11))
                            .foregroundColor(index == components.count - 1 ? .primary : .secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    GeometryReader { geometry in
                        Color.clear
                            .onAppear { breadcrumbWidth = geometry.size.width }
                            .onChange(of: geometry.size.width) { _, newValue in
                                breadcrumbWidth = newValue
                            }
                    }
                )

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
                // Markdown preview - pass directory of file as basePath for relative image URLs
                let fileDirectory = (file.path as NSString).deletingLastPathComponent
                GeometryReader { geometry in
                    ScrollView {
                        MarkdownView(content: file.content, isStreaming: false, basePath: fileDirectory)
                            .frame(width: geometry.size.width - 32, alignment: .leading)
                            .padding()
                    }
                }
            } else {
                // Code editor
                CodeEditorView(
                    content: file.content,
                    language: detectLanguage(from: file.path),
                    isEditable: true,
                    filePath: file.path,
                    repoPath: repoPath,
                    hasUnsavedChanges: file.hasUnsavedChanges,
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

    private func relativePath(for absolutePath: String, basePath: String?) -> String {
        guard let basePath, !basePath.isEmpty else { return absolutePath }
        let normalizedBase = basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath
        let normalizedAbsolute = absolutePath.hasSuffix("/") ? String(absolutePath.dropLast()) : absolutePath
        if normalizedAbsolute == normalizedBase {
            return URL(fileURLWithPath: absolutePath).lastPathComponent
        }
        if normalizedAbsolute.hasPrefix(normalizedBase + "/") {
            return String(normalizedAbsolute.dropFirst(normalizedBase.count + 1))
        }
        return absolutePath
    }

    private func collapsedComponents(_ components: [String], availableWidth: CGFloat) -> [String] {
        guard components.count > 2, availableWidth > 0 else { return components }
        if totalWidth(for: components) <= availableWidth {
            return components
        }

        let first = components[0]
        let last = components[components.count - 1]
        var result: [String] = [first, "...", last]
        if totalWidth(for: result) > availableWidth {
            result = ["...", last]
            if totalWidth(for: result) > availableWidth {
                return [last]
            }
            return result
        }

        for index in stride(from: components.count - 2, through: 1, by: -1) {
            let candidate = [first, "..."] + components[index...]
            if totalWidth(for: candidate) <= availableWidth {
                result = candidate
            } else {
                break
            }
        }

        return result
    }

    private func totalWidth(for components: [String]) -> CGFloat {
        let componentWidth = components.reduce(0) { $0 + textWidth($1) }
        let chevronCount = max(components.count - 1, 0)
        let elementCount = max(components.count * 2 - 1, 0)
        let spacingCount = max(elementCount - 1, 0)
        return componentWidth
            + (CGFloat(chevronCount) * 8)
            + (CGFloat(spacingCount) * 4)
    }

    private func textWidth(_ text: String) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11)
        ]
        return (text as NSString).size(withAttributes: attributes).width
    }
}
