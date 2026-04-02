//
//  AgentUsageMetricsStore.swift
//  aizen
//
//  Aggregates token/cost usage and account quota info per agent
//

import Foundation
import Combine

@MainActor
final class AgentUsageMetricsStore: ObservableObject {
    static let shared = AgentUsageMetricsStore()

    @Published private(set) var reports: [String: AgentUsageReport] = [:]
    @Published private(set) var refreshStates: [String: UsageRefreshState] = [:]

    private var lastRefresh: [String: Date] = [:]
    private var refreshingAgents: Set<String> = []
    private let minRefreshInterval: TimeInterval = 60

    private init() {}

    func report(for agentId: String) -> AgentUsageReport {
        reports[agentId] ?? AgentUsageReport()
    }

    func refreshState(for agentId: String) -> UsageRefreshState {
        refreshStates[agentId] ?? .idle
    }

    func refreshIfNeeded(agentId: String) {
        refresh(agentId: agentId, force: false)
    }

    func refresh(agentId: String, force: Bool = false) {
        if refreshingAgents.contains(agentId) { return }
        let now = Date()
        if !force, let last = lastRefresh[agentId], now.timeIntervalSince(last) < minRefreshInterval {
            return
        }

        refreshingAgents.insert(agentId)
        refreshStates[agentId] = .loading

        Task.detached(priority: .utility) { [agentId] in
            let report = await Self.buildReport(agentId: agentId)
            await AgentUsageMetricsStore.shared.applyReport(report, agentId: agentId)
        }
    }

    nonisolated private static func buildReport(agentId: String) async -> AgentUsageReport {
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

    nonisolated private static func tokenCostSummaries(provider: UsageProvider, now: Date) -> [UsagePeriodSummary] {
        let cal = Calendar.current
        let since = cal.date(byAdding: .day, value: -29, to: now) ?? now
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        let daily = CostUsageScanner.loadDailyReport(provider: provider, since: since, until: now, now: now)
        let monthDaily = CostUsageScanner.loadDailyReport(provider: provider, since: monthStart, until: now, now: now)
        return UsageTokenCostCalculator.periodSummaries(from: daily, monthReport: monthDaily, now: now)
    }

    nonisolated private static func hasAnyUsageData(_ report: AgentUsageReport) -> Bool {
        let hasPeriods = report.periods.contains { period in
            period.inputTokens != nil || period.outputTokens != nil || period.totalTokens != nil || period.costUSD != nil
        }
        return hasPeriods || !report.quota.isEmpty || report.user != nil
    }

    @MainActor
    private func applyReport(_ report: AgentUsageReport, agentId: String) {
        reports[agentId] = report
        if let firstError = report.errors.first {
            refreshStates[agentId] = .failed(firstError)
        } else {
            refreshStates[agentId] = .idle
        }
        lastRefresh[agentId] = Date()
        refreshingAgents.remove(agentId)
    }
}
