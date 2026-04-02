//
//  GitHostingService.swift
//  aizen
//
//  Service for detecting Git hosting providers and managing PR operations
//

import Foundation
import os.log

// MARK: - Service

actor GitHostingService {
    static let shared = GitHostingService()

    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "GitHostingService")

    // Cache CLI paths
    private var cliPathCache: [GitHostingProvider: String?] = [:]
    // Cache hosting info and auth checks to avoid redundant CLI calls.
    private struct CachedHostingInfo {
        let info: GitHostingInfo
        let timestamp: Date
    }
    private struct CachedAuthStatus {
        let authenticated: Bool
        let timestamp: Date
    }
    private var hostingInfoCache: [String: CachedHostingInfo] = [:]
    private var hostingInfoTasks: [String: Task<GitHostingInfo?, Never>] = [:]
    private var authStatusCache: [GitHostingProvider: CachedAuthStatus] = [:]
    private var authStatusTasks: [GitHostingProvider: Task<Bool, Never>] = [:]

    private let hostingInfoTTL: TimeInterval = 60
    private let authStatusTTL: TimeInterval = 60

    // MARK: - CLI Execution Helper

    /// Execute CLI command with proper environment (matching GitLabWorkflowProvider pattern)
    func executeCLI(_ cliPath: String, arguments: [String], workingDirectory: String) async throws -> ProcessResult {
        logger.debug("Executing: \(cliPath) \(arguments.joined(separator: " "))")

        let env = ShellEnvironment.loadUserShellEnvironment()
        let result = try await ProcessExecutor.shared.executeWithOutput(
            executable: cliPath,
            arguments: arguments,
            environment: env,
            workingDirectory: workingDirectory
        )

        return result
    }

    // MARK: - Provider Detection

    func getHostingInfo(for repoPath: String) async -> GitHostingInfo? {
        if let cached = hostingInfoCache[repoPath],
           Date().timeIntervalSince(cached.timestamp) < hostingInfoTTL {
            return cached.info
        }

        if let task = hostingInfoTasks[repoPath] {
            return await task.value
        }

        let task = Task { [repoPath] in
            return await self.computeHostingInfo(repoPath: repoPath)
        }
        hostingInfoTasks[repoPath] = task

        let info = await task.value
        hostingInfoTasks[repoPath] = nil
        if let info = info {
            hostingInfoCache[repoPath] = CachedHostingInfo(info: info, timestamp: Date())
        }
        return info
    }

    private func computeHostingInfo(repoPath: String) async -> GitHostingInfo? {
        // Actor methods run on background executor, no need for Task.detached
        let remoteURL: String?
        do {
            let repo = try Libgit2Repository(path: repoPath)
            guard let remote = try repo.defaultRemote() else {
                return nil
            }
            remoteURL = remote.url
        } catch {
            logger.error("Failed to get hosting info: \(error.localizedDescription)")
            return nil
        }

        guard let remoteURL = remoteURL else { return nil }

        // Use WorkflowDetector for reliable provider detection (handles custom SSH aliases, self-hosted instances)
        let workflowProvider = await WorkflowDetector.shared.detect(repoPath: repoPath)
        let provider: GitHostingProvider
        switch workflowProvider {
        case .github: provider = .github
        case .gitlab: provider = .gitlab
        case .none: provider = GitHostingRemoteSupport.detectProvider(from: remoteURL)  // Fallback to URL-based detection
        }

        guard let (owner, repo) = GitHostingRemoteSupport.parseOwnerRepo(from: remoteURL) else {
            return nil
        }

        let baseURL = GitHostingRemoteSupport.extractBaseURL(from: remoteURL, provider: provider)
        let (cliInstalled, _) = await checkCLIInstalled(for: provider)
        let cliAuthenticated = cliInstalled ? await checkCLIAuthenticated(for: provider, repoPath: repoPath) : false

        return GitHostingInfo(
            provider: provider,
            owner: owner,
            repo: repo,
            baseURL: baseURL,
            cliInstalled: cliInstalled,
            cliAuthenticated: cliAuthenticated
        )
    }

    // MARK: - CLI Detection

    func checkCLIInstalled(for provider: GitHostingProvider) async -> (installed: Bool, path: String?) {
        guard let cliName = provider.cliName else {
            return (false, nil)
        }

        // Check cache (only positive results)
        if let cachedPath = cliPathCache[provider], cachedPath != nil {
            return (true, cachedPath)
        }

        // Check common paths (matching GitLabWorkflowProvider pattern)
        // Use fileExists instead of isExecutableFile for reliability
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/\(cliName)") {
            let path = "/opt/homebrew/bin/\(cliName)"
            cliPathCache[provider] = path
            return (true, path)
        }

        if FileManager.default.fileExists(atPath: "/usr/local/bin/\(cliName)") {
            let path = "/usr/local/bin/\(cliName)"
            cliPathCache[provider] = path
            return (true, path)
        }

        // Search PATH from the user's shell environment
        let env = ShellEnvironment.loadUserShellEnvironment()
        if let pathValue = env["PATH"], !pathValue.isEmpty {
            let pathEntries = pathValue.split(separator: ":", omittingEmptySubsequences: false)
            for entry in pathEntries {
                let rawEntry = entry.isEmpty ? "." : String(entry)
                let expandedEntry = (rawEntry as NSString).expandingTildeInPath
                let candidate = (expandedEntry as NSString).appendingPathComponent(cliName)
                if FileManager.default.fileExists(atPath: candidate) {
                    cliPathCache[provider] = candidate
                    return (true, candidate)
                }
            }
        }

        return (false, nil)
    }

    func checkCLIAuthenticated(for provider: GitHostingProvider, repoPath: String) async -> Bool {
        if let cached = authStatusCache[provider],
           Date().timeIntervalSince(cached.timestamp) < authStatusTTL {
            return cached.authenticated
        }

        if let task = authStatusTasks[provider] {
            return await task.value
        }

        let task = Task { [provider, repoPath] in
            return await self.computeCLIAuthenticated(for: provider, repoPath: repoPath)
        }
        authStatusTasks[provider] = task

        let authenticated = await task.value
        authStatusTasks[provider] = nil
        authStatusCache[provider] = CachedAuthStatus(authenticated: authenticated, timestamp: Date())
        return authenticated
    }

    private func computeCLIAuthenticated(for provider: GitHostingProvider, repoPath: String) async -> Bool {
        let (installed, path) = await checkCLIInstalled(for: provider)
        guard installed, let cliPath = path else { return false }

        do {
            switch provider {
            case .github:
                let result = try await executeCLI(cliPath, arguments: ["auth", "status"], workingDirectory: repoPath)
                return result.exitCode == 0

            case .gitlab:
                let result = try await executeCLI(cliPath, arguments: ["auth", "status"], workingDirectory: repoPath)
                return result.exitCode == 0

            case .azureDevOps:
                let result = try await executeCLI(cliPath, arguments: ["account", "show"], workingDirectory: repoPath)
                return result.exitCode == 0

            default:
                return false
            }
        } catch {
            logger.debug("CLI auth check failed: \(error.localizedDescription)")
            return false
        }
    }

}
