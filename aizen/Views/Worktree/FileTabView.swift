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
    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        if worktree.path != nil {
            FileBrowserSessionView(
                worktree: worktree,
                context: viewContext,
                fileToOpenFromSearch: $fileToOpenFromSearch,
                showPathHeader: showPathHeader
            )
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
