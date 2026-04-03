//
//  PullRequestRowView.swift
//  aizen
//
//  Row rendering for pull request list items.
//

import SwiftUI

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
