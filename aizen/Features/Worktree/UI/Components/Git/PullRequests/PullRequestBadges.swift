//
//  PullRequestBadges.swift
//  aizen
//
//  Badge views for pull request list metadata.
//

import SwiftUI

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
