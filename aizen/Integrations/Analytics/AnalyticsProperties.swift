//
//  AnalyticsProperties.swift
//  aizen
//
//  Typed low-cardinality analytics property values.
//

import Foundation

nonisolated enum AnalyticsPropertyValue: Equatable, Sendable {
    case string(String)
    case integer(Int)
    case bool(Bool)
    case number(Double)
}

nonisolated enum AnalyticsCountBucket: String, Sendable {
    case one = "1"
    case twoToThree = "2_3"
    case fourToTen = "4_10"
    case elevenPlus = "11_plus"

    static func bucket(for count: Int) -> AnalyticsCountBucket {
        switch count {
        case ...1:
            return .one
        case 2...3:
            return .twoToThree
        case 4...10:
            return .fourToTen
        default:
            return .elevenPlus
        }
    }
}

nonisolated enum AnalyticsChannel: String, Sendable {
    case stable
    case nightly
    case debug
    case unknown
}

nonisolated enum AnalyticsLicenseTier: String, Sendable {
    case free
    case pro
    case lifetime
    case unknown
}

nonisolated enum AnalyticsRepositorySource: String, Sendable {
    case local
    case clone
    case unknown
}

nonisolated enum AnalyticsRepositoryProvider: String, Sendable {
    case github
    case gitlab
    case other
    case unknown

    static func provider(forCloneURL cloneURL: String) -> AnalyticsRepositoryProvider {
        let lowercased = cloneURL.lowercased()
        if lowercased.contains("github.com") {
            return .github
        }
        if lowercased.contains("gitlab.com") {
            return .gitlab
        }
        if lowercased.contains("://") || lowercased.contains("@") {
            return .other
        }
        return .unknown
    }
}

nonisolated enum AnalyticsWorktreeSource: String, Sendable {
    case newBranch = "new_branch"
    case existingBranch = "existing_branch"
    case unknown
}

nonisolated enum AnalyticsEntryPoint: String, Sendable {
    case worktree
    case chat
    case review
    case commandPalette = "command_palette"
    case settings
    case menu
    case unknown
}

nonisolated enum AnalyticsAgentProvider: String, Sendable {
    case codex
    case claude
    case gemini
    case custom
    case unknown

    static func provider(forAgentId agentId: String) -> AnalyticsAgentProvider {
        let lowercased = agentId.lowercased()
        if lowercased.hasPrefix("custom-") {
            return .custom
        }
        if lowercased.contains("codex") || lowercased.contains("openai") {
            return .codex
        }
        if lowercased.contains("claude") {
            return .claude
        }
        if lowercased.contains("gemini") {
            return .gemini
        }
        return .unknown
    }
}

nonisolated enum AnalyticsAgentDistribution: String, Sendable {
    case localCommand = "local_command"
    case npm
    case github
    case binary
    case uv
    case unknown
}

nonisolated enum AnalyticsMCPServerSource: String, Sendable {
    case registry
    case manual
    case unknown
}

nonisolated enum AnalyticsUpdateSource: String, Sendable {
    case settings
    case menu
    case unknown
}

nonisolated enum AnalyticsUpgradeSource: String, Sendable {
    case settings
    case featureGate = "feature_gate"
    case unknown
}
