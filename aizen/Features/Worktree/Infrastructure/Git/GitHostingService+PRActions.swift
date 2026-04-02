import AppKit
import Foundation
import os

extension GitHostingService {
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
        let result = try await executeCLI(
            cliPath,
            arguments: ["pr", "view", String(number), "--json", "comments,reviews"],
            workingDirectory: repoPath
        )

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
        let result = try await executeCLI(
            cliPath,
            arguments: ["mr", "view", String(number), "--comments", "--output", "json"],
            workingDirectory: repoPath
        )

        guard result.exitCode == 0 else {
            return []
        }

        guard let data = result.stdout.data(using: .utf8) else {
            return []
        }

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

        return notes
            .filter { !($0.system ?? false) }
            .map { note in
                let createdAt = GitHostingRemoteSupport.parseISO8601Date(note.created_at)
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
            let result = try await executeCLI(
                path,
                arguments: ["pr", "review", String(number), "--request-changes", "--body", body],
                workingDirectory: repoPath
            )
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
        guard let url = GitHostingURLBuilder.buildURL(info: info, action: action) else {
            logger.error("Failed to build URL for action")
            return
        }

        NSWorkspace.shared.open(url)
    }

    nonisolated func buildURL(info: GitHostingInfo, action: GitHostingAction) -> URL? {
        GitHostingURLBuilder.buildURL(info: info, action: action)
    }
}
