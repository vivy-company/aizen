import Foundation
import os

extension GitHostingService {
    // MARK: - PR Status

    func getPRStatus(repoPath: String, branch: String) async -> PRStatus {
        guard let info = await getHostingInfo(for: repoPath) else {
            return .unknown
        }

        guard info.cliInstalled && info.cliAuthenticated else {
            return .unknown
        }

        let (_, cliPath) = await checkCLIInstalled(for: info.provider)
        guard let path = cliPath else { return .unknown }

        do {
            switch info.provider {
            case .github:
                return try await getGitHubPRStatus(cliPath: path, repoPath: repoPath, branch: branch)
            case .gitlab:
                return try await getGitLabMRStatus(cliPath: path, repoPath: repoPath, branch: branch)
            default:
                return .unknown
            }
        } catch {
            logger.error("Failed to get PR status: \(error.localizedDescription)")
            return .unknown
        }
    }

    private func getGitHubPRStatus(cliPath: String, repoPath: String, branch: String) async throws -> PRStatus {
        let result = try await executeCLI(
            cliPath,
            arguments: ["pr", "view", "--json", "number,url,state,mergeable,title", "--head", branch],
            workingDirectory: repoPath
        )

        if result.exitCode != 0 {
            if result.stderr.contains("no pull requests found") || result.stderr.contains("Could not resolve") {
                return .noPR
            }
            return .unknown
        }

        guard let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .unknown
        }

        let state = json["state"] as? String ?? ""
        let number = json["number"] as? Int ?? 0
        let url = json["url"] as? String ?? ""
        let mergeable = json["mergeable"] as? String ?? ""
        let title = json["title"] as? String ?? ""

        switch state.uppercased() {
        case "OPEN":
            return .open(number: number, url: url, mergeable: mergeable == "MERGEABLE", title: title)
        case "MERGED":
            return .merged
        case "CLOSED":
            return .closed
        default:
            return .unknown
        }
    }

    private func getGitLabMRStatus(cliPath: String, repoPath: String, branch: String) async throws -> PRStatus {
        let result = try await executeCLI(
            cliPath,
            arguments: ["mr", "view", "--output", "json", branch],
            workingDirectory: repoPath
        )

        if result.exitCode != 0 {
            if result.stderr.contains("no merge request") || result.stderr.contains("not found") {
                return .noPR
            }
            return .unknown
        }

        guard let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .unknown
        }

        let state = json["state"] as? String ?? ""
        let iid = json["iid"] as? Int ?? 0
        let webUrl = json["web_url"] as? String ?? ""
        let mergeStatus = json["merge_status"] as? String ?? ""
        let title = json["title"] as? String ?? ""

        switch state.lowercased() {
        case "opened":
            return .open(number: iid, url: webUrl, mergeable: mergeStatus == "can_be_merged", title: title)
        case "merged":
            return .merged
        case "closed":
            return .closed
        default:
            return .unknown
        }
    }
}
