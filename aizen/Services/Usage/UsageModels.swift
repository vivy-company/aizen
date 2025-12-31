//
//  UsageModels.swift
//  aizen
//
//  Shared usage data models
//

import Foundation

nonisolated enum UsageProvider: String, Codable, CaseIterable, Sendable {
    case codex
    case claude
    case gemini
    case kimi
    case opencode
    case vibe
    case qwen
    case custom

    static func fromAgentId(_ agentId: String) -> UsageProvider {
        switch agentId.lowercased() {
        case "codex": return .codex
        case "claude": return .claude
        case "gemini": return .gemini
        case "kimi": return .kimi
        case "opencode": return .opencode
        case "vibe": return .vibe
        case "qwen": return .qwen
        default: return .custom
        }
    }
}

nonisolated struct UsagePeriodSummary: Codable, Equatable, Sendable {
    let label: String
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?
    let costUSD: Double?

    init(
        label: String,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        totalTokens: Int? = nil,
        costUSD: Double? = nil
    ) {
        self.label = label
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.costUSD = costUSD
    }
}

nonisolated struct UsageQuotaWindow: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let usedPercent: Double?
    let resetsAt: Date?
    let resetDescription: String?
    let usedAmount: Double?
    let remainingAmount: Double?
    let limitAmount: Double?
    let unit: String?

    init(
        id: String = UUID().uuidString,
        title: String,
        usedPercent: Double? = nil,
        resetsAt: Date? = nil,
        resetDescription: String? = nil,
        usedAmount: Double? = nil,
        remainingAmount: Double? = nil,
        limitAmount: Double? = nil,
        unit: String? = nil
    ) {
        self.id = id
        self.title = title
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.resetDescription = resetDescription
        self.usedAmount = usedAmount
        self.remainingAmount = remainingAmount
        self.limitAmount = limitAmount
        self.unit = unit
    }
}

nonisolated struct UsageUserIdentity: Codable, Equatable, Sendable {
    let email: String?
    let organization: String?
    let plan: String?

    init(email: String? = nil, organization: String? = nil, plan: String? = nil) {
        self.email = email
        self.organization = organization
        self.plan = plan
    }
}

nonisolated struct AgentUsageReport: Codable, Equatable, Sendable {
    var periods: [UsagePeriodSummary]
    var quota: [UsageQuotaWindow]
    var user: UsageUserIdentity?
    var updatedAt: Date?
    var notes: [String]
    var errors: [String]
    var unavailableReason: String?

    init(
        periods: [UsagePeriodSummary] = [],
        quota: [UsageQuotaWindow] = [],
        user: UsageUserIdentity? = nil,
        updatedAt: Date? = nil,
        notes: [String] = [],
        errors: [String] = [],
        unavailableReason: String? = nil
    ) {
        self.periods = periods
        self.quota = quota
        self.user = user
        self.updatedAt = updatedAt
        self.notes = notes
        self.errors = errors
        self.unavailableReason = unavailableReason
    }

    static func unavailable(_ reason: String) -> AgentUsageReport {
        AgentUsageReport(unavailableReason: reason)
    }
}

nonisolated enum UsageRefreshState: Equatable, Sendable {
    case idle
    case loading
    case failed(String)
}
