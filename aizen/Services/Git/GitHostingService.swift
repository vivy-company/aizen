//
//  GitHostingService.swift
//  aizen
//
//  Service for detecting Git hosting providers and managing PR operations
//

import Foundation
import AppKit
import os.log

// MARK: - Types

enum GitHostingProvider: String, Sendable {
    case github
    case gitlab
    case bitbucket
    case azureDevOps
    case unknown

    var displayName: String {
        switch self {
        case .github: return "GitHub"
        case .gitlab: return "GitLab"
        case .bitbucket: return "Bitbucket"
        case .azureDevOps: return "Azure DevOps"
        case .unknown: return "Unknown"
        }
    }

    var cliName: String? {
        switch self {
        case .github: return "gh"
        case .gitlab: return "glab"
        case .azureDevOps: return "az"
        case .bitbucket, .unknown: return nil
        }
    }

    var prTerminology: String {
        switch self {
        case .gitlab: return "Merge Request"
        default: return "Pull Request"
        }
    }

    var installInstructions: String {
        switch self {
        case .github: return "brew install gh && gh auth login"
        case .gitlab: return "brew install glab && glab auth login"
        case .azureDevOps: return "brew install azure-cli && az login"
        case .bitbucket, .unknown: return ""
        }
    }
}

struct GitHostingInfo: Sendable {
    let provider: GitHostingProvider
    let owner: String
    let repo: String
    let baseURL: String
    let cliInstalled: Bool
    let cliAuthenticated: Bool
}

enum PRStatus: Sendable, Equatable {
    case unknown
    case noPR
    case open(number: Int, url: String, mergeable: Bool, title: String)
    case merged
    case closed

    static func == (lhs: PRStatus, rhs: PRStatus) -> Bool {
        switch (lhs, rhs) {
        case (.unknown, .unknown), (.noPR, .noPR), (.merged, .merged), (.closed, .closed):
            return true
        case let (.open(n1, u1, m1, t1), .open(n2, u2, m2, t2)):
            return n1 == n2 && u1 == u2 && m1 == m2 && t1 == t2
        default:
            return false
        }
    }
}

enum GitHostingAction {
    case createPR(sourceBranch: String, targetBranch: String?)
    case viewPR(number: Int)
    case viewRepo
}

enum GitHostingError: LocalizedError {
    case cliNotInstalled(provider: GitHostingProvider)
    case cliNotAuthenticated(provider: GitHostingProvider)
    case commandFailed(message: String)
    case unsupportedProvider
    case noRemoteFound

    var errorDescription: String? {
        switch self {
        case .cliNotInstalled(let provider):
            return "\(provider.cliName ?? "CLI") is not installed"
        case .cliNotAuthenticated(let provider):
            return "\(provider.cliName ?? "CLI") is not authenticated"
        case .commandFailed(let message):
            return message
        case .unsupportedProvider:
            return "This Git hosting provider is not supported"
        case .noRemoteFound:
            return "No remote repository found"
        }
    }
}

// MARK: - Service

