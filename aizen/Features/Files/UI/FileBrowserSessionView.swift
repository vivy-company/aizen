//
//  FileBrowserSessionView.swift
//  aizen
//
//  Main file browser with tree and content viewer
//

import SwiftUI

struct FileBrowserSessionView: View {
    @StateObject private var viewModel: FileBrowserStore
    @Binding private var searchOpenRequest: SearchOpenRequest?
    let showPathHeader: Bool
    @AppStorage("fileBrowserShowTree") private var showTree = true

    init(
        viewModel: FileBrowserStore,
        searchOpenRequest: Binding<SearchOpenRequest?>,
        showPathHeader: Bool = true
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _searchOpenRequest = searchOpenRequest
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
        .task(id: searchOpenRequest) {
            await openPendingFileIfNeeded()
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

    @MainActor
    private func openPendingFileIfNeeded() async {
        guard let searchOpenRequest else { return }
        await viewModel.openFile(request: searchOpenRequest)
        self.searchOpenRequest = nil
    }
}
