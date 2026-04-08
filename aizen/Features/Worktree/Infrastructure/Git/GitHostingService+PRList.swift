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

}
