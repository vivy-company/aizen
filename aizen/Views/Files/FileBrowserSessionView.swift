//
//  FileBrowserSessionView.swift
//  aizen
//
//  Main file browser with tree and content viewer
//

import SwiftUI

struct FileBrowserSessionView: View {
    @StateObject private var viewModel: FileBrowserViewModel

    init(rootPath: String) {
        _viewModel = StateObject(wrappedValue: FileBrowserViewModel(rootPath: rootPath))
    }

    var body: some View {
        HSplitView {
            // Left: File tree (30%)
            VStack(spacing: 0) {
                // Tree header
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
                        }
                    )
                    .padding(.vertical, 4)
                }
            }
            .frame(minWidth: 150, idealWidth: 250, maxWidth: 400)

            // Right: File content viewer (70%)
            FileContentTabView(viewModel: viewModel)
                .frame(minWidth: 300)
        }
    }
}
