import Foundation

extension AgentUsageMetricsStore {
    nonisolated static func buildReport(agentId: String) async -> AgentUsageReport {
        let provider = UsageProvider.fromAgentId(agentId)
        let now = Date()

        switch provider {
        case .codex:
            var report = AgentUsageReport()
            report.periods = tokenCostSummaries(provider: .codex, now: now)
            report.notes.append("Token and cost estimates are based on local logs.")

            let snapshot = await CodexUsageFetcher.fetch()
            report.quota = snapshot.quotaWindows
            if let credits = snapshot.creditsRemaining {
                report.quota.append(
                    UsageQuotaWindow(
                        title: "Credits",
                        remainingAmount: credits,
                        unit: "USD"
                    )
                )
            }
            report.user = snapshot.user
            report.errors.append(contentsOf: snapshot.errors)
            report.updatedAt = now
            if !hasAnyUsageData(report) {
                report.unavailableReason = "No usage data available yet."
            }
            return report

        case .claude:
            var report = AgentUsageReport()
            report.periods = tokenCostSummaries(provider: .claude, now: now)
            report.notes.append("Token and cost estimates are based on local logs.")

            let snapshot = await ClaudeUsageFetcher.fetch()
            report.quota = snapshot.quotaWindows
            report.user = snapshot.user
            report.errors.append(contentsOf: snapshot.errors)
            report.notes.append(contentsOf: snapshot.notes)

            report.updatedAt = now
            if !hasAnyUsageData(report) {
                report.unavailableReason = "No usage data available yet."
            }
            return report

        case .gemini:
            var report = AgentUsageReport()
            let snapshot = await GeminiUsageFetcher.fetch()
            report.quota = snapshot.quotaWindows
            report.user = snapshot.user
            report.errors.append(contentsOf: snapshot.errors)
            report.notes.append(contentsOf: snapshot.notes)
            report.notes.append("Token and cost totals are not available for Gemini yet.")
            report.updatedAt = now
            if !hasAnyUsageData(report) {
                report.unavailableReason = "No usage data available yet."
            }
            return report

        default:
            var report = AgentUsageReport.unavailable("Usage details aren't available for this agent yet.")
            report.updatedAt = now
            return report
        }
    }

    nonisolated static func tokenCostSummaries(provider: UsageProvider, now: Date) -> [UsagePeriodSummary] {
        let cal = Calendar.current
        let since = cal.date(byAdding: .day, value: -29, to: now) ?? now
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        let daily = CostUsageScanner.loadDailyReport(provider: provider, since: since, until: now, now: now)
        let monthDaily = CostUsageScanner.loadDailyReport(provider: provider, since: monthStart, until: now, now: now)
        return UsageTokenCostCalculator.periodSummaries(from: daily, monthReport: monthDaily, now: now)
    }

    nonisolated static func hasAnyUsageData(_ report: AgentUsageReport) -> Bool {
        let hasPeriods = report.periods.contains { period in
            period.inputTokens != nil || period.outputTokens != nil || period.totalTokens != nil || period.costUSD != nil
        }
        return hasPeriods || !report.quota.isEmpty || report.user != nil
    }
}
