//
//  GitHubWorkflowProvider.swift
//  aizen
//
//  GitHub Actions workflow provider using gh CLI
//

import Foundation
import os.log

actor GitHubWorkflowProvider: WorkflowProviderProtocol {
    nonisolated let provider: WorkflowProvider = .github

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "GitHubWorkflow")
    private let ghPath: String

    init() {
        // Find gh binary
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/gh") {
            self.ghPath = "/opt/homebrew/bin/gh"
        } else if FileManager.default.fileExists(atPath: "/usr/local/bin/gh") {
            self.ghPath = "/usr/local/bin/gh"
        } else {
            self.ghPath = "gh"  // Rely on PATH
        }
    }

    // MARK: - Workflows

    // MARK: - Runs

    // MARK: - Actions

    // MARK: - Logs

    func getRunLogs(repoPath: String, runId: String, jobId: String?) async throws -> String {
        var args = ["run", "view", runId, "--log"]
        if let jobId = jobId {
            args.append(contentsOf: ["--job", jobId])
        }

        let result = try await executeGH(args, workingDirectory: repoPath)
        return result.stdout
    }

    nonisolated static let timestampRegex = try? NSRegularExpression(pattern: #"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})"#)

    // MARK: - Auth

    func checkAuthentication() async -> Bool {
        do {
            let env = ShellEnvironment.loadUserShellEnvironment()
            let result = try await ProcessExecutor.shared.executeWithOutput(
                executable: ghPath,
                arguments: ["auth", "status"],
                environment: env,
                workingDirectory: FileManager.default.currentDirectoryPath
            )
            return result.exitCode == 0
        } catch {
            return false
        }
    }

    // MARK: - Private Helpers

    func executeGH(_ arguments: [String], workingDirectory: String) async throws -> ProcessResult {
        logger.debug("Executing: gh \(arguments.joined(separator: " "))")

        let env = ShellEnvironment.loadUserShellEnvironment()
        let result = try await ProcessExecutor.shared.executeWithOutput(
            executable: ghPath,
            arguments: arguments,
            environment: env,
            workingDirectory: workingDirectory
        )

        if result.exitCode != 0 {
            logger.error("gh command failed: \(result.stderr)")
            throw WorkflowError.executionFailed(result.stderr)
        }

        return result
    }

    func parseRunStatus(_ status: String) -> RunStatus {
        switch status.lowercased() {
        case "queued": return .queued
        case "in_progress": return .inProgress
        case "completed": return .completed
        case "pending": return .pending
        case "waiting": return .waiting
        case "requested": return .requested
        default: return .completed
        }
    }

    func parseConclusion(_ conclusion: String) -> RunConclusion? {
        switch conclusion.lowercased() {
        case "success": return .success
        case "failure": return .failure
        case "cancelled": return .cancelled
        case "skipped": return .skipped
        case "timed_out": return .timedOut
        case "action_required": return .actionRequired
        case "neutral": return .neutral
        default: return nil
        }
    }
}
