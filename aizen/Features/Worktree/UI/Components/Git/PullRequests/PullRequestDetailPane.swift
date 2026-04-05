//
//  PullRequestDetailPane.swift
//  aizen
//
//  Right pane showing PR details with tabs
//

import SwiftUI

struct PullRequestDetailPane: View {
    @ObservedObject var viewModel: PullRequestsViewModel
    let pr: PullRequest

    @State var selectedTab: DetailTab = .overview
    @State var commentText: String = ""
    @State var conversationAction: PullRequestsViewModel.ConversationAction = .comment
    @State var showRequestChangesSheet = false
    @State var requestChangesText: String = ""

    @AppStorage("editorFontFamily") var editorFontFamily: String = "Menlo"
    @AppStorage("diffFontSize") var diffFontSize: Double = 11.0

    enum DetailTab: String, CaseIterable {
        case overview = "Overview"
        case diff = "Diff"
        case comments = "Comments"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            GitWindowDivider()
            tabBar
            GitWindowDivider()
            tabContent
            GitWindowDivider()
            actionBar
        }
        .sheet(isPresented: $showRequestChangesSheet) {
            requestChangesSheet
        }
        .task(id: pr.id) {
            commentText = ""
            conversationAction = .comment
            showRequestChangesSheet = false
            requestChangesText = ""
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.actionError != nil },
            set: { _ in viewModel.actionError = nil }
        )) {
            Button("OK") { viewModel.actionError = nil }
        } message: {
            Text(viewModel.actionError ?? "")
        }
    }

    // MARK: - Action Bar

}
