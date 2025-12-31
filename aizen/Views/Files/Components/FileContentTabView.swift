//
//  FileContentTabView.swift
//  aizen
//
//  Tab view for managing multiple open files
//

import SwiftUI

struct FileContentTabView: View {
    @ObservedObject var viewModel: FileBrowserViewModel

    private func selectPreviousTab() {
        guard let currentId = viewModel.selectedFileId,
              let currentIndex = viewModel.openFiles.firstIndex(where: { $0.id == currentId }),
              currentIndex > 0 else { return }
        viewModel.selectedFileId = viewModel.openFiles[currentIndex - 1].id
    }

    private func selectNextTab() {
        guard let currentId = viewModel.selectedFileId,
              let currentIndex = viewModel.openFiles.firstIndex(where: { $0.id == currentId }),
              currentIndex < viewModel.openFiles.count - 1 else { return }
        viewModel.selectedFileId = viewModel.openFiles[currentIndex + 1].id
    }

    private func canCloseToLeft(of fileId: UUID) -> Bool {
        guard let index = viewModel.openFiles.firstIndex(where: { $0.id == fileId }) else { return false }
        return index > 0
    }

    private func canCloseToRight(of fileId: UUID) -> Bool {
        guard let index = viewModel.openFiles.firstIndex(where: { $0.id == fileId }) else { return false }
        return index < viewModel.openFiles.count - 1
    }

    private func closeAllToLeft(of fileId: UUID) {
        guard let index = viewModel.openFiles.firstIndex(where: { $0.id == fileId }) else { return }

        for i in (0..<index).reversed() {
            viewModel.closeFile(id: viewModel.openFiles[i].id)
        }
    }

    private func closeAllToRight(of fileId: UUID) {
        guard let index = viewModel.openFiles.firstIndex(where: { $0.id == fileId }) else { return }

        for i in ((index + 1)..<viewModel.openFiles.count).reversed() {
            viewModel.closeFile(id: viewModel.openFiles[i].id)
        }
    }

    private func closeOtherTabs(except fileId: UUID) {
        for file in viewModel.openFiles where file.id != fileId {
            viewModel.closeFile(id: file.id)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.openFiles.isEmpty {
                emptyState
            } else {
                // Tab bar
                HStack(spacing: 0) {
                    // Navigation arrows
                    Button(action: selectPreviousTab) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                    .frame(width: 24, height: 36)
                    .disabled(viewModel.openFiles.count <= 1)

                    Button(action: selectNextTab) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                    .frame(width: 24, height: 36)
                    .disabled(viewModel.openFiles.count <= 1)

                    Divider()

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            ForEach(viewModel.openFiles) { file in
                                FileTab(
                                    file: file,
                                    isSelected: viewModel.selectedFileId == file.id,
                                    onSelect: {
                                        viewModel.selectedFileId = file.id
                                    },
                                    onClose: {
                                        viewModel.closeFile(id: file.id)
                                    }
                                )
                                .contextMenu {
                                    Button("Close") {
                                        viewModel.closeFile(id: file.id)
                                    }

                                    Divider()

                                    Button("Close All to the Left") {
                                        closeAllToLeft(of: file.id)
                                    }
                                    .disabled(!canCloseToLeft(of: file.id))

                                    Button("Close All to the Right") {
                                        closeAllToRight(of: file.id)
                                    }
                                    .disabled(!canCloseToRight(of: file.id))

                                    Divider()

                                    Button("Close Other Tabs") {
                                        closeOtherTabs(except: file.id)
                                    }
                                    .disabled(viewModel.openFiles.count <= 1)
                                }
                            }
                        }
                    }
                }
                .frame(height: 36)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .overlay(
                    Rectangle()
                        .fill(Color(NSColor.separatorColor))
                        .frame(height: 1),
                    alignment: .top
                )

                Divider()

                // Content
                if let selectedFile = viewModel.openFiles.first(where: { $0.id == viewModel.selectedFileId }) {
                    FileContentView(
                        file: selectedFile,
                        repoPath: viewModel.currentPath,
                        onContentChange: { newContent in
                            viewModel.updateFileContent(id: selectedFile.id, content: newContent)
                        },
                        onSave: {
                            try? viewModel.saveFile(id: selectedFile.id)
                        },
                        onRevert: {
                            Task {
                                await viewModel.openFile(path: selectedFile.path)
                            }
                        }
                    )
                }
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
