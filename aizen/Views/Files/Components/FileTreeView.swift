//
//  FileTreeView.swift
//  aizen
//
//  Recursive file tree navigator with Catppuccin icons
//

import SwiftUI

struct FileTreeView: View {
    let currentPath: String
    let path: String
    let level: Int
    @Binding var expandedPaths: Set<String>
    let listDirectory: (String) throws -> [FileItem]
    let onOpenFile: (String) -> Void
    let viewModel: FileBrowserViewModel

    init(
        currentPath: String,
        path: String? = nil,
        level: Int = 0,
        expandedPaths: Binding<Set<String>>,
        listDirectory: @escaping (String) throws -> [FileItem],
        onOpenFile: @escaping (String) -> Void,
        viewModel: FileBrowserViewModel
    ) {
        self.currentPath = currentPath
        self.path = path ?? currentPath
        self.level = level
        self._expandedPaths = expandedPaths
        self.listDirectory = listDirectory
        self.onOpenFile = onOpenFile
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let items = try? listDirectory(path) {
                ForEach(items) { item in
                    FileTreeItem(
                        item: item,
                        level: level,
                        expandedPaths: $expandedPaths,
                        listDirectory: listDirectory,
                        onOpenFile: onOpenFile,
                        viewModel: viewModel
                    )
                }
            }
        }
        .id(viewModel.treeRefreshTrigger)
    }
}

struct FileTreeItem: View {
    let item: FileItem
    let level: Int
    @Binding var expandedPaths: Set<String>
    let listDirectory: (String) throws -> [FileItem]
    let onOpenFile: (String) -> Void
    let viewModel: FileBrowserViewModel

    @AppStorage("editorTheme") private var editorTheme: String = "Aizen Dark"
    @State private var isHovering = false
    @State private var showingDialog: FileInputDialogType?
    @State private var showingDeleteAlert = false

    private var isExpanded: Bool {
        expandedPaths.contains(item.path)
    }

    private var gitColors: GitStatusColors {
        GhosttyThemeParser.loadGitStatusColors(named: editorTheme)
    }

    private func textColor(for item: FileItem) -> Color {
        guard let status = item.gitStatus else { return .primary }
        switch status {
        case .modified, .mixed:
            return Color(nsColor: gitColors.modified)
        case .staged, .added:
            return Color(nsColor: gitColors.added)
        case .untracked:
            return Color(nsColor: gitColors.untracked)
        case .deleted, .conflicted:
            return Color(nsColor: gitColors.deleted)
        case .renamed:
            return Color(nsColor: gitColors.renamed)
        }
    }

    private func toggleExpanded() {
        if isExpanded {
            expandedPaths.remove(item.path)
        } else {
            expandedPaths.insert(item.path)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Item row
            HStack(spacing: 4) {
                // Indentation
                if level > 0 {
                    Color.clear
                        .frame(width: CGFloat(level * 16))
                }

                // Expand/collapse arrow for directories
                if item.isDirectory {
                    Button(action: toggleExpanded) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .frame(width: 12, height: 12)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear
                        .frame(width: 12, height: 12)
                }

                // Icon
                FileIconView(path: item.path, size: 12)
                    .opacity(item.isGitIgnored ? 0.5 : 1.0)

                // Name
                Text(item.name)
                    .font(.system(size: 12))
                    .foregroundColor(textColor(for: item))
                    .opacity(item.isGitIgnored ? 0.5 : 1.0)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(isHovering ? Color.secondary.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture {
                if item.isDirectory {
                    toggleExpanded()
                } else {
                    onOpenFile(item.path)
                }
            }
            .onHover { hovering in
                isHovering = hovering
            }
            .contextMenu {
                if item.isDirectory {
                    Button("New File...") {
                        showingDialog = .newFile
                    }

                    Button("New Folder...") {
                        showingDialog = .newFolder
                    }

                    Divider()
                }

                Button("Rename...") {
                    showingDialog = .rename
                }

                Button("Delete") {
                    showingDeleteAlert = true
                }

                Divider()

                Button("Copy Path") {
                    viewModel.copyPathToClipboard(path: item.path)
                }

                Button("Reveal in Finder") {
                    viewModel.revealInFinder(path: item.path)
                }
            }
            .alert("Delete \(item.name)?", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task {
                        await viewModel.deleteItem(path: item.path)
                    }
                }
            } message: {
                Text("This action cannot be undone.")
            }
            .sheet(item: $showingDialog) { dialogType in
                FileInputDialog(
                    type: dialogType,
                    initialValue: dialogType == .rename ? item.name : "",
                    onSubmit: { name in
                        Task {
                            switch dialogType {
                            case .newFile:
                                await viewModel.createNewFile(parentPath: item.path, name: name)
                            case .newFolder:
                                await viewModel.createNewFolder(parentPath: item.path, name: name)
                            case .rename:
                                await viewModel.renameItem(oldPath: item.path, newName: name)
                            }
                        }
                        showingDialog = nil
                    },
                    onCancel: {
                        showingDialog = nil
                    }
                )
            }

            // Recursive children for expanded directories
            if item.isDirectory && isExpanded {
                FileTreeView(
                    currentPath: item.path,
                    path: item.path,
                    level: level + 1,
                    expandedPaths: $expandedPaths,
                    listDirectory: listDirectory,
                    onOpenFile: onOpenFile,
                    viewModel: viewModel
                )
            }
        }
    }
}

extension FileInputDialogType: Identifiable {
    var id: String {
        switch self {
        case .newFile: return "newFile"
        case .newFolder: return "newFolder"
        case .rename: return "rename"
        }
    }
}
