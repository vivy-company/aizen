//
//  AgentVersionChecker.swift
//  aizen
//
//  Service to check ACP agent versions and suggest updates
//

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
    private let cacheExpiration: TimeInterval = 3600 // 1 hour

    private init() {}

    /// Check if an agent's version is outdated
    func checkVersion(for agentName: String) async -> AgentVersionInfo {
        // Check cache first
        if let cached = versionCache[agentName],
           let lastCheck = lastCheckTime[agentName],
           Date().timeIntervalSince(lastCheck) < cacheExpiration {
            return cached
        }

        let metadata = AgentRegistry.shared.getMetadata(for: agentName)
        guard let agentPath = metadata?.executablePath else {
            return AgentVersionInfo(current: nil, latest: nil, isOutdated: false, updateAvailable: false)
        }

        // Detect actual install method by inspecting the binary
        let actualInstallMethod = await detectInstallMethod(agentPath: agentPath, configuredMethod: metadata?.installMethod)

        let info: AgentVersionInfo

        switch actualInstallMethod {
        case .npm(let package):
            info = await checkNpmVersion(package: package, agentPath: agentPath)
        case .githubRelease(let repo, _):
            info = await checkGithubVersion(repo: repo, agentPath: agentPath)
        default:
            info = AgentVersionInfo(current: nil, latest: nil, isOutdated: false, updateAvailable: false)
        }

        // Cache the result
        versionCache[agentName] = info
        lastCheckTime[agentName] = Date()

        return info
    }

    /// Detect actual install method by inspecting the binary
    private func detectInstallMethod(agentPath: String, configuredMethod: AgentInstallMethod?) async -> AgentInstallMethod? {
        // Check if it's a symlink to node_modules (npm install)
        if let resolvedPath = try? FileManager.default.destinationOfSymbolicLink(atPath: agentPath),
           resolvedPath.contains("node_modules") {
            // Extract package name from path like: ../lib/node_modules/@scope/package/dist/index.js
            if let packageMatch = resolvedPath.range(of: #"node_modules/([^/]+(?:/[^/]+)?)"#, options: .regularExpression) {
                let packagePath = String(resolvedPath[packageMatch])
                let packageName = packagePath.replacingOccurrences(of: "node_modules/", with: "")
                return .npm(package: packageName)
            }
            // Fallback to configured method if we found node_modules but couldn't extract package
            if case .npm(let package) = configuredMethod {
                return .npm(package: package)
            }
        }

        // If not npm, return configured method
        return configuredMethod
    }

    /// Check NPM package version
    private func checkNpmVersion(package: String, agentPath: String?) async -> AgentVersionInfo {
        // Get current installed version
        let currentVersion = await getCurrentNpmVersion(package: package)

        // Get latest version from npm registry
        let latestVersion = await getLatestNpmVersion(package: package)

        let isOutdated = compareVersions(current: currentVersion, latest: latestVersion)

        return AgentVersionInfo(
            current: currentVersion,
            latest: latestVersion,
            isOutdated: isOutdated,
            updateAvailable: isOutdated
        )
    }

    /// Get current installed NPM package version
    private func getCurrentNpmVersion(package: String) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["npm", "list", "-g", package, "--json"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dependencies = json["dependencies"] as? [String: Any],
               let packageInfo = dependencies[package] as? [String: Any],
               let version = packageInfo["version"] as? String {
                return version
            }
        } catch {
            print("[AgentVersionChecker] Failed to get current npm version for \(package): \(error)")
        }

        return nil
    }

    /// Get latest NPM package version from registry
    private func getLatestNpmVersion(package: String) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["npm", "view", package, "version"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let version = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !version.isEmpty {
                return version
            }
        } catch {
            print("[AgentVersionChecker] Failed to get latest npm version for \(package): \(error)")
        }

        return nil
    }

    /// Check GitHub release version (placeholder - implement if needed)
    private func checkGithubVersion(repo: String, agentPath: String?) async -> AgentVersionInfo {
        // TODO: Implement GitHub release version checking via API
        return AgentVersionInfo(current: nil, latest: nil, isOutdated: false, updateAvailable: false)
    }

    /// Compare semantic versions
    private func compareVersions(current: String?, latest: String?) -> Bool {
        guard let current = current, let latest = latest else {
            return false
        }

        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        let latestParts = latest.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(currentParts.count, latestParts.count) {
            let currentPart = i < currentParts.count ? currentParts[i] : 0
            let latestPart = i < latestParts.count ? latestParts[i] : 0

            if latestPart > currentPart {
                return true // Outdated
            } else if latestPart < currentPart {
                return false // Newer than latest (dev version?)
            }
        }

        return false // Same version
    }

    /// Clear cache for an agent
    func clearCache(for agentName: String) {
        versionCache.removeValue(forKey: agentName)
        lastCheckTime.removeValue(forKey: agentName)
    }

    /// Clear all caches
    func clearAllCaches() {
        versionCache.removeAll()
        lastCheckTime.removeAll()
    }
}
