import Foundation

extension GitHostingService {
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
}
