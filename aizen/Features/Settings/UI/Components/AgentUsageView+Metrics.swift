import ACP
import Foundation
import SwiftUI

extension AgentUsageDetailContent {
    var totalCostString: String {
        guard let month = report.periods.first(where: { $0.label.lowercased().contains("month") }) else {
            if let first = report.periods.first {
                return UsageFormatter.usdString(first.costUSD)
            }
            return "$0"
        }
        return UsageFormatter.usdString(month.costUSD)
    }

    var totalTokensString: String {
        guard let month = report.periods.first(where: { $0.label.lowercased().contains("month") }) else {
            if let first = report.periods.first {
                return UsageFormatter.tokenString(first.totalTokens)
            }
            return "0"
        }
        return UsageFormatter.tokenString(month.totalTokens)
    }

    var lastUsedText: String {
        guard let lastUsedAt = activityStats.lastUsedAt else { return "Never" }
        return RelativeDateFormatter.shared.string(from: lastUsedAt)
    }

    var tokenPeriodsList: some View {
        let totals = report.periods.map { Double($0.totalTokens ?? 0) }
        let maxTotal = max(totals.max() ?? 0, 1)

        return VStack(alignment: .leading, spacing: 10) {
            ForEach(report.periods, id: \.label) { period in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(period.label)
                            .font(.caption)
                        Spacer()
                        Text(UsageFormatter.usdString(period.costUSD))
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    UsageStackedBar(
                        input: Double(period.inputTokens ?? 0),
                        output: Double(period.outputTokens ?? 0),
                        total: maxTotal
                    )
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.accentColor.opacity(0.5))
                                .frame(width: 6, height: 6)
                            Text("In \(UsageFormatter.tokenString(period.inputTokens))")
                        }
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 6, height: 6)
                            Text("Out \(UsageFormatter.tokenString(period.outputTokens))")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
            }
        }
    }

    func quotaColor(_ percent: Double?) -> Color {
        guard let p = percent else { return .secondary }
        if p >= 90 { return .red }
        if p >= 70 { return .orange }
        return .green
    }

    func hasAccountDetails(_ user: UsageUserIdentity) -> Bool {
        user.email != nil || user.organization != nil || user.plan != nil
    }
}
