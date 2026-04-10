//
//  FileContentTabView.swift
//  aizen
//
//  Tab view for managing multiple open files
//

import SwiftUI

struct FileContentTabView: View {
    @ObservedObject var viewModel: FileBrowserStore
    @Binding var showTree: Bool
    var showTopDivider: Bool = true
    @State var isHoveringToggle = false
    @State var isHoveringPrev = false
    @State var isHoveringNext = false

    var body: some View {
        VStack(spacing: 0) {
            tabBar

            Divider()

            if viewModel.openFiles.isEmpty {
                emptyState
            } else {
                contentStack
            }
        }
    }

    private var effectiveSelectedFileId: UUID? {
        viewModel.selectedFileId ?? viewModel.openFiles.last?.id
    }

    private var selectedFile: OpenFileInfo? {
        guard let effectiveSelectedFileId else { return nil }
        return viewModel.openFiles.first(where: { $0.id == effectiveSelectedFileId })
    }

    private var contentStack: some View {
        Group {
            if let file = selectedFile {
                FileContentView(
                    file: file,
                    repoPath: viewModel.currentPath,
                    editorRuntime: viewModel.editorRuntime(for: file),
                    onContentChange: { newContent in
                        viewModel.updateFileContent(id: file.id, content: newContent)
                    },
                    onSave: {
                        try? viewModel.saveFile(id: file.id)
                    },
                    onRevert: {
                        Task {
                            await viewModel.openFile(path: file.path)
                        }
                    }
                )
                .id(file.id)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("No files open")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Text("Select a file from the tree to open")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FileTab: View {
    let file: OpenFileInfo
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        TabContainer(isSelected: isSelected, onSelect: onSelect) {
            TabLabel(
                title: file.name,
                isSelected: isSelected,
                onClose: onClose
            ) {
                FileIconView(path: file.path, size: 12)
            } trailing: {
                Circle()
                    .fill(file.hasUnsavedChanges ? Color.white : Color.clear)
                    .frame(width: 6, height: 6)
            }
        }
    }
}
