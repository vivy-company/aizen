//
//  AgentInstaller.swift
//  aizen
//
//  Agent installation manager coordinator for ACP agents
//

import Foundation

enum AgentInstallError: LocalizedError {
    case downloadFailed(message: String)
    case installFailed(message: String)
    case unsupportedPlatform
    case invalidResponse
    case fileSystemError(message: String)

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let message):
            return "Download failed: \(message)"
        case .installFailed(let message):
            return "Installation failed: \(message)"
        case .unsupportedPlatform:
            return "Unsupported platform"
        case .invalidResponse:
            return "Invalid server response"
        case .fileSystemError(let message):
            return "File system error: \(message)"
        }
    }
}

actor AgentInstaller {
    static let shared = AgentInstaller()

    private let baseInstallPath: String

    private init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        baseInstallPath = homeDir.appendingPathComponent(".aizen/agents").path
    }

    // MARK: - Installation Status

    func canInstall(_ metadata: AgentMetadata) -> Bool {
        return metadata.installMethod != nil
    }

    func isInstalled(_ agentName: String) -> Bool {
        let agentPath = getAgentExecutablePath(agentName)
        return FileManager.default.fileExists(atPath: agentPath) &&
               FileManager.default.isExecutableFile(atPath: agentPath)
    }

    func canUpdate(_ metadata: AgentMetadata) -> Bool {
        // Can update if:
        // 1. Has an install method (npm, binary, or githubRelease)
        // 2. Is currently installed in our managed .aizen/agents directory (not user-defined paths)
        guard metadata.installMethod != nil else { return false }

        // Get the expected path for our managed installation
        let managedPath = getAgentExecutablePath(metadata.id)
        guard !managedPath.isEmpty else { return false }

        // Verify executable is actually at the managed path, not a user-defined location
        guard let actualPath = metadata.executablePath else { return false }

        // Only allow updates if executable is exactly at our managed path
        return actualPath == managedPath && FileManager.default.fileExists(atPath: managedPath)
    }

    func getAgentExecutablePath(_ agentName: String) -> String {
        let agentDir = (baseInstallPath as NSString).appendingPathComponent(agentName)

        switch agentName {
        case "claude":
            return (agentDir as NSString).appendingPathComponent("node_modules/.bin/claude-code-acp")
        case "codex":
            return (agentDir as NSString).appendingPathComponent("node_modules/.bin/codex-acp")
        case "gemini":
            return (agentDir as NSString).appendingPathComponent("node_modules/.bin/gemini")
        case "kimi":
            return (agentDir as NSString).appendingPathComponent("kimi")
        case "opencode":
            return (agentDir as NSString).appendingPathComponent("node_modules/.bin/opencode")
        case "vibe":
            return (agentDir as NSString).appendingPathComponent("vibe-acp")
        case "qwen":
            return (agentDir as NSString).appendingPathComponent("node_modules/.bin/qwen")
        default:
            return ""
        }
    }

    // MARK: - Installation

    func installAgent(_ metadata: AgentMetadata) async throws {
        guard let installMethod = metadata.installMethod else {
            throw AgentInstallError.installFailed(message: "Agent '\(metadata.name)' has no installation method")
        }

        let agentDir = (baseInstallPath as NSString).appendingPathComponent(metadata.id)

        // Create directory if needed
        try createDirectoryIfNeeded(agentDir)

        // Route to appropriate installer
        switch installMethod {
        case .npm(let package):
            try await NPMAgentInstaller.shared.install(
                package: package,
                targetDir: agentDir
            )
        case .uv(let package):
            try await UVAgentInstaller.shared.install(
                package: package,
                targetDir: agentDir,
                executableName: metadata.id
            )
        case .binary(let urlString):
            let arch = getArchitecture()
            let resolvedURL = urlString.replacingOccurrences(of: "{arch}", with: arch)
            try await BinaryAgentInstaller.shared.install(
                from: resolvedURL,
                agentId: metadata.id,
                targetDir: agentDir
            )
        case .githubRelease(let repo, let assetPattern):
            try await GitHubReleaseInstaller.shared.install(
                repo: repo,
                assetPattern: assetPattern,
                agentId: metadata.id,
                targetDir: agentDir
            )
        }

        // Register the installed path
        let executablePath = getAgentExecutablePath(metadata.id)
        await AgentRegistry.shared.setAgentPath(executablePath, for: metadata.id)
    }

    // Legacy method for backwards compatibility
    func installAgent(_ agentName: String) async throws {
        let metadata = AgentRegistry.shared.getMetadata(for: agentName)
        guard let metadata = metadata else {
            throw AgentInstallError.installFailed(message: "Unknown agent: \(agentName)")
        }

        try await installAgent(metadata)
    }

    // MARK: - Update

    func updateAgent(_ metadata: AgentMetadata) async throws {
        guard canUpdate(metadata) else {
            throw AgentInstallError.installFailed(message: "Agent '\(metadata.name)' cannot be updated")
        }

        // Remove old installation
        let agentDir = (baseInstallPath as NSString).appendingPathComponent(metadata.id)
        if FileManager.default.fileExists(atPath: agentDir) {
            try FileManager.default.removeItem(atPath: agentDir)
        }

        // Reinstall with latest version
        try await installAgent(metadata)
    }

    // MARK: - Uninstallation

    func uninstallAgent(_ agentName: String) async throws {
        let agentDir = (baseInstallPath as NSString).appendingPathComponent(agentName)

        if FileManager.default.fileExists(atPath: agentDir) {
            try FileManager.default.removeItem(atPath: agentDir)
        }

        await AgentRegistry.shared.removeAgent(named: agentName)
    }

    // MARK: - Helpers

    private func createDirectoryIfNeeded(_ path: String) throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: path) {
            try fileManager.createDirectory(
                atPath: path,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }

    private func getArchitecture() -> String {
        #if arch(arm64)
        return "aarch64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}
