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
    let viewModel: FileBrowserStore

    init(
        currentPath: String,
        path: String? = nil,
        level: Int = 0,
        expandedPaths: Binding<Set<String>>,
        listDirectory: @escaping (String) throws -> [FileItem],
        onOpenFile: @escaping (String) -> Void,
        viewModel: FileBrowserStore
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
    let viewModel: FileBrowserStore

    @Environment(\.colorScheme) var colorScheme
    @State var isHovering = false
    @State var showingDialog: FileInputDialogType?
    @State var showingDeleteAlert = false

    var isExpanded: Bool {
        expandedPaths.contains(item.path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            itemRow

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
