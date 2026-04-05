//
//  WorktreeDetailsSheet.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI

struct WorktreeDetailsSheet: View {
    @ObservedObject var worktree: Worktree
    @ObservedObject var repositoryManager: WorkspaceRepositoryStore
    @Environment(\.dismiss) var dismiss

    @State var currentBranch = ""
    @State var ahead = 0
    @State var behind = 0
    @State var isLoading = false
    @State var errorMessage: String?
}
