import Foundation

extension GitHostingService {
    func listGitHubPRs(
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

        let prs = try decoder.decode([GitHubPRPayload].self, from: data)
        let startIndex = (max(page, 1) - 1) * normalizedLimit
        let pageItems = prs.dropFirst(startIndex).prefix(normalizedLimit)

        return pageItems.map { mapGitHubPR($0) }
    }

    func getGitHubPRDetail(cliPath: String, repoPath: String, number: Int) async throws -> PullRequest {
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

        let pr = try decoder.decode(GitHubPRPayload.self, from: data)
        return mapGitHubPR(pr)
    }

    private func mapGitHubPR(_ pr: GitHubPRPayload) -> PullRequest {
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

nonisolated private struct GitHubPRPayload: Decodable {
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
