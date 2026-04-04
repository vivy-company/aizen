import SwiftUI

struct AgentUsageSummaryView: View {
    let report: AgentUsageReport
    let refreshState: UsageRefreshState
    let onRefresh: () -> Void
    let onOpenDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Usage summary")
                    .font(.headline)
                Spacer()
                refreshButton
            }

            if report.periods.isEmpty {
                Text("No usage data yet.")
                    .foregroundStyle(.secondary)
            } else {
                periodSummaryGrid(periods: report.periods)
            }

            if let quota = report.quota.first {
                UsageProgressRow(
                    title: "Subscription",
                    subtitle: quota.resetDescription,
                    value: quota.usedPercent
                )
            }

            if let user = report.user, hasAccountDetails(user) {
                Text(user.email ?? user.organization ?? "Signed in")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let reason = report.unavailableReason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("View details") {
                    onOpenDetails()
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
