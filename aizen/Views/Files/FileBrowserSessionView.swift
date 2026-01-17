//
//  FileBrowserSessionView.swift
//  aizen
//
//  Main file browser with tree and content viewer
//

import SwiftUI
import CoreData

struct FileBrowserSessionView: View {
    @StateObject private var viewModel: FileBrowserViewModel
    @Binding private var fileToOpenFromSearch: String?
    let showPathHeader: Bool
    @AppStorage("fileBrowserShowTree") private var showTree = true

    init(
        worktree: Worktree,
        context: NSManagedObjectContext,
        fileToOpenFromSearch: Binding<String?>,
        showPathHeader: Bool = true
    ) {
        _viewModel = StateObject(wrappedValue: FileBrowserViewModel(worktree: worktree, context: context))
        _fileToOpenFromSearch = fileToOpenFromSearch
        self.showPathHeader = showPathHeader
    }

    var body: some View {
        Group {
            if showTree {
                HSplitView {
                    // Left: File tree (30%)
                    VStack(spacing: 0) {
                        if showPathHeader {
                            treeHeader
                        }

                        // Tree view
                        ScrollView {
                            FileTreeView(
                                currentPath: viewModel.currentPath,
                                expandedPaths: $viewModel.expandedPaths,
                                listDirectory: viewModel.listDirectory,
                                onOpenFile: { path in
                                    Task { @MainActor in
                                        await viewModel.openFile(path: path)
                                    }
                                },
                                viewModel: viewModel
                            )
                            .padding(.vertical, 4)
                        }
                    }
                    .frame(minWidth: 150, idealWidth: 250, maxWidth: 400)

                    // Right: File content viewer (70%)
                    FileContentTabView(
                        viewModel: viewModel,
                        showTree: $showTree,
                        showTopDivider: showPathHeader
                    )
                        .frame(minWidth: 300)
                }
            } else {
                FileContentTabView(
                    viewModel: viewModel,
                    showTree: $showTree,
                    showTopDivider: showPathHeader
                )
                    .frame(minWidth: 300)
            }
        }
        .onAppear {
            openPendingFileIfNeeded()
        }
        .onChange(of: fileToOpenFromSearch) { _ in
            openPendingFileIfNeeded()
        }
    }

    private var treeHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Text(viewModel.currentPath)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .textSelection(.enabled)

            CopyButton(text: viewModel.currentPath, iconSize: 9)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    private func openPendingFileIfNeeded() {
        guard let path = fileToOpenFromSearch else { return }

        Task { @MainActor in
            await viewModel.openFile(path: path)
            fileToOpenFromSearch = nil
        }
    }
}
