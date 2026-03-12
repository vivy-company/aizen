//
//  AgentVersionChecker.swift
//  aizen
//

import ACPRegistry
import Foundation

struct AgentVersionInfo: Codable {
    let current: String?
    let latest: String?
    let isOutdated: Bool
    let updateAvailable: Bool
}

actor AgentVersionChecker {
    static let shared = AgentVersionChecker()

    private var versionCache: [String: AgentVersionInfo] = [:]
    private var lastCheckTime: [String: Date] = [:]
    private let cacheExpiration: TimeInterval = 3600

    func checkVersion(for agentName: String) async -> AgentVersionInfo {
        if let cached = versionCache[agentName],
           let lastCheck = lastCheckTime[agentName],
           Date().timeIntervalSince(lastCheck) < cacheExpiration {
            return cached
        }

        guard let metadata = AgentRegistry.shared.getMetadata(for: agentName),
              metadata.isRegistry else {
            return AgentVersionInfo(current: nil, latest: nil, isOutdated: false, updateAvailable: false)
        }

        let latestAgent = try? await ACPRegistryService.shared.agent(id: metadata.id, forceRefresh: false)
        let latestVersion = latestAgent?.version
        let currentVersion = metadata.registryVersion
        let isOutdated = currentVersion != nil && latestVersion != nil && currentVersion != latestVersion

        let info = AgentVersionInfo(
            current: currentVersion,
            latest: latestVersion,
            isOutdated: isOutdated,
            updateAvailable: isOutdated
        )

        versionCache[agentName] = info
        lastCheckTime[agentName] = Date()
        return info
    }

    func clearCache(for agentName: String) {
        versionCache[agentName] = nil
        lastCheckTime[agentName] = nil
    }
}
