//
//  FileTabView.swift
//  aizen
//
//  File browser tab for worktree
//

import SwiftUI
import CoreData

struct FileTabView: View {
    let worktree: Worktree
    @Binding var fileToOpenFromSearch: String?
    var showPathHeader: Bool = true
    let store: FileBrowserStore?
    @Environment(\.managedObjectContext) private var viewContext

    init(
        worktree: Worktree,
        fileToOpenFromSearch: Binding<String?>,
        showPathHeader: Bool = true,
        store: FileBrowserStore? = nil
    ) {
        self.worktree = worktree
        self._fileToOpenFromSearch = fileToOpenFromSearch
        self.showPathHeader = showPathHeader
        self.store = store
    }

    var body: some View {
        if worktree.path != nil {
            if let store {
                FileBrowserSessionView(
                    viewModel: store,
                    fileToOpenFromSearch: $fileToOpenFromSearch,
                    showPathHeader: showPathHeader
                )
                .id(ObjectIdentifier(store))
            } else {
                FileBrowserSessionView(
                    worktree: worktree,
                    context: viewContext,
                    fileToOpenFromSearch: $fileToOpenFromSearch,
                    showPathHeader: showPathHeader
                )
                .id(worktree.objectID)
            }
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
