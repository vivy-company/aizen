//
//  WorkflowDetector.swift
//  aizen
//
//  Auto-detects CI/CD provider from repository remotes and files
//

import Foundation
import os.log

actor WorkflowDetector {
    static let shared = WorkflowDetector()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "WorkflowDetector")

    // Cache detection results
    private var cache: [String: WorkflowProvider] = [:]

    func detect(repoPath: String) async -> WorkflowProvider {
        // Check cache first
        if let cached = cache[repoPath] {
            return cached
        }

        let provider = await performDetection(repoPath: repoPath)
        cache[repoPath] = provider
        return provider
    }

    func clearCache(for repoPath: String? = nil) {
        if let path = repoPath {
            cache.removeValue(forKey: path)
        } else {
            cache.removeAll()
        }
    }

    private func performDetection(repoPath: String) async -> WorkflowProvider {
        // 1. Check remote URLs first (most reliable)
        if let remoteProvider = await detectFromRemotes(repoPath: repoPath) {
            logger.info("Detected \(remoteProvider.rawValue) from remote URLs")
            return remoteProvider
        }

        // 2. Fallback: check for workflow/CI files
        if let fileProvider = detectFromFiles(repoPath: repoPath) {
            logger.info("Detected \(fileProvider.rawValue) from CI files")
            return fileProvider
        }

        logger.info("No CI/CD provider detected")
        return .none
    }

    private func detectFromRemotes(repoPath: String) async -> WorkflowProvider? {
        do {
            let result = try await ProcessExecutor.shared.executeWithOutput(
                executable: "/usr/bin/git",
                arguments: ["remote", "-v"],
                workingDirectory: repoPath
            )

            let output = result.stdout.lowercased()

            // Check for GitHub
            if output.contains("github.com") {
                return .github
            }

            // Check for GitLab (including self-hosted)
            if output.contains("gitlab.com") || output.contains("gitlab") {
                return .gitlab
            }

            // Try to detect self-hosted GitLab by checking API
            let remotes = parseRemoteURLs(output)
            for remote in remotes {
                if await isGitLabInstance(url: remote) {
                    return .gitlab
                }
            }

            return nil
        } catch {
            logger.error("Failed to get remotes: \(error.localizedDescription)")
            return nil
        }
    }

    private func parseRemoteURLs(_ output: String) -> [String] {
        var urls: Set<String> = []

        for line in output.components(separatedBy: .newlines) {
            let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 2 else { continue }

            var url = parts[1]

            // Convert SSH to HTTPS for API check
            if url.hasPrefix("git@") {
                // git@github.com:user/repo.git -> https://github.com
                let withoutGit = url.replacingOccurrences(of: "git@", with: "")
                if let colonIndex = withoutGit.firstIndex(of: ":") {
                    let host = String(withoutGit[..<colonIndex])
                    url = "https://\(host)"
                }
            } else if url.hasPrefix("https://") || url.hasPrefix("http://") {
                // Extract just the host
                if let urlObj = URL(string: url), let host = urlObj.host {
                    url = "https://\(host)"
                }
            }

            urls.insert(url)
        }

        return Array(urls)
    }

    private func isGitLabInstance(url: String) async -> Bool {
        // Try to hit GitLab API endpoint
        guard let apiURL = URL(string: "\(url)/api/v4/version") else { return false }

        var request = URLRequest(url: apiURL)
        request.timeoutInterval = 5

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                // GitLab returns 200 or 401 (unauthorized but endpoint exists)
                return httpResponse.statusCode == 200 || httpResponse.statusCode == 401
            }
            return false
        } catch {
            return false
        }
    }

    private func detectFromFiles(repoPath: String) -> WorkflowProvider? {
        let fileManager = FileManager.default

        // Check for GitHub Actions
        let githubWorkflowsPath = (repoPath as NSString).appendingPathComponent(".github/workflows")
        if fileManager.fileExists(atPath: githubWorkflowsPath) {
            // Verify there's at least one workflow file
            if let contents = try? fileManager.contentsOfDirectory(atPath: githubWorkflowsPath),
               contents.contains(where: { $0.hasSuffix(".yml") || $0.hasSuffix(".yaml") }) {
                return .github
            }
        }

        // Check for GitLab CI
        let gitlabCIPath = (repoPath as NSString).appendingPathComponent(".gitlab-ci.yml")
        if fileManager.fileExists(atPath: gitlabCIPath) {
            return .gitlab
        }

        return nil
    }

    // MARK: - CLI Availability

    func checkCLIAvailability() async -> CLIAvailability {
        async let ghAvailable = checkCommandExists("gh")
        async let glabAvailable = checkCommandExists("glab")
        async let ghAuth = checkGHAuth()
        async let glabAuth = checkGLabAuth()

        return await CLIAvailability(
            gh: ghAvailable,
            glab: glabAvailable,
            ghAuthenticated: ghAuth,
            glabAuthenticated: glabAuth
        )
    }

    private func checkCommandExists(_ command: String) async -> Bool {
        let env = ShellEnvironment.loadUserShellEnvironment()

        do {
            let result = try await ProcessExecutor.shared.executeWithOutput(
                executable: "/usr/bin/which",
                arguments: [command],
                environment: env,
                workingDirectory: FileManager.default.currentDirectoryPath
            )
            return result.exitCode == 0
        } catch {
            return false
        }
    }

    private func checkGHAuth() async -> Bool {
        let provider = await MainActor.run { GitHubWorkflowProvider() }
        return await provider.checkAuthentication()
    }

    private func checkGLabAuth() async -> Bool {
        let provider = await MainActor.run { GitLabWorkflowProvider() }
        return await provider.checkAuthentication()
    }
}