actor GitHostingService {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "GitHostingService")

    // Cache CLI paths
    private var cliPathCache: [GitHostingProvider: String?] = [:]

    // MARK: - CLI Execution Helper

    /// Execute CLI command with proper environment (matching GitLabWorkflowProvider pattern)
    private func executeCLI(_ cliPath: String, arguments: [String], workingDirectory: String) async throws -> ProcessResult {
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

    func detectProvider(from remoteURL: String) -> GitHostingProvider {
        let lowercased = remoteURL.lowercased()

        if lowercased.contains("github.com") {
            return .github
        } else if lowercased.contains("gitlab.com") || lowercased.contains("gitlab.") {
            return .gitlab
        } else if lowercased.contains("bitbucket.org") {
            return .bitbucket
        } else if lowercased.contains("dev.azure.com") || lowercased.contains("visualstudio.com") {
            return .azureDevOps
        }

        return .unknown
    }

    func parseOwnerRepo(from remoteURL: String) -> (owner: String, repo: String)? {
        // Handle SSH format: git@github.com:owner/repo.git
        if remoteURL.contains("@") && remoteURL.contains(":") {
            let parts = remoteURL.components(separatedBy: ":")
            guard parts.count >= 2 else { return nil }
            let pathPart = parts[1]
            return parsePathComponents(pathPart)
        }

        // Handle HTTPS format: https://github.com/owner/repo.git
        guard let url = URL(string: remoteURL) else { return nil }
        let path = url.path
        return parsePathComponents(path)
    }

    private func parsePathComponents(_ path: String) -> (owner: String, repo: String)? {
        var cleanPath = path
        if cleanPath.hasPrefix("/") {
            cleanPath = String(cleanPath.dropFirst())
        }
        if cleanPath.hasSuffix(".git") {
            cleanPath = String(cleanPath.dropLast(4))
        }

        let components = cleanPath.components(separatedBy: "/")
        guard components.count >= 2 else { return nil }

        return (owner: components[0], repo: components[1])
    }

    func getHostingInfo(for repoPath: String) async -> GitHostingInfo? {
        // Run libgit2 operations on background thread
        let remoteURL: String?
        do {
            remoteURL = try await Task.detached {
                let repo = try Libgit2Repository(path: repoPath)
                guard let remote = try repo.defaultRemote() else {
                    return nil
                }
                return remote.url
            }.value
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
        case .none: provider = detectProvider(from: remoteURL)  // Fallback to URL-based detection
        }

        guard let (owner, repo) = parseOwnerRepo(from: remoteURL) else {
            return nil
        }

        let baseURL = extractBaseURL(from: remoteURL, provider: provider)
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

    private func extractBaseURL(from remoteURL: String, provider: GitHostingProvider) -> String {
        switch provider {
        case .github:
            return "https://github.com"
        case .gitlab:
            if let url = URL(string: remoteURL), let host = url.host {
                return "https://\(host)"
            }
            return "https://gitlab.com"
        case .bitbucket:
            return "https://bitbucket.org"
        case .azureDevOps:
            if let url = URL(string: remoteURL), let host = url.host {
                return "https://\(host)"
            }
            return "https://dev.azure.com"
        case .unknown:
            return ""
        }
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

    // MARK: - PR Status

    func getPRStatus(repoPath: String, branch: String) async -> PRStatus {
        guard let info = await getHostingInfo(for: repoPath) else {
            return .unknown
        }

        guard info.cliInstalled && info.cliAuthenticated else {
            return .unknown
        }

        let (_, cliPath) = await checkCLIInstalled(for: info.provider)
        guard let path = cliPath else { return .unknown }

        do {
            switch info.provider {
            case .github:
                return try await getGitHubPRStatus(cliPath: path, repoPath: repoPath, branch: branch)
            case .gitlab:
                return try await getGitLabMRStatus(cliPath: path, repoPath: repoPath, branch: branch)
            default:
                return .unknown
            }
        } catch {
            logger.error("Failed to get PR status: \(error.localizedDescription)")
            return .unknown
        }
    }

    private func getGitHubPRStatus(cliPath: String, repoPath: String, branch: String) async throws -> PRStatus {
        let result = try await executeCLI(cliPath, arguments: ["pr", "view", "--json", "number,url,state,mergeable,title", "--head", branch], workingDirectory: repoPath)

        if result.exitCode != 0 {
            // No PR found
            if result.stderr.contains("no pull requests found") || result.stderr.contains("Could not resolve") {
                return .noPR
            }
            return .unknown
        }

        guard let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .unknown
        }

        let state = json["state"] as? String ?? ""
        let number = json["number"] as? Int ?? 0
        let url = json["url"] as? String ?? ""
        let mergeable = json["mergeable"] as? String ?? ""
        let title = json["title"] as? String ?? ""

        switch state.uppercased() {
        case "OPEN":
            return .open(number: number, url: url, mergeable: mergeable == "MERGEABLE", title: title)
        case "MERGED":
            return .merged
        case "CLOSED":
            return .closed
        default:
            return .unknown
        }
    }

    private func getGitLabMRStatus(cliPath: String, repoPath: String, branch: String) async throws -> PRStatus {
        let result = try await executeCLI(cliPath, arguments: ["mr", "view", "--output", "json", branch], workingDirectory: repoPath)

        if result.exitCode != 0 {
            if result.stderr.contains("no merge request") || result.stderr.contains("not found") {
                return .noPR
            }
            return .unknown
        }

        guard let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .unknown
        }

        let state = json["state"] as? String ?? ""
        let iid = json["iid"] as? Int ?? 0
        let webUrl = json["web_url"] as? String ?? ""
        let mergeStatus = json["merge_status"] as? String ?? ""
        let title = json["title"] as? String ?? ""

        switch state.lowercased() {
        case "opened":
            return .open(number: iid, url: webUrl, mergeable: mergeStatus == "can_be_merged", title: title)
        case "merged":
            return .merged
        case "closed":
            return .closed
        default:
            return .unknown
        }
    }

    // MARK: - PR Operations

    func createPR(repoPath: String, sourceBranch: String) async throws {
        guard let info = await getHostingInfo(for: repoPath) else {
            throw GitHostingError.noRemoteFound
        }

        if !info.cliInstalled {
            throw GitHostingError.cliNotInstalled(provider: info.provider)
        }

        if !info.cliAuthenticated {
            throw GitHostingError.cliNotAuthenticated(provider: info.provider)
        }

        let (_, cliPath) = await checkCLIInstalled(for: info.provider)
        guard let path = cliPath else {
            throw GitHostingError.cliNotInstalled(provider: info.provider)
        }

        // Open interactive PR creation in terminal
        switch info.provider {
        case .github:
            let result = try await executeCLI(path, arguments: ["pr", "create", "--web"], workingDirectory: repoPath)
            if result.exitCode != 0 && !result.stderr.isEmpty {
                throw GitHostingError.commandFailed(message: result.stderr)
            }

        case .gitlab:
            let result = try await executeCLI(path, arguments: ["mr", "create", "--web"], workingDirectory: repoPath)
            if result.exitCode != 0 && !result.stderr.isEmpty {
                throw GitHostingError.commandFailed(message: result.stderr)
            }

        case .azureDevOps:
            let result = try await executeCLI(path, arguments: ["repos", "pr", "create", "--open"], workingDirectory: repoPath)
            if result.exitCode != 0 && !result.stderr.isEmpty {
                throw GitHostingError.commandFailed(message: result.stderr)
            }

        default:
            throw GitHostingError.unsupportedProvider
        }
    }

    func mergePR(repoPath: String, prNumber: Int) async throws {
        guard let info = await getHostingInfo(for: repoPath) else {
            throw GitHostingError.noRemoteFound
        }

        if !info.cliInstalled {
            throw GitHostingError.cliNotInstalled(provider: info.provider)
        }

        if !info.cliAuthenticated {
            throw GitHostingError.cliNotAuthenticated(provider: info.provider)
        }

        let (_, cliPath) = await checkCLIInstalled(for: info.provider)
        guard let path = cliPath else {
            throw GitHostingError.cliNotInstalled(provider: info.provider)
        }

        switch info.provider {
        case .github:
            let result = try await executeCLI(path, arguments: ["pr", "merge", String(prNumber), "--merge"], workingDirectory: repoPath)
            if result.exitCode != 0 {
                throw GitHostingError.commandFailed(message: result.stderr)
            }

        case .gitlab:
            let result = try await executeCLI(path, arguments: ["mr", "merge", String(prNumber)], workingDirectory: repoPath)
            if result.exitCode != 0 {
                throw GitHostingError.commandFailed(message: result.stderr)
            }

        default:
            throw GitHostingError.unsupportedProvider
        }
    }

    // MARK: - PR List

    func listPullRequests(
        repoPath: String,
        filter: PRFilter = .open,
        page: Int = 1,
        limit: Int = 30
    ) async throws -> [PullRequest] {
        guard let info = await getHostingInfo(for: repoPath) else {
            throw GitHostingError.noRemoteFound
        }

        guard info.cliInstalled else {
            throw GitHostingError.cliNotInstalled(provider: info.provider)
        }

        guard info.cliAuthenticated else {
            throw GitHostingError.cliNotAuthenticated(provider: info.provider)
        }

        let (_, cliPath) = await checkCLIInstalled(for: info.provider)
        guard let path = cliPath else {
            throw GitHostingError.cliNotInstalled(provider: info.provider)
        }

        let sanitizedPage = max(page, 1)

        switch info.provider {
        case .github:
            return try await listGitHubPRs(
                cliPath: path,
                repoPath: repoPath,
                filter: filter,
                page: sanitizedPage,
                limit: limit
            )
        case .gitlab:
            return try await listGitLabMRs(
                cliPath: path,
                repoPath: repoPath,
                filter: filter,
                page: sanitizedPage,
                limit: limit
            )
        default:
            throw GitHostingError.unsupportedProvider
        }
    }

    private func listGitHubPRs(
        cliPath: String,
        repoPath: String,
        filter: PRFilter,
        page: Int,
        limit: Int
    ) async throws -> [PullRequest] {
        let normalizedLimit = max(limit, 1)
        let fetchLimit = normalizedLimit * max(page, 1)
        let arguments = [
            "pr", "list",
            "--json", "number,title,body,state,author,headRefName,baseRefName,url,createdAt,updatedAt,isDraft,mergeable,reviewDecision,statusCheckRollup,additions,deletions,changedFiles",
            "--limit", String(fetchLimit),
            "--state", filter.cliValue
        ]

        let result = try await executeCLI(cliPath, arguments: arguments, workingDirectory: repoPath)

        guard result.exitCode == 0 else {
            throw GitHostingError.commandFailed(message: result.stderr)
        }

        guard let data = result.stdout.data(using: .utf8) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        struct GitHubPR: Decodable {
            let number: Int
            let title: String
            let body: String?
            let state: String
            let author: Author
            let headRefName: String
            let baseRefName: String
            let url: String
            let createdAt: Date
            let updatedAt: Date
            let isDraft: Bool
            let mergeable: String?
            let reviewDecision: String?
            let statusCheckRollup: [StatusCheck]?
            let additions: Int?
            let deletions: Int?
            let changedFiles: Int?

            struct Author: Decodable {
                let login: String
            }

            struct StatusCheck: Decodable {
                let conclusion: String?
                let status: String?
            }
        }

        let prs = try decoder.decode([GitHubPR].self, from: data)
        let startIndex = (max(page, 1) - 1) * normalizedLimit
        let pageItems = prs.dropFirst(startIndex).prefix(normalizedLimit)

        return pageItems.map { pr in
            let mergeableState: PullRequest.MergeableState
            switch pr.mergeable?.uppercased() {
            case "MERGEABLE": mergeableState = .mergeable
            case "CONFLICTING": mergeableState = .conflicting
            default: mergeableState = .unknown
            }

            let reviewDecision = pr.reviewDecision.flatMap { PullRequest.ReviewDecision(rawValue: $0) }

            let checksStatus: PullRequest.ChecksStatus?
            if let checks = pr.statusCheckRollup, !checks.isEmpty {
                if checks.allSatisfy({ $0.conclusion == "SUCCESS" }) {
                    checksStatus = .passing
                } else if checks.contains(where: { $0.conclusion == "FAILURE" }) {
                    checksStatus = .failing
                } else {
                    checksStatus = .pending
                }
            } else {
                checksStatus = nil
            }

            let state: PullRequest.State
            switch pr.state.uppercased() {
            case "MERGED": state = .merged
            case "CLOSED": state = .closed
            default: state = .open
            }

            return PullRequest(
                id: pr.number,
                number: pr.number,
                title: pr.title,
                body: pr.body ?? "",
                state: state,
                author: pr.author.login,
                sourceBranch: pr.headRefName,
                targetBranch: pr.baseRefName,
                url: pr.url,
                createdAt: pr.createdAt,
                updatedAt: pr.updatedAt,
                isDraft: pr.isDraft,
                mergeable: mergeableState,
                reviewDecision: reviewDecision,
                checksStatus: checksStatus,
                additions: pr.additions ?? 0,
                deletions: pr.deletions ?? 0,
                changedFiles: pr.changedFiles ?? 0
            )
        }
    }

    private func listGitLabMRs(
        cliPath: String,
        repoPath: String,
        filter: PRFilter,
        page: Int,
        limit: Int
    ) async throws -> [PullRequest] {
        var arguments = [
            "mr", "list",
            "-F", "json",
            "--per-page", String(limit),
            "--page", String(max(page, 1))
        ]

        // glab uses different flags: -A/--all, -c/--closed, -M/--merged (default is open)
        switch filter {
        case .all:
            arguments.append("-A")
        case .closed:
            arguments.append("-c")
        case .merged:
            arguments.append("-M")
        case .open:
            break  // Default is open
        }

        let result = try await executeCLI(cliPath, arguments: arguments, workingDirectory: repoPath)

        guard result.exitCode == 0 else {
            throw GitHostingError.commandFailed(message: result.stderr)
        }

        guard let data = result.stdout.data(using: .utf8) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        struct GitLabMR: Decodable {
            let iid: Int
            let title: String
            let description: String?
            let state: String
            let author: Author
            let sourceBranch: String
            let targetBranch: String
            let webUrl: String
            let createdAt: String
            let updatedAt: String
            let draft: Bool?
            let mergeStatus: String?

            struct Author: Decodable {
                let username: String
            }
        }

        let mrs = try decoder.decode([GitLabMR].self, from: data)

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]

        return mrs.map { mr in
            let mergeableState: PullRequest.MergeableState
            switch mr.mergeStatus {
            case "can_be_merged": mergeableState = .mergeable
            case "cannot_be_merged": mergeableState = .conflicting
            default: mergeableState = .unknown
            }

            let state: PullRequest.State
            switch mr.state.lowercased() {
            case "merged": state = .merged
            case "closed": state = .closed
            default: state = .open
            }

            let createdAt = dateFormatter.date(from: mr.createdAt) ?? fallbackFormatter.date(from: mr.createdAt) ?? Date()
            let updatedAt = dateFormatter.date(from: mr.updatedAt) ?? fallbackFormatter.date(from: mr.updatedAt) ?? Date()

            return PullRequest(
                id: mr.iid,
                number: mr.iid,
                title: mr.title,
                body: mr.description ?? "",
                state: state,
                author: mr.author.username,
                sourceBranch: mr.sourceBranch,
                targetBranch: mr.targetBranch,
                url: mr.webUrl,
                createdAt: createdAt,
                updatedAt: updatedAt,
                isDraft: mr.draft ?? false,
                mergeable: mergeableState,
                reviewDecision: nil,
                checksStatus: nil,
                additions: 0,
                deletions: 0,
                changedFiles: 0
            )
        }
    }

    // MARK: - PR Detail

    func getPullRequestDetail(repoPath: String, number: Int) async throws -> PullRequest {
        guard let info = await getHostingInfo(for: repoPath) else {
            throw GitHostingError.noRemoteFound
        }

        guard info.cliInstalled else {
            throw GitHostingError.cliNotInstalled(provider: info.provider)
        }

        guard info.cliAuthenticated else {
            throw GitHostingError.cliNotAuthenticated(provider: info.provider)
        }

        let (_, cliPath) = await checkCLIInstalled(for: info.provider)
        guard let path = cliPath else {
            throw GitHostingError.cliNotInstalled(provider: info.provider)
        }

        switch info.provider {
        case .github:
            return try await getGitHubPRDetail(cliPath: path, repoPath: repoPath, number: number)
        case .gitlab:
            return try await getGitLabMRDetail(cliPath: path, repoPath: repoPath, number: number)
        default:
            throw GitHostingError.unsupportedProvider
        }
    }

    private func getGitHubPRDetail(cliPath: String, repoPath: String, number: Int) async throws -> PullRequest {
        let result = try await executeCLI(cliPath, arguments: [
            "pr", "view", String(number),
            "--json", "number,title,body,state,author,headRefName,baseRefName,url,createdAt,updatedAt,isDraft,mergeable,reviewDecision,statusCheckRollup,additions,deletions,changedFiles"
        ], workingDirectory: repoPath)

        guard result.exitCode == 0 else {
            throw GitHostingError.commandFailed(message: result.stderr)
        }

        guard let data = result.stdout.data(using: .utf8) else {
            throw GitHostingError.commandFailed(message: "Empty response")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        struct GitHubPR: Decodable {
            let number: Int
            let title: String
            let body: String?
            let state: String
            let author: Author
            let headRefName: String
            let baseRefName: String
            let url: String
            let createdAt: Date
            let updatedAt: Date
            let isDraft: Bool
            let mergeable: String?
            let reviewDecision: String?
            let statusCheckRollup: [StatusCheck]?
            let additions: Int?
            let deletions: Int?
            let changedFiles: Int?

            struct Author: Decodable {
                let login: String
            }

            struct StatusCheck: Decodable {
                let conclusion: String?
                let status: String?
            }
        }

        let pr = try decoder.decode(GitHubPR.self, from: data)

        let mergeableState: PullRequest.MergeableState
        switch pr.mergeable?.uppercased() {
        case "MERGEABLE": mergeableState = .mergeable
        case "CONFLICTING": mergeableState = .conflicting
        default: mergeableState = .unknown
        }

        let reviewDecision = pr.reviewDecision.flatMap { PullRequest.ReviewDecision(rawValue: $0) }

        let checksStatus: PullRequest.ChecksStatus?
        if let checks = pr.statusCheckRollup, !checks.isEmpty {
            if checks.allSatisfy({ $0.conclusion == "SUCCESS" }) {
                checksStatus = .passing
            } else if checks.contains(where: { $0.conclusion == "FAILURE" }) {
                checksStatus = .failing
            } else {
                checksStatus = .pending
            }
        } else {
            checksStatus = nil
        }

        let state: PullRequest.State
        switch pr.state.uppercased() {
        case "MERGED": state = .merged
        case "CLOSED": state = .closed
        default: state = .open
        }

        return PullRequest(
            id: pr.number,
            number: pr.number,
            title: pr.title,
            body: pr.body ?? "",
            state: state,
            author: pr.author.login,
            sourceBranch: pr.headRefName,
            targetBranch: pr.baseRefName,
            url: pr.url,
            createdAt: pr.createdAt,
            updatedAt: pr.updatedAt,
            isDraft: pr.isDraft,
            mergeable: mergeableState,
            reviewDecision: reviewDecision,
            checksStatus: checksStatus,
            additions: pr.additions ?? 0,
            deletions: pr.deletions ?? 0,
            changedFiles: pr.changedFiles ?? 0
        )
    }

    private func getGitLabMRDetail(cliPath: String, repoPath: String, number: Int) async throws -> PullRequest {
        let result = try await executeCLI(cliPath, arguments: ["mr", "view", String(number), "--output", "json"], workingDirectory: repoPath)

        guard result.exitCode == 0 else {
            throw GitHostingError.commandFailed(message: result.stderr)
        }

        guard let data = result.stdout.data(using: .utf8) else {
            throw GitHostingError.commandFailed(message: "Empty response")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        struct GitLabMR: Decodable {
            let iid: Int
            let title: String
            let description: String?
            let state: String
            let author: Author
            let sourceBranch: String
            let targetBranch: String
            let webUrl: String
            let createdAt: String
            let updatedAt: String
            let draft: Bool?
            let mergeStatus: String?
            let changesCount: String?

            struct Author: Decodable {
                let username: String
            }
        }

        let mr = try decoder.decode(GitLabMR.self, from: data)

        let mergeableState: PullRequest.MergeableState
        switch mr.mergeStatus {
        case "can_be_merged": mergeableState = .mergeable
        case "cannot_be_merged": mergeableState = .conflicting
        default: mergeableState = .unknown
        }

        let state: PullRequest.State
        switch mr.state.lowercased() {
        case "merged": state = .merged
        case "closed": state = .closed
        default: state = .open
        }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]

        let createdAt = dateFormatter.date(from: mr.createdAt) ?? fallbackFormatter.date(from: mr.createdAt) ?? Date()
        let updatedAt = dateFormatter.date(from: mr.updatedAt) ?? fallbackFormatter.date(from: mr.updatedAt) ?? Date()

        return PullRequest(
            id: mr.iid,
            number: mr.iid,
            title: mr.title,
            body: mr.description ?? "",
            state: state,
            author: mr.author.username,
            sourceBranch: mr.sourceBranch,
            targetBranch: mr.targetBranch,
            url: mr.webUrl,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isDraft: mr.draft ?? false,
            mergeable: mergeableState,
            reviewDecision: nil,
            checksStatus: nil,
            additions: 0,
            deletions: 0,
            changedFiles: Int(mr.changesCount ?? "0") ?? 0
        )
    }

    // MARK: - PR Comments

    func getPullRequestComments(repoPath: String, number: Int) async throws -> [PRComment] {
        guard let info = await getHostingInfo(for: repoPath) else {
            throw GitHostingError.noRemoteFound
        }

        guard info.cliInstalled && info.cliAuthenticated else {
            return []
        }

        let (_, cliPath) = await checkCLIInstalled(for: info.provider)
        guard let path = cliPath else {
            return []
        }

        switch info.provider {
        case .github:
            return try await getGitHubPRComments(cliPath: path, repoPath: repoPath, number: number)
        case .gitlab:
            return try await getGitLabMRComments(cliPath: path, repoPath: repoPath, number: number)
        default:
            return []
        }
    }

    private func getGitHubPRComments(cliPath: String, repoPath: String, number: Int) async throws -> [PRComment] {
        let result = try await executeCLI(cliPath, arguments: [
            "pr", "view", String(number),
            "--json", "comments,reviews"
        ], workingDirectory: repoPath)

        guard result.exitCode == 0 else {
            return []
        }

        guard let data = result.stdout.data(using: .utf8) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        struct PRData: Decodable {
            let comments: [Comment]?
            let reviews: [Review]?

            struct Comment: Decodable {
                let id: String
                let author: Author
                let body: String
                let createdAt: Date

                struct Author: Decodable {
                    let login: String
                    let avatarUrl: String?
                }
            }

            struct Review: Decodable {
                let id: String
                let author: Author
                let body: String?
                let state: String
                let submittedAt: Date?

                struct Author: Decodable {
                    let login: String
                    let avatarUrl: String?
                }
            }
        }

        let prData = try decoder.decode(PRData.self, from: data)

        var comments: [PRComment] = []

        // Add regular comments
        if let prComments = prData.comments {
            for comment in prComments {
                comments.append(PRComment(
                    id: comment.id,
                    author: comment.author.login,
                    avatarURL: comment.author.avatarUrl,
                    body: comment.body,
                    createdAt: comment.createdAt,
                    isReview: false,
                    reviewState: nil,
                    path: nil,
                    line: nil
                ))
            }
        }

        // Add reviews
        if let reviews = prData.reviews {
            for review in reviews {
                if let body = review.body, !body.isEmpty {
                    comments.append(PRComment(
                        id: review.id,
                        author: review.author.login,
                        avatarURL: review.author.avatarUrl,
                        body: body,
                        createdAt: review.submittedAt ?? Date(),
                        isReview: true,
                        reviewState: PRComment.ReviewState(rawValue: review.state),
                        path: nil,
                        line: nil
                    ))
                }
            }
        }

        return comments.sorted { $0.createdAt < $1.createdAt }
    }

    private func getGitLabMRComments(cliPath: String, repoPath: String, number: Int) async throws -> [PRComment] {
        // Use mr view --comments to get notes (glab doesn't have "mr note list")
        let result = try await executeCLI(cliPath, arguments: ["mr", "view", String(number), "--comments", "--output", "json"], workingDirectory: repoPath)

        guard result.exitCode == 0 else {
            return []
        }

        guard let data = result.stdout.data(using: .utf8) else {
            return []
        }

        // Notes are in the "Notes" array of the MR JSON
        struct MRWithNotes: Decodable {
            let Notes: [Note]?

            struct Note: Decodable {
                let id: Int
                let author: Author
                let body: String
                let created_at: String
                let system: Bool?

                struct Author: Decodable {
                    let username: String
                    let avatar_url: String?
                }
            }
        }

        let decoder = JSONDecoder()
        let mrData = try decoder.decode(MRWithNotes.self, from: data)

        guard let notes = mrData.Notes else {
            return []
        }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]

        return notes
            .filter { !($0.system ?? false) }
            .map { note in
                let createdAt = dateFormatter.date(from: note.created_at) ?? fallbackFormatter.date(from: note.created_at) ?? Date()
                return PRComment(
                    id: String(note.id),
                    author: note.author.username,
                    avatarURL: note.author.avatar_url,
                    body: note.body,
                    createdAt: createdAt,
                    isReview: false,
                    reviewState: nil,
                    path: nil,
                    line: nil
                )
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - PR Diff

    func getPullRequestDiff(repoPath: String, number: Int) async throws -> String {
        guard let info = await getHostingInfo(for: repoPath) else {
            throw GitHostingError.noRemoteFound
        }

        guard info.cliInstalled && info.cliAuthenticated else {
            throw GitHostingError.cliNotAuthenticated(provider: info.provider)
        }

        let (_, cliPath) = await checkCLIInstalled(for: info.provider)
        guard let path = cliPath else {
            throw GitHostingError.cliNotInstalled(provider: info.provider)
        }

        switch info.provider {
        case .github:
            let result = try await executeCLI(path, arguments: ["pr", "diff", String(number)], workingDirectory: repoPath)
            guard result.exitCode == 0 else {
                throw GitHostingError.commandFailed(message: result.stderr)
            }
            return result.stdout

        case .gitlab:
            let result = try await executeCLI(path, arguments: ["mr", "diff", String(number)], workingDirectory: repoPath)
            guard result.exitCode == 0 else {
                throw GitHostingError.commandFailed(message: result.stderr)
            }
            return result.stdout

        default:
            throw GitHostingError.unsupportedProvider
        }
    }

    // MARK: - PR Actions

    func closePullRequest(repoPath: String, number: Int) async throws {
        guard let info = await getHostingInfo(for: repoPath) else {
            throw GitHostingError.noRemoteFound
        }

        guard info.cliInstalled && info.cliAuthenticated else {
            throw GitHostingError.cliNotAuthenticated(provider: info.provider)
        }

        let (_, cliPath) = await checkCLIInstalled(for: info.provider)
        guard let path = cliPath else {
            throw GitHostingError.cliNotInstalled(provider: info.provider)
        }

        switch info.provider {
        case .github:
            let result = try await executeCLI(path, arguments: ["pr", "close", String(number)], workingDirectory: repoPath)
            guard result.exitCode == 0 else {
                throw GitHostingError.commandFailed(message: result.stderr)
            }

        case .gitlab:
            let result = try await executeCLI(path, arguments: ["mr", "close", String(number)], workingDirectory: repoPath)
            guard result.exitCode == 0 else {
                throw GitHostingError.commandFailed(message: result.stderr)
            }

        default:
            throw GitHostingError.unsupportedProvider
        }
    }

    func mergePullRequestWithMethod(repoPath: String, number: Int, method: PRMergeMethod) async throws {
        guard let info = await getHostingInfo(for: repoPath) else {
            throw GitHostingError.noRemoteFound
        }

        guard info.cliInstalled && info.cliAuthenticated else {
            throw GitHostingError.cliNotAuthenticated(provider: info.provider)
        }

        let (_, cliPath) = await checkCLIInstalled(for: info.provider)
        guard let path = cliPath else {
            throw GitHostingError.cliNotInstalled(provider: info.provider)
        }

        switch info.provider {
        case .github:
            let result = try await executeCLI(path, arguments: ["pr", "merge", String(number), method.ghFlag], workingDirectory: repoPath)
            guard result.exitCode == 0 else {
                throw GitHostingError.commandFailed(message: result.stderr)
            }

        case .gitlab:
            var arguments = ["mr", "merge", String(number)]
            if method == .squash {
                arguments.append("--squash")
            }
            let result = try await executeCLI(path, arguments: arguments, workingDirectory: repoPath)
            guard result.exitCode == 0 else {
                throw GitHostingError.commandFailed(message: result.stderr)
            }

        default:
            throw GitHostingError.unsupportedProvider
        }
    }

    func approvePullRequest(repoPath: String, number: Int, body: String? = nil) async throws {
        guard let info = await getHostingInfo(for: repoPath) else {
            throw GitHostingError.noRemoteFound
        }

        guard info.cliInstalled && info.cliAuthenticated else {
            throw GitHostingError.cliNotAuthenticated(provider: info.provider)
        }

        let (_, cliPath) = await checkCLIInstalled(for: info.provider)
        guard let path = cliPath else {
            throw GitHostingError.cliNotInstalled(provider: info.provider)
        }

        switch info.provider {
        case .github:
            var arguments = ["pr", "review", String(number), "--approve"]
            if let body = body, !body.isEmpty {
                arguments += ["--body", body]
            }
            let result = try await executeCLI(path, arguments: arguments, workingDirectory: repoPath)
            guard result.exitCode == 0 else {
                throw GitHostingError.commandFailed(message: result.stderr)
            }

        case .gitlab:
            let result = try await executeCLI(path, arguments: ["mr", "approve", String(number)], workingDirectory: repoPath)
            guard result.exitCode == 0 else {
                throw GitHostingError.commandFailed(message: result.stderr)
            }

        default:
            throw GitHostingError.unsupportedProvider
        }
    }

    func requestChanges(repoPath: String, number: Int, body: String) async throws {
        guard let info = await getHostingInfo(for: repoPath) else {
            throw GitHostingError.noRemoteFound
        }

        guard info.cliInstalled && info.cliAuthenticated else {
            throw GitHostingError.cliNotAuthenticated(provider: info.provider)
        }

        let (_, cliPath) = await checkCLIInstalled(for: info.provider)
        guard let path = cliPath else {
            throw GitHostingError.cliNotInstalled(provider: info.provider)
        }

        switch info.provider {
        case .github:
            let result = try await executeCLI(path, arguments: ["pr", "review", String(number), "--request-changes", "--body", body], workingDirectory: repoPath)
            guard result.exitCode == 0 else {
                throw GitHostingError.commandFailed(message: result.stderr)
            }

        case .gitlab:
            // GitLab doesn't have direct request-changes, add a comment instead
            let result = try await executeCLI(path, arguments: ["mr", "note", String(number), "--message", body], workingDirectory: repoPath)
            guard result.exitCode == 0 else {
                throw GitHostingError.commandFailed(message: result.stderr)
            }

        default:
            throw GitHostingError.unsupportedProvider
        }
    }

    func addPullRequestComment(repoPath: String, number: Int, body: String) async throws {
        guard let info = await getHostingInfo(for: repoPath) else {
            throw GitHostingError.noRemoteFound
        }

        guard info.cliInstalled && info.cliAuthenticated else {
            throw GitHostingError.cliNotAuthenticated(provider: info.provider)
        }

        let (_, cliPath) = await checkCLIInstalled(for: info.provider)
        guard let path = cliPath else {
            throw GitHostingError.cliNotInstalled(provider: info.provider)
        }

        switch info.provider {
        case .github:
            let result = try await executeCLI(path, arguments: ["pr", "comment", String(number), "--body", body], workingDirectory: repoPath)
            guard result.exitCode == 0 else {
                throw GitHostingError.commandFailed(message: result.stderr)
            }

        case .gitlab:
            let result = try await executeCLI(path, arguments: ["mr", "note", String(number), "--message", body], workingDirectory: repoPath)
            guard result.exitCode == 0 else {
                throw GitHostingError.commandFailed(message: result.stderr)
            }

        default:
            throw GitHostingError.unsupportedProvider
        }
    }

    // MARK: - Browser Fallback

    func openInBrowser(info: GitHostingInfo, action: GitHostingAction) {
        guard let url = buildURL(info: info, action: action) else {
            logger.error("Failed to build URL for action")
            return
        }

        NSWorkspace.shared.open(url)
    }

    nonisolated func buildURL(info: GitHostingInfo, action: GitHostingAction) -> URL? {
        switch action {
        case .createPR(let sourceBranch, let targetBranch):
            return buildCreatePRURL(info: info, sourceBranch: sourceBranch, targetBranch: targetBranch)
        case .viewPR(let number):
            return buildViewPRURL(info: info, number: number)
        case .viewRepo:
            return buildRepoURL(info: info)
        }
    }

    private nonisolated func buildCreatePRURL(info: GitHostingInfo, sourceBranch: String, targetBranch: String?) -> URL? {
        let target = targetBranch ?? "main"
        let encodedSource = sourceBranch.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? sourceBranch
        let encodedTarget = target.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? target

        switch info.provider {
        case .github:
            return URL(string: "\(info.baseURL)/\(info.owner)/\(info.repo)/compare/\(encodedTarget)...\(encodedSource)?expand=1")

        case .gitlab:
            return URL(string: "\(info.baseURL)/\(info.owner)/\(info.repo)/-/merge_requests/new?merge_request[source_branch]=\(encodedSource)&merge_request[target_branch]=\(encodedTarget)")

        case .bitbucket:
            return URL(string: "\(info.baseURL)/\(info.owner)/\(info.repo)/pull-requests/new?source=\(encodedSource)&dest=\(encodedTarget)")

        case .azureDevOps:
            return URL(string: "\(info.baseURL)/\(info.owner)/_git/\(info.repo)/pullrequestcreate?sourceRef=\(encodedSource)&targetRef=\(encodedTarget)")

        case .unknown:
            return nil
        }
    }

    private nonisolated func buildViewPRURL(info: GitHostingInfo, number: Int) -> URL? {
        switch info.provider {
        case .github:
            return URL(string: "\(info.baseURL)/\(info.owner)/\(info.repo)/pull/\(number)")
        case .gitlab:
            return URL(string: "\(info.baseURL)/\(info.owner)/\(info.repo)/-/merge_requests/\(number)")
        case .bitbucket:
            return URL(string: "\(info.baseURL)/\(info.owner)/\(info.repo)/pull-requests/\(number)")
        case .azureDevOps:
            return URL(string: "\(info.baseURL)/\(info.owner)/_git/\(info.repo)/pullrequest/\(number)")
        case .unknown:
            return nil
        }
    }

    private nonisolated func buildRepoURL(info: GitHostingInfo) -> URL? {
        switch info.provider {
        case .github:
            return URL(string: "\(info.baseURL)/\(info.owner)/\(info.repo)")
        case .gitlab:
            return URL(string: "\(info.baseURL)/\(info.owner)/\(info.repo)")
        case .bitbucket:
            return URL(string: "\(info.baseURL)/\(info.owner)/\(info.repo)")
        case .azureDevOps:
            return URL(string: "\(info.baseURL)/\(info.owner)/_git/\(info.repo)")
        case .unknown:
            return nil
        }
    }
}
