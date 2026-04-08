import Foundation

extension GitHostingService {
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

    // MARK: - PR Checkout

    func checkoutPullRequest(repoPath: String, number: Int) async throws {
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

        let arguments: [String]
        switch info.provider {
        case .github:
            arguments = ["pr", "checkout", String(number)]
        case .gitlab:
            arguments = ["mr", "checkout", String(number)]
        default:
            throw GitHostingError.unsupportedProvider
        }

        let result = try await executeCLI(path, arguments: arguments, workingDirectory: repoPath)
        guard result.exitCode == 0 else {
            throw GitHostingError.commandFailed(message: result.stderr)
        }
    }

}
