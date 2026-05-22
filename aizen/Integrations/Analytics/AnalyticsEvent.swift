//
//  AnalyticsEvent.swift
//  aizen
//
//  Auditable app analytics events. Keep all event data low-cardinality and content-free.
//

import Foundation

nonisolated enum AnalyticsEvent: Equatable, Sendable {
    case appOpened
    case appActiveDaily
    case workspaceCreated(workspaceCount: Int)
    case repositoryAdded(
        source: AnalyticsRepositorySource,
        provider: AnalyticsRepositoryProvider,
        repositoryCount: Int
    )
    case worktreeCreated(source: AnalyticsWorktreeSource, worktreeCount: Int)
    case agentSessionStarted(
        provider: AnalyticsAgentProvider,
        entryPoint: AnalyticsEntryPoint,
        hasAttachments: Bool
    )
    case terminalOpened(entryPoint: AnalyticsEntryPoint, splitCount: Int)
    case browserOpened(entryPoint: AnalyticsEntryPoint)
    case fileBrowserOpened(entryPoint: AnalyticsEntryPoint)
    case settingsOpened
    case customAgentCreated(distribution: AnalyticsAgentDistribution, customAgentCount: Int)
    case mcpServerAdded(source: AnalyticsMCPServerSource, serverCount: Int)
    case licenseActivated(tier: AnalyticsLicenseTier)
    case upgradeClicked(source: AnalyticsUpgradeSource)
    case updateCheckStarted(source: AnalyticsUpdateSource)
    case updateInstalled(previousVersionKnown: Bool, previousChannel: AnalyticsChannel)

    var name: String {
        switch self {
        case .appOpened:
            return "app_opened"
        case .appActiveDaily:
            return "app_active_daily"
        case .workspaceCreated:
            return "workspace_created"
        case .repositoryAdded:
            return "repository_added"
        case .worktreeCreated:
            return "worktree_created"
        case .agentSessionStarted:
            return "agent_session_started"
        case .terminalOpened:
            return "terminal_opened"
        case .browserOpened:
            return "browser_opened"
        case .fileBrowserOpened:
            return "file_browser_opened"
        case .settingsOpened:
            return "settings_opened"
        case .customAgentCreated:
            return "custom_agent_created"
        case .mcpServerAdded:
            return "mcp_server_added"
        case .licenseActivated:
            return "license_activated"
        case .upgradeClicked:
            return "upgrade_clicked"
        case .updateCheckStarted:
            return "update_check_started"
        case .updateInstalled:
            return "update_installed"
        }
    }

    var url: String {
        switch self {
        case .appOpened, .appActiveDaily:
            return "/app"
        case .workspaceCreated:
            return "/workspace"
        case .repositoryAdded:
            return "/repository"
        case .worktreeCreated:
            return "/worktree"
        case .agentSessionStarted:
            return "/agent-session"
        case .terminalOpened:
            return "/terminal"
        case .browserOpened:
            return "/browser"
        case .fileBrowserOpened:
            return "/files"
        case .settingsOpened, .customAgentCreated, .mcpServerAdded:
            return "/settings"
        case .licenseActivated, .upgradeClicked:
            return "/license"
        case .updateCheckStarted, .updateInstalled:
            return "/updates"
        }
    }

    var properties: [String: AnalyticsPropertyValue] {
        switch self {
        case .appOpened, .appActiveDaily, .settingsOpened:
            return [:]

        case .workspaceCreated(let workspaceCount):
            return [
                "workspace_count_bucket": .string(AnalyticsCountBucket.bucket(for: workspaceCount).rawValue)
            ]

        case .repositoryAdded(let source, let provider, let repositoryCount):
            return [
                "source": .string(source.rawValue),
                "provider": .string(provider.rawValue),
                "repository_count_bucket": .string(AnalyticsCountBucket.bucket(for: repositoryCount).rawValue)
            ]

        case .worktreeCreated(let source, let worktreeCount):
            return [
                "source": .string(source.rawValue),
                "worktree_count_bucket": .string(AnalyticsCountBucket.bucket(for: worktreeCount).rawValue)
            ]

        case .agentSessionStarted(let provider, let entryPoint, let hasAttachments):
            return [
                "provider": .string(provider.rawValue),
                "entry_point": .string(entryPoint.rawValue),
                "has_attachments": .bool(hasAttachments)
            ]

        case .terminalOpened(let entryPoint, let splitCount):
            return [
                "entry_point": .string(entryPoint.rawValue),
                "split_count_bucket": .string(AnalyticsCountBucket.bucket(for: splitCount).rawValue)
            ]

        case .browserOpened(let entryPoint), .fileBrowserOpened(let entryPoint):
            return [
                "entry_point": .string(entryPoint.rawValue)
            ]

        case .customAgentCreated(let distribution, let customAgentCount):
            return [
                "distribution": .string(distribution.rawValue),
                "custom_agent_count_bucket": .string(AnalyticsCountBucket.bucket(for: customAgentCount).rawValue)
            ]

        case .mcpServerAdded(let source, let serverCount):
            return [
                "source": .string(source.rawValue),
                "server_count_bucket": .string(AnalyticsCountBucket.bucket(for: serverCount).rawValue)
            ]

        case .licenseActivated(let tier):
            return [
                "license_tier": .string(tier.rawValue)
            ]

        case .upgradeClicked(let source):
            return [
                "source": .string(source.rawValue)
            ]

        case .updateCheckStarted(let source):
            return [
                "source": .string(source.rawValue)
            ]

        case .updateInstalled(let previousVersionKnown, let previousChannel):
            return [
                "previous_version_known": .bool(previousVersionKnown),
                "previous_channel": .string(previousChannel.rawValue)
            ]
        }
    }
}
