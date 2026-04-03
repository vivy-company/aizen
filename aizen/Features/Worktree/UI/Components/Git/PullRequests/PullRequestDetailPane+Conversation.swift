import SwiftUI

extension PullRequestDetailPane {
    @ViewBuilder
    var commentInput: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Picker("Action", selection: $conversationAction) {
                    ForEach(PullRequestsViewModel.ConversationAction.allCases, id: \.self) { action in
                        Text(conversationActionTitle(action)).tag(action)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(viewModel.isPerformingAction)

                Spacer()

                if viewModel.hostingInfo?.provider == .gitlab, conversationAction == .requestChanges {
                    Text("GitLab posts this as a comment.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $commentText)
                    .font(.system(size: 13))
                    .frame(minHeight: 72)
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
                    .disabled(viewModel.isPerformingAction)

                if commentText.isEmpty {
                    Text(conversationPlaceholder)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }

            HStack {
                Spacer()
                Button {
                    let body = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task {
                        await viewModel.submitConversationAction(conversationAction, body: body)
                        if viewModel.actionError == nil {
                            commentText = ""
                            conversationAction = .comment
                        }
                    }
                } label: {
                    Label(conversationActionButtonTitle, systemImage: conversationActionIcon(conversationAction))
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!canSubmitConversationAction)
            }
        }
        .padding(12)
    }

    var trimmedCommentText: String {
        commentText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSubmitConversationAction: Bool {
        if viewModel.isPerformingAction {
            return false
        }

        switch conversationAction {
        case .comment, .requestChanges:
            return !trimmedCommentText.isEmpty
        case .approve:
            return viewModel.canApprove
        }
    }

    var conversationPlaceholder: String {
        switch conversationAction {
        case .comment:
            return "Add a comment..."
        case .approve:
            return "Optional note for approval..."
        case .requestChanges:
            return "Describe the changes needed..."
        }
    }

    var conversationActionButtonTitle: String {
        switch conversationAction {
        case .comment:
            return "Comment"
        case .approve:
            return "Approve"
        case .requestChanges:
            return "Request Changes"
        }
    }

    func conversationActionTitle(_ action: PullRequestsViewModel.ConversationAction) -> String {
        switch action {
        case .comment:
            return "Comment"
        case .approve:
            return "Approve"
        case .requestChanges:
            return "Request Changes"
        }
    }

    func conversationActionIcon(_ action: PullRequestsViewModel.ConversationAction) -> String {
        switch action {
        case .comment:
            return "bubble.left"
        case .approve:
            return "checkmark"
        case .requestChanges:
            return "xmark"
        }
    }
}
