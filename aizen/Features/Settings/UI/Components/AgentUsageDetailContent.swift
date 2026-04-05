import SwiftUI

struct AgentUsageDetailContent: View {
    let report: AgentUsageReport
    let refreshState: UsageRefreshState
    let activityStats: AgentUsageStats
    let onRefresh: () -> Void
    let showActivity: Bool

    let gridSpacing: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: gridSpacing) {
            if let reason = report.unavailableReason {
                Text(reason)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
            }

            heroSection
            accountAndActivitySection
            usageAndQuotaSection
            footerSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
