import SwiftUI

struct AgentUsageSheet: View {
    let agentId: String
    let agentName: String

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var metricsStore = AgentUsageMetricsStore.shared
    @ObservedObject private var activityStore = AgentUsageStore.shared

    var body: some View {
        let report = metricsStore.report(for: agentId)
        let refreshState = metricsStore.refreshState(for: agentId)

        VStack(alignment: .leading, spacing: 16) {
            ZStack(alignment: .topTrailing) {
                HStack(spacing: 12) {
                    AgentIconView(agent: agentId, size: 28)
                        .padding(6)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(agentName)
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Usage details")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                DetailCloseButton { dismiss() }
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    AgentUsageDetailContent(
                        report: report,
                        refreshState: refreshState,
                        activityStats: activityStore.stats(for: agentId),
                        onRefresh: { metricsStore.refresh(agentId: agentId, force: true) },
                        showActivity: true
                    )
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .frame(minWidth: 680, maxWidth: .infinity, alignment: .leading)
        .settingsSheetChrome()
        .onAppear {
            metricsStore.refreshIfNeeded(agentId: agentId)
        }
    }
}
