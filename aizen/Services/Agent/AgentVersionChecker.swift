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

    private let baseInstallPath: String

    private init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        baseInstallPath = homeDir.appendingPathComponent(".aizen/agents").path
    }

    /// Check if an agent's version is outdated
    func checkVersion(for agentName: String) async -> AgentVersionInfo {
        // Check cache first
        if let cached = versionCache[agentName],
           let lastCheck = lastCheckTime[agentName],
           Date().timeIntervalSince(lastCheck) < cacheExpiration {
            return cached
        }

        let metadata = AgentRegistry.shared.getMetadata(for: agentName)
        guard let installMethod = metadata?.installMethod else {
            return AgentVersionInfo(current: nil, latest: nil, isOutdated: false, updateAvailable: false)
        }

        let agentDir = (baseInstallPath as NSString).appendingPathComponent(agentName)
        let info: AgentVersionInfo

        switch installMethod {
        case .npm(let package):
            info = await checkNpmVersion(package: package, agentDir: agentDir)
        case .uv(let package):
            info = await checkUvVersion(package: package, agentDir: agentDir)
        case .githubRelease(let repo, _):
            info = await checkGithubVersion(repo: repo, agentDir: agentDir)
        case .binary:
            // Binary installs don't have version tracking
            info = AgentVersionInfo(current: nil, latest: nil, isOutdated: false, updateAvailable: false)
        case .script:
            // Script installs don't have version tracking
            info = AgentVersionInfo(current: nil, latest: nil, isOutdated: false, updateAvailable: false)
        }

        // Cache the result
        versionCache[agentName] = info
        lastCheckTime[agentName] = Date()

        return info
    }

    // MARK: - NPM Version Detection

    /// Check NPM package version using local package.json
    private func checkNpmVersion(package: String, agentDir: String) async -> AgentVersionInfo {
        // Get current version from local installation
        let currentVersion = await getCurrentNpmVersion(package: package, agentDir: agentDir)

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

    /// Get current installed NPM package version from local package.json
    private func getCurrentNpmVersion(package: String, agentDir: String) async -> String? {
        // First try .version manifest file (written at install time)
        if let version = readVersionManifest(agentDir: agentDir) {
            return version
        }

        // Fallback: read from local node_modules package.json
        return await NPMAgentInstaller.shared.getInstalledVersion(package: package, targetDir: agentDir)
    }

    /// Get latest NPM package version from registry
    private func getLatestNpmVersion(package: String) async -> String? {
        // Strip version specifiers like @latest before querying
        let cleanPackage = stripVersionSpecifier(from: package)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["npm", "view", cleanPackage, "version"]
        process.environment = ShellEnvironment.loadUserShellEnvironment()

        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
            try? pipe.fileHandleForReading.close()
            try? errorPipe.fileHandleForReading.close()
            if let version = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !version.isEmpty {
                return version
            }
        } catch {
            try? pipe.fileHandleForReading.close()
            try? errorPipe.fileHandleForReading.close()
        }

        return nil
    }

    /// Strip version specifier from package name (e.g., "opencode-ai@latest" -> "opencode-ai")
    private func stripVersionSpecifier(from package: String) -> String {
        // Handle scoped packages: @scope/name@version -> @scope/name
        if package.hasPrefix("@") {
            if let slashIndex = package.firstIndex(of: "/") {
                let afterSlash = package[package.index(after: slashIndex)...]
                if let atIndex = afterSlash.firstIndex(of: "@") {
                    return String(package[..<atIndex])
                }
            }
            return package
        }

        // Simple package: name@version -> name
        if let atIndex = package.firstIndex(of: "@") {
            return String(package[..<atIndex])
        }

        return package
    }

    // MARK: - GitHub Version Detection

    /// Check GitHub release version
    private func checkGithubVersion(repo: String, agentDir: String) async -> AgentVersionInfo {
        // Get current version from manifest or binary
        let currentVersion = getCurrentGithubVersion(agentDir: agentDir)

        // Get latest version from GitHub API
        let latestVersion = await GitHubReleaseInstaller.shared.getLatestVersion(repo: repo)

        let isOutdated = compareVersions(current: currentVersion, latest: latestVersion)

        return AgentVersionInfo(
            current: currentVersion,
            latest: latestVersion,
            isOutdated: isOutdated,
            updateAvailable: isOutdated
        )
    }

    /// Get current GitHub release version from manifest
    private func getCurrentGithubVersion(agentDir: String) -> String? {
        // First try .version manifest file (written at install time)
        if let version = readVersionManifest(agentDir: agentDir) {
            return version
        }

        // Fallback: try --version flag on binary
        // Find the binary in the agent directory
        let fileManager = FileManager.default
        if let contents = try? fileManager.contentsOfDirectory(atPath: agentDir) {
            for file in contents where !file.hasPrefix(".") {
                let filePath = (agentDir as NSString).appendingPathComponent(file)
                if fileManager.isExecutableFile(atPath: filePath) {
                    if let version = getBinaryVersion(path: filePath) {
                        return version
                    }
                }
            }
        }

        return nil
    }

    // MARK: - UV (Python) Version Detection

    /// Check UV package version
    private func checkUvVersion(package: String, agentDir: String) async -> AgentVersionInfo {
        // Get current version from manifest or binary
        let currentVersion = getCurrentUvVersion(agentDir: agentDir)

        // Get latest version from PyPI
        let latestVersion = await getLatestPyPIVersion(package: package)

        let isOutdated = compareVersions(current: currentVersion, latest: latestVersion)

        return AgentVersionInfo(
            current: currentVersion,
            latest: latestVersion,
            isOutdated: isOutdated,
            updateAvailable: isOutdated
        )
    }

    /// Get current UV package version from manifest or binary
    private func getCurrentUvVersion(agentDir: String) -> String? {
        // First try .version manifest file
        if let version = readVersionManifest(agentDir: agentDir) {
            return version
        }

        // Fallback: try --version on any executable in the directory
        let fileManager = FileManager.default
        if let contents = try? fileManager.contentsOfDirectory(atPath: agentDir) {
            for file in contents where !file.hasPrefix(".") && !file.hasSuffix("-cli") {
                let filePath = (agentDir as NSString).appendingPathComponent(file)
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: filePath, isDirectory: &isDir),
                   !isDir.boolValue,
                   fileManager.isExecutableFile(atPath: filePath) {
                    if let version = getBinaryVersion(path: filePath) {
                        return version
                    }
                }
            }
        }

        return nil
    }

    /// Get latest version from PyPI
    private func getLatestPyPIVersion(package: String) async -> String? {
        guard let url = URL(string: "https://pypi.org/pypi/\(package)/json") else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let info = json["info"] as? [String: Any],
               let version = info["version"] as? String {
                return version
            }
        } catch {
        }

        return nil
    }

    // MARK: - Helpers

    /// Read version from manifest file
    private func readVersionManifest(agentDir: String) -> String? {
        let manifestPath = (agentDir as NSString).appendingPathComponent(".version")
        guard let version = try? String(contentsOfFile: manifestPath, encoding: .utf8) else {
            return nil
        }
        return version.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Get binary version by executing with --version flag
    private func getBinaryVersion(path: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]

        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
            try? pipe.fileHandleForReading.close()
            try? errorPipe.fileHandleForReading.close()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !output.isEmpty {
                return extractVersionNumber(from: output)
            }
        } catch {
            try? pipe.fileHandleForReading.close()
            try? errorPipe.fileHandleForReading.close()
            // Binary doesn't support --version, that's ok
        }

        return nil
    }

    /// Extract version number from version string
    private func extractVersionNumber(from output: String) -> String? {
        // Match version pattern with 2 or 3 parts (e.g., "1.2", "1.2.3", "v1.2.3")
        let pattern = #"v?(\d+\.\d+(?:\.\d+)?)"#
        if let range = output.range(of: pattern, options: .regularExpression),
           let match = output[range].firstMatch(of: /v?(\d+\.\d+(?:\.\d+)?)/) {
            return String(match.1)
        }
        return nil
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

    /// Write version manifest for an agent (for migration of existing installs)
    func writeVersionManifest(for agentName: String, version: String) {
        let agentDir = (baseInstallPath as NSString).appendingPathComponent(agentName)
        let manifestPath = (agentDir as NSString).appendingPathComponent(".version")
        try? version.write(toFile: manifestPath, atomically: true, encoding: .utf8)
    }
}
