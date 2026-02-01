//
//  GitHubReleaseInstaller.swift
//  aizen
//
//  GitHub release API integration for agent installation
//

import Foundation

actor GitHubReleaseInstaller {
    static let shared = GitHubReleaseInstaller()

    private let urlSession: URLSession
    private let binaryInstaller: BinaryAgentInstaller

    init(urlSession: URLSession = .shared, binaryInstaller: BinaryAgentInstaller = .shared) {
        self.urlSession = urlSession
        self.binaryInstaller = binaryInstaller
    }

    // MARK: - Installation

    func install(repo: String, assetPattern: String, agentId: String, targetDir: String) async throws {
        // Fetch latest release info from GitHub API
        guard let apiURL = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            throw AgentInstallError.invalidResponse
        }

        var request = URLRequest(url: apiURL, timeoutInterval: 30)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await urlSession.data(for: request)

        // Validate HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AgentInstallError.downloadFailed(message: "Invalid response from GitHub API")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = formatHTTPError(statusCode: httpResponse.statusCode, repo: repo)
            throw AgentInstallError.downloadFailed(message: errorMessage)
        }

        // Parse JSON to get tag_name
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String else {
            throw AgentInstallError.invalidResponse
        }

        // Build download URL by replacing placeholders
        let downloadURL = buildDownloadURL(
            repo: repo,
            tagName: tagName,
            assetPattern: assetPattern
        )

        // Use binary installer for the actual download
        try await binaryInstaller.install(
            from: downloadURL,
            agentId: agentId,
            targetDir: targetDir
        )

        // Save installed version to manifest (strip 'v' prefix if present)
        let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        saveVersionManifest(version: version, targetDir: targetDir)
    }

    // MARK: - Version Detection

    /// Get latest release version from GitHub API
    func getLatestVersion(repo: String) async -> String? {
        guard let apiURL = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            return nil
        }

        var request = URLRequest(url: apiURL, timeoutInterval: 30)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tagName = json["tag_name"] as? String {
                // Remove 'v' prefix if present
                return tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            }
        } catch {
        }

        return nil
    }

    /// Save version to manifest file for quick lookup
    private func saveVersionManifest(version: String, targetDir: String) {
        let manifestPath = (targetDir as NSString).appendingPathComponent(".version")
        try? version.write(toFile: manifestPath, atomically: true, encoding: .utf8)
    }

    // MARK: - Helpers

    private func formatHTTPError(statusCode: Int, repo: String) -> String {
        switch statusCode {
        case 403, 429:
            return "GitHub API rate limit exceeded. Please try again later."
        case 404:
            return "Release not found for \(repo)"
        default:
            return "GitHub API returned status \(statusCode)"
        }
    }

    private func buildDownloadURL(repo: String, tagName: String, assetPattern: String) -> String {
        var url = "https://github.com/\(repo)/releases/download/\(tagName)/" + assetPattern
        url = url.replacingOccurrences(of: "{version}", with: tagName)

        // Handle architecture placeholders
        #if arch(arm64)
        let standardArch = "aarch64"
        let shortArch = "arm64"
        #elseif arch(x86_64)
        let standardArch = "x86_64"
        let shortArch = "x64"
        #else
        let standardArch = "unknown"
        let shortArch = "unknown"
        #endif

        url = url.replacingOccurrences(of: "{arch}", with: standardArch)
        url = url.replacingOccurrences(of: "{short-arch}", with: shortArch)

        return url
    }
}
