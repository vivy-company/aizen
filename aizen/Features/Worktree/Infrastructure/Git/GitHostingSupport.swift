//
//  GitHostingSupport.swift
//  aizen
//
//  Pure helpers and value types for git hosting provider detection and URL building.
//

import Foundation

enum GitHostingProvider: String, Sendable {
    case github
    case gitlab
    case bitbucket
    case azureDevOps
    case unknown

    nonisolated var displayName: String {
        switch self {
        case .github: return "GitHub"
        case .gitlab: return "GitLab"
        case .bitbucket: return "Bitbucket"
        case .azureDevOps: return "Azure DevOps"
        case .unknown: return "Unknown"
        }
    }

    nonisolated var cliName: String? {
        switch self {
        case .github: return "gh"
        case .gitlab: return "glab"
        case .azureDevOps: return "az"
        case .bitbucket, .unknown: return nil
        }
    }

    nonisolated var prTerminology: String {
        switch self {
        case .gitlab: return "Merge Request"
        default: return "Pull Request"
        }
    }

    nonisolated var installInstructions: String {
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

    nonisolated var errorDescription: String? {
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
            return "No remote project found"
        }
    }
}

enum GitHostingRemoteSupport {
    nonisolated static func detectProvider(from remoteURL: String) -> GitHostingProvider {
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

    nonisolated static func parseOwnerRepo(from remoteURL: String) -> (owner: String, repo: String)? {
        if remoteURL.contains("@") && remoteURL.contains(":") {
            let parts = remoteURL.components(separatedBy: ":")
            guard parts.count >= 2 else { return nil }
            return parsePathComponents(parts[1])
        }

        guard let url = URL(string: remoteURL) else { return nil }
        return parsePathComponents(url.path)
    }

    nonisolated static func parseISO8601Date(_ value: String) -> Date {
        ISO8601DateParser.shared.parse(value) ?? Date()
    }

    nonisolated static func extractBaseURL(from remoteURL: String, provider: GitHostingProvider) -> String {
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

    nonisolated private static func parsePathComponents(_ path: String) -> (owner: String, repo: String)? {
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
}

enum GitHostingURLBuilder {
    nonisolated static func buildURL(info: GitHostingInfo, action: GitHostingAction) -> URL? {
        switch action {
        case .createPR(let sourceBranch, let targetBranch):
            return buildCreatePRURL(info: info, sourceBranch: sourceBranch, targetBranch: targetBranch)
        case .viewPR(let number):
            return buildViewPRURL(info: info, number: number)
        case .viewRepo:
            return buildRepoURL(info: info)
        }
    }

    nonisolated static func buildCreatePRURL(info: GitHostingInfo, sourceBranch: String, targetBranch: String?) -> URL? {
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

    nonisolated static func buildViewPRURL(info: GitHostingInfo, number: Int) -> URL? {
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

    nonisolated static func buildRepoURL(info: GitHostingInfo) -> URL? {
        switch info.provider {
        case .github, .gitlab, .bitbucket:
            return URL(string: "\(info.baseURL)/\(info.owner)/\(info.repo)")
        case .azureDevOps:
            return URL(string: "\(info.baseURL)/\(info.owner)/_git/\(info.repo)")
        case .unknown:
            return nil
        }
    }
}
