//
//  PullRequestListPane.swift
//  aizen
//
//  Left pane showing list of PRs with filter and pagination
//

import SwiftUI

struct PullRequestListPane: View {
    enum Layout {
        static let headerHorizontalPadding: CGFloat = 12
        static let headerVerticalPadding: CGFloat = 8
        static let chipCornerRadius: CGFloat = 9
        static let listBottomPadding: CGFloat = 8
    }

    @Environment(\.controlActiveState) private var controlActiveState
    @ObservedObject var viewModel: PullRequestsViewModel
    @State var hoveredPullRequestID: Int?

    var selectedForegroundColor: Color {
        controlActiveState == .key ? .accentColor : .accentColor.opacity(0.78)
    }

    var selectionFillColor: Color {
        let base = NSColor.unemphasizedSelectedContentBackgroundColor
        let alpha: Double = controlActiveState == .key ? 0.26 : 0.18
        return Color(nsColor: base).opacity(alpha)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            GitWindowDivider()
            listContent
        }
    }

}

// MARK: - PR Row View

struct PRRowView: View {
    let pr: PullRequest
    let isSelected: Bool
    let isHovered: Bool
    let selectedForegroundColor: Color
    let selectionFillColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? selectedForegroundColor : .secondary)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("#\(pr.number)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(isSelected ? selectedForegroundColor : .secondary)

                    Text(pr.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? selectedForegroundColor : .primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer()

                    if showsStateBadge {
                        PRStateBadge(
                            state: pr.state,
                            isDraft: pr.isDraft
                        )
                    }

                    Text(pr.relativeCreatedAt)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary.opacity(0.75))
                }

                HStack(spacing: 8) {
                    Label(pr.author, systemImage: "person")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Text("•")
                        .foregroundStyle(Color.secondary.opacity(0.45))

                    HStack(spacing: 2) {
                        Text(pr.sourceBranch)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 8))
                        Text(pr.targetBranch)
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                    Spacer()
                }

                if hasStatusDetails {
                    HStack(spacing: 8) {
                        if let checks = pr.checksStatus {
                            PRChecksBadge(status: checks)
                        }

                        if let review = pr.reviewDecision {
                            PRReviewBadge(decision: review)
                        }

                        if pr.changedFiles > 0 {
                            HStack(spacing: 4) {
                                Text("\(pr.changedFiles)f")
                                    .foregroundStyle(Color.secondary.opacity(0.75))
                                Text("+\(pr.additions)")
                                    .foregroundStyle(.green)
                                Text("-\(pr.deletions)")
                                    .foregroundStyle(.red)
                            }
                            .font(.system(size: 11, design: .monospaced))
                        }

                        Spacer()
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            Group {
                if isSelected {
                    Rectangle().fill(selectionFillColor)
                } else if isHovered {
                    Rectangle().fill(Color.white.opacity(0.06))
                } else {
                    Color.clear
                }
            }
        )
        .contentShape(Rectangle())
    }

    private var showsStateBadge: Bool {
        pr.isDraft || pr.state != .open
    }

    private var hasStatusDetails: Bool {
        pr.state == .open && (pr.checksStatus != nil || pr.reviewDecision != nil || pr.changedFiles > 0)
    }
}

// MARK: - Badge Views

struct PRStateBadge: View {
    let state: PullRequest.State
    let isDraft: Bool
    let colorOverride: Color?

    init(state: PullRequest.State, isDraft: Bool, colorOverride: Color? = nil) {
        self.state = state
        self.isDraft = isDraft
        self.colorOverride = colorOverride
    }

    var body: some View {
        let color = colorOverride ?? foregroundColor
        return TagBadge(
            text: isDraft ? "Draft" : state.displayName,
            color: color,
            cornerRadius: 4,
            font: .system(size: 10, weight: .medium),
            horizontalPadding: 6,
            verticalPadding: 2,
            backgroundOpacity: 0.2,
            textColor: color
        )
    }

    private var foregroundColor: Color {
        if isDraft {
            return .gray
        }
        switch state {
        case .open: return .green
        case .merged: return .purple
        case .closed: return .red
        }
    }
}

struct PRChecksBadge: View {
    let status: PullRequest.ChecksStatus
    let colorOverride: Color?

    init(status: PullRequest.ChecksStatus, colorOverride: Color? = nil) {
        self.status = status
        self.colorOverride = colorOverride
    }

    var body: some View {
        PRStatusBadge(
            text: status.displayName,
            color: colorOverride ?? color,
            iconSystemName: status.iconName
        )
    }

    private var color: Color {
        switch status {
        case .passing: return .green
        case .failing: return .red
        case .pending: return .orange
        }
    }
}

struct PRReviewBadge: View {
    let decision: PullRequest.ReviewDecision
    let colorOverride: Color?

    init(decision: PullRequest.ReviewDecision, colorOverride: Color? = nil) {
        self.decision = decision
        self.colorOverride = colorOverride
    }

    var body: some View {
        PRStatusBadge(
            text: decision.displayName,
            color: colorOverride ?? color,
            iconSystemName: decision.iconName
        )
    }

    private var color: Color {
        switch decision {
        case .approved: return .green
        case .changesRequested: return .red
        case .reviewRequired: return .orange
        }
    }
}

private struct PRStatusBadge: View {
    let text: String
    let color: Color
    let iconSystemName: String

    var body: some View {
        TagBadge(
            text: text,
            color: color,
            cornerRadius: 0,
            font: .system(size: 10),
            horizontalPadding: 0,
            verticalPadding: 0,
            backgroundOpacity: 0,
            textColor: color,
            iconSystemName: iconSystemName,
            iconSize: 9,
            spacing: 3
        )
    }
}
