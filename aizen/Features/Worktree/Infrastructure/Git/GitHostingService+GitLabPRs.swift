import Foundation

extension GitHostingService {
    func listGitLabMRs(
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

    func getGitLabMRDetail(cliPath: String, repoPath: String, number: Int) async throws -> PullRequest {
        let result = try await executeCLI(
            cliPath,
            arguments: ["mr", "view", String(number), "--output", "json"],
            workingDirectory: repoPath
        )

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

            struct Author: Decodable { let username: String }
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
            changedFiles: Int(mr.changesCount ?? "0") ?? 0
        )
    }
}
