import ACP
import Foundation
import SwiftUI

extension AgentUsageSummaryView {
    @ViewBuilder
    var refreshButton: some View {
        switch refreshState {
        case .loading:
            ProgressView()
                .controlSize(.small)
        default:
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh usage")
        }
    }

    func periodSummaryGrid(periods: [UsagePeriodSummary]) -> some View {
        let totals = periods.map { Double($0.totalTokens ?? 0) }
        let maxTotal = max(totals.max() ?? 0, 1)

        return VStack(alignment: .leading, spacing: 10) {
            ForEach(periods, id: \.label) { period in
                let total = Double(period.totalTokens ?? 0)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(period.label)
                        Spacer()
                        Text(UsageFormatter.usdString(period.costUSD))
                            .foregroundStyle(.secondary)
                    }
                    UsageProgressBar(value: total, maxValue: maxTotal)
                    Text("Total tokens \(UsageFormatter.tokenString(period.totalTokens))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    func hasAccountDetails(_ user: UsageUserIdentity) -> Bool {
        user.email != nil || user.organization != nil || user.plan != nil
    }
}
