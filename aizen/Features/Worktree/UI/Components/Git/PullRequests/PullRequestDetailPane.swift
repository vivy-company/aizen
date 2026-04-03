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

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("#\(pr.number)")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)

                Text(pr.title)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(2)

                Spacer()

                PRStateBadge(state: pr.state, isDraft: pr.isDraft)
            }

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text(pr.sourceBranch)
                        .font(.system(size: 12, design: .monospaced))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10))
                    Text(pr.targetBranch)
                        .font(.system(size: 12, design: .monospaced))
                }
                .foregroundStyle(.secondary)

                Text("•")
                    .foregroundStyle(.quaternary)

                HStack(spacing: 4) {
                    Text("+\(pr.additions)")
                        .foregroundStyle(.green)
                    Text("-\(pr.deletions)")
                        .foregroundStyle(.red)
                    if pr.changedFiles > 0 {
                        Text("\(pr.changedFiles) files")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 12, weight: .medium, design: .monospaced))

                Spacer()

                Label("@\(pr.author)", systemImage: "person")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Text("•")
                    .foregroundStyle(.quaternary)

                Text(pr.relativeCreatedAt)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }

            // Status row
            if pr.state == .open {
                HStack(spacing: 12) {
                    if let checks = pr.checksStatus {
                        PRChecksBadge(status: checks)
                    }

                    if let review = pr.reviewDecision {
                        PRReviewBadge(decision: review)
                    }

                    mergeabilityBadge

                    Spacer()
                }
            }
        }
        .padding(12)
    }

    private var mergeabilityBadge: some View {
        let isMergeable = pr.mergeable.isMergeable
        let color: Color = isMergeable ? .green : .red
        return TagBadge(
            text: isMergeable ? "Mergeable" : "Conflicts",
            color: color,
            cornerRadius: 0,
            font: .system(size: 10),
            horizontalPadding: 0,
            verticalPadding: 0,
            backgroundOpacity: 0,
            textColor: color,
            iconSystemName: isMergeable ? "checkmark.circle.fill" : "xmark.circle.fill",
            iconSize: 9,
            spacing: 3
        )
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(DetailTab.allCases, id: \.self) { tab in
                PRDetailTabButton(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    badge: badgeCount(for: tab),
                    action: { selectedTab = tab }
                )
            }
            Spacer()
        }
        .frame(height: 36)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    private func badgeCount(for tab: DetailTab) -> Int? {
        switch tab {
        case .overview: return nil
        case .diff: return pr.changedFiles > 0 ? pr.changedFiles : nil
        case .comments: return viewModel.comments.isEmpty ? nil : viewModel.comments.count
        }
    }

    // MARK: - Action Bar

}

// MARK: - Comment View

struct PRCommentView: View {
    let comment: PRComment

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            avatarView

            VStack(alignment: .leading, spacing: 6) {
                // Header
                HStack(spacing: 6) {
                    Text("@\(comment.author)")
                        .font(.system(size: 12, weight: .semibold))

                    if comment.isReview, let state = comment.reviewState {
                        reviewBadge(for: state)
                    }

                    Spacer()

                    Text(comment.relativeDate)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                // Message content with markdown
                MessageContentView(content: comment.body)

                // File reference if inline comment
                if let path = comment.path {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 10))
                        Text(path)
                        if let line = comment.line {
                            Text(":\(line)")
                        }
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(bubbleBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var bubbleBackground: some View {
        Color.clear
            .background(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(GitWindowDividerStyle.color(opacity: 0.3), lineWidth: 0.5)
            }
    }

    private var avatarView: some View {
        let size: CGFloat = 28
        return Group {
            if let avatarURL = comment.avatarURL, let url = URL(string: avatarURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        initialsAvatar
                    }
                }
            } else {
                initialsAvatar
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .strokeBorder(GitWindowDividerStyle.color(opacity: 0.3), lineWidth: 0.5)
        )
    }

    private var initialsAvatar: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.2))
            Text(initials)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }

    private var initials: String {
        let trimmed = comment.author.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "?" }

        let parts = trimmed
            .replacingOccurrences(of: "@", with: "")
            .split(whereSeparator: { $0 == " " || $0 == "." || $0 == "-" || $0 == "_" })

        if let first = parts.first?.first, let second = parts.dropFirst().first?.first {
            return String([first, second]).uppercased()
        }

        if let first = parts.first?.first {
            return String(first).uppercased()
        }

        return "?"
    }

    @ViewBuilder
    private func reviewBadge(for state: PRComment.ReviewState) -> some View {
        let color = foregroundColor(for: state)
        TagBadge(
            text: state.displayName,
            color: color,
            cornerRadius: 4,
            font: .system(size: 10, weight: .medium),
            horizontalPadding: 6,
            verticalPadding: 2,
            backgroundOpacity: 0.2,
            textColor: color,
            iconSystemName: iconName(for: state),
            iconSize: 9,
            spacing: 3
        )
    }

    private func iconName(for state: PRComment.ReviewState) -> String {
        switch state {
        case .approved: return "checkmark.circle.fill"
        case .changesRequested: return "xmark.circle.fill"
        case .commented: return "bubble.left.fill"
        case .pending: return "clock.fill"
        }
    }

    private func foregroundColor(for state: PRComment.ReviewState) -> Color {
        switch state {
        case .approved: return .green
        case .changesRequested: return .red
        case .commented: return .blue
        case .pending: return .orange
        }
    }
}

// MARK: - Tab Button

struct PRDetailTabButton: View {
    let tab: PullRequestDetailPane.DetailTab
    let isSelected: Bool
    let badge: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(tab.rawValue)
                    .foregroundStyle(isSelected ? .primary : .secondary)

                if let count = badge {
                    Text("(\(count))")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 11, weight: isSelected ? .medium : .regular))
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(isSelected ? Color(NSColor.textBackgroundColor) : Color.clear)
            .overlay(
                Rectangle()
                    .fill(isSelected ? Color.accentColor : Color.clear)
                    .frame(height: 2),
                alignment: .top
            )
            .overlay(
                Rectangle()
                    .fill(GitWindowDividerStyle.color(opacity: 1))
                    .frame(width: 1),
                alignment: .trailing
            )
        }
        .buttonStyle(.plain)
    }
}
