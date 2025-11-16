//
//  FileTabView.swift
//  aizen
//
//  File browser tab for worktree
//

import SwiftUI

struct FileTabView: View {
    let worktree: Worktree

    var body: some View {
        if let path = worktree.path {
            FileBrowserSessionView(rootPath: path)
        } else {
            VStack {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundColor(.orange)
                Text("Worktree path not available")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
