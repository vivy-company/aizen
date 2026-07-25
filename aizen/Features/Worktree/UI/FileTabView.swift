//
//  FileTabView.swift
//  aizen
//
//  File browser tab for worktree
//

import SwiftUI

struct FileTabView: View {
    let worktree: Worktree
    @Binding var searchOpenRequest: SearchOpenRequest?
    var showPathHeader: Bool = true
    let store: FileBrowserStore

    init(
        worktree: Worktree,
        searchOpenRequest: Binding<SearchOpenRequest?>,
        showPathHeader: Bool = true,
        store: FileBrowserStore
    ) {
        self.worktree = worktree
        self._searchOpenRequest = searchOpenRequest
        self.showPathHeader = showPathHeader
        self.store = store
    }

    var body: some View {
        if worktree.path != nil {
            FileBrowserSessionView(
                viewModel: store,
                searchOpenRequest: $searchOpenRequest,
                showPathHeader: showPathHeader
            )
            .id(ObjectIdentifier(store))
        } else {
            VStack {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundColor(.orange)
                Text("Environment path not available")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
