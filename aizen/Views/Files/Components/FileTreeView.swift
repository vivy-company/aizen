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

    init(
        currentPath: String,
        path: String? = nil,
        level: Int = 0,
        expandedPaths: Binding<Set<String>>,
        listDirectory: @escaping (String) throws -> [FileItem],
        onOpenFile: @escaping (String) -> Void
    ) {
        self.currentPath = currentPath
        self.path = path ?? currentPath
        self.level = level
        self._expandedPaths = expandedPaths
        self.listDirectory = listDirectory
        self.onOpenFile = onOpenFile
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
                        onOpenFile: onOpenFile
                    )
                }
            }
        }
    }
}

struct FileTreeItem: View {
    let item: FileItem
    let level: Int
    @Binding var expandedPaths: Set<String>
    let listDirectory: (String) throws -> [FileItem]
    let onOpenFile: (String) -> Void

    @State private var isHovering = false

    private var isExpanded: Bool {
        expandedPaths.contains(item.path)
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
                    .id(item.path)

                // Name
                Text(item.name)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(isHovering ? Color.secondary.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture {
                print("DEBUG: Tapped item: \(item.name), isDirectory: \(item.isDirectory)")
                if item.isDirectory {
                    toggleExpanded()
                } else {
                    print("DEBUG: Opening file: \(item.path)")
                    onOpenFile(item.path)
                }
            }
            .onHover { hovering in
                isHovering = hovering
            }

            // Recursive children for expanded directories
            if item.isDirectory && isExpanded {
                FileTreeView(
                    currentPath: item.path,
                    path: item.path,
                    level: level + 1,
                    expandedPaths: $expandedPaths,
                    listDirectory: listDirectory,
                    onOpenFile: onOpenFile
                )
            }
        }
    }
}
