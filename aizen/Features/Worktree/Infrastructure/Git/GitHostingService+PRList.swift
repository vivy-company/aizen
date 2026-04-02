import Foundation

extension GitHostingService {
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

            struct Author: Decodable { let login: String }
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

        switch filter {
        case .all:
            arguments.append("-A")
        case .closed:
            arguments.append("-c")
        case .merged:
            arguments.append("-M")
        case .open:
            break
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

            struct Author: Decodable { let username: String }
        }

        let mrs = try decoder.decode([GitLabMR].self, from: data)

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

            let createdAt = GitHostingRemoteSupport.parseISO8601Date(mr.createdAt)
            let updatedAt = GitHostingRemoteSupport.parseISO8601Date(mr.updatedAt)

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
}
