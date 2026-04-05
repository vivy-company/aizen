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
