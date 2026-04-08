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
