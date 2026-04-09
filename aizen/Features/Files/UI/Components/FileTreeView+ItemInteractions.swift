//
//  FileTreeView+ItemInteractions.swift
//  aizen
//
//  File tree item presentation and interactions.
//

import SwiftUI

extension FileTreeItem {
    var gitColors: GitStatusColors {
        GhosttyThemeParser.loadGitStatusColors(named: AppearanceSettings.effectiveThemeName(colorScheme: colorScheme))
    }

    func textColor(for item: FileItem) -> Color {
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

    func toggleExpanded() {
        if isExpanded {
            expandedPaths.remove(item.path)
        } else {
            expandedPaths.insert(item.path)
        }
    }

    func handleTap() {
        if item.isDirectory {
            toggleExpanded()
        } else {
            onOpenFile(item.path)
        }
    }

    func presentDialog(for dialogType: FileInputDialogType) -> some View {
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

    @ViewBuilder
    var itemContextMenu: some View {
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

    var itemRow: some View {
        HStack(spacing: 4) {
            if level > 0 {
                Color.clear
                    .frame(width: CGFloat(level * 16))
            }

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

            FileIconView(path: item.path, size: 12)
                .opacity(item.isGitIgnored ? 0.5 : 1.0)

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
        .onTapGesture(perform: handleTap)
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            itemContextMenu
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
            presentDialog(for: dialogType)
        }
    }
}
