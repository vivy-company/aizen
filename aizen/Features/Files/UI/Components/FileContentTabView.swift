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

    /// Keep one persistent editor view per open tab so VVCode buffers/highlighting
    /// are retained when switching tabs (prevents flicker on tab changes).
    private var contentStack: some View {
        ZStack {
            ForEach(viewModel.openFiles) { file in
                let isSelected = effectiveSelectedFileId == file.id
                FileContentView(
                    file: file,
                    repoPath: viewModel.currentPath,
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
                .opacity(isSelected ? 1 : 0)
                .allowsHitTesting(isSelected)
                .accessibilityHidden(!isSelected)
                .zIndex(isSelected ? 1 : 0)
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
