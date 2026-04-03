import SwiftUI

extension PullRequestDetailPane {
    @ViewBuilder
    var header: some View {
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

    var mergeabilityBadge: some View {
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

    @ViewBuilder
    var tabBar: some View {
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

    func badgeCount(for tab: DetailTab) -> Int? {
        switch tab {
        case .overview: return nil
        case .diff: return pr.changedFiles > 0 ? pr.changedFiles : nil
        case .comments: return viewModel.comments.isEmpty ? nil : viewModel.comments.count
        }
    }
}
