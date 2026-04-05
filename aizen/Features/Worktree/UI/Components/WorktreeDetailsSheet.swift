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

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    branchStatus
                    informationSection
                    errorSection
                }
                .padding()
            }
        }
        .frame(width: 500, height: 400)
        .settingsSheetChrome()
        .onAppear {
            refreshStatus()
        }
    }
}
