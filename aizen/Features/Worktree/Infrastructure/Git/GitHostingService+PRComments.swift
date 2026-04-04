import Foundation

extension GitHostingService {
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
}
