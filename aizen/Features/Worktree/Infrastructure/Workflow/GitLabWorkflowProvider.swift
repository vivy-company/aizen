//
//  GitLabWorkflowProvider.swift
//  aizen
//
//  GitLab CI workflow provider using glab CLI
//

import Foundation
import os.log

actor GitLabWorkflowProvider: WorkflowProviderProtocol {
    nonisolated let provider: WorkflowProvider = .gitlab

    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "GitLabWorkflow")
    private let glabPath: String

    init() {
        // Find glab binary
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/glab") {
            self.glabPath = "/opt/homebrew/bin/glab"
        } else if FileManager.default.fileExists(atPath: "/usr/local/bin/glab") {
            self.glabPath = "/usr/local/bin/glab"
        } else {
            self.glabPath = "glab"  // Rely on PATH
        }
    }

    // MARK: - Workflows

    func listWorkflows(repoPath: String) async throws -> [Workflow] {
        // GitLab doesn't have multiple workflows like GitHub
        // Check if .gitlab-ci.yml exists
        let ciPath = (repoPath as NSString).appendingPathComponent(".gitlab-ci.yml")

        if FileManager.default.fileExists(atPath: ciPath) {
            return [
                Workflow(
                    id: "gitlab-ci",
                    name: "GitLab CI",
                    path: ".gitlab-ci.yml",
                    state: .active,
                    provider: .gitlab,
                    supportsManualTrigger: true  // GitLab pipelines can always be triggered manually
                )
            ]
        }
        return []
    }

    func getWorkflowInputs(repoPath: String, workflow: Workflow) async throws -> [WorkflowInput] {
        // GitLab uses variables which can be specified at runtime
        // Parse .gitlab-ci.yml for variables with defaults
        let ciPath = (repoPath as NSString).appendingPathComponent(".gitlab-ci.yml")

        guard let content = try? String(contentsOfFile: ciPath, encoding: .utf8) else {
            return []
        }

        return GitLabWorkflowVariableParser.parse(yaml: content)
    }

    // MARK: - Actions

    func triggerWorkflow(repoPath: String, workflow: Workflow, branch: String, inputs: [String: String]) async throws -> WorkflowRun? {
        var args = ["ci", "run", "-b", branch]

        for (key, value) in inputs {
            args.append(contentsOf: ["--variables", "\(key):\(value)"])
        }

        let result = try await executeGLab(args, workingDirectory: repoPath)

        // Parse the output to get pipeline ID
        // glab ci run outputs something like "Created pipeline (id: 123456)"
        if let match = result.stdout.range(of: #"id:\s*(\d+)"#, options: .regularExpression) {
            let idStr = result.stdout[match].replacingOccurrences(of: "id:", with: "").trimmingCharacters(in: .whitespaces)
            return try await getRun(repoPath: repoPath, runId: idStr)
        }

        return nil
    }

    func cancelRun(repoPath: String, runId: String) async throws {
        // glab uses ci cancel or api call
        _ = try await executeGLab(["api", "-X", "POST", "projects/:id/pipelines/\(runId)/cancel"], workingDirectory: repoPath)
    }

    // MARK: - Auth

    func checkAuthentication() async -> Bool {
        do {
            let env = ShellEnvironment.loadUserShellEnvironment()
            let result = try await ProcessExecutor.shared.executeWithOutput(
                executable: glabPath,
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

    func executeGLab(_ arguments: [String], workingDirectory: String) async throws -> ProcessResult {
        logger.debug("Executing: glab \(arguments.joined(separator: " "))")

        let env = ShellEnvironment.loadUserShellEnvironment()
        let result = try await ProcessExecutor.shared.executeWithOutput(
            executable: glabPath,
            arguments: arguments,
            environment: env,
            workingDirectory: workingDirectory
        )

        if result.exitCode != 0 {
            logger.error("glab command failed: \(result.stderr)")
            throw WorkflowError.executionFailed(result.stderr)
        }

        return result
    }

    func parseRunStatus(_ status: String) -> RunStatus {
        switch status.lowercased() {
        case "pending", "created", "waiting_for_resource", "preparing", "scheduled":
            return .pending
        case "running":
            return .inProgress
        case "success", "failed", "canceled", "skipped", "manual":
            return .completed
        default:
            return .completed
        }
    }

    func parseConclusion(_ status: String) -> RunConclusion? {
        switch status.lowercased() {
        case "success":
            return .success
        case "failed":
            return .failure
        case "canceled":
            return .cancelled
        case "skipped":
            return .skipped
        case "pending", "running", "created", "waiting_for_resource", "preparing", "scheduled", "manual":
            return nil
        default:
            return nil
        }
    }

}
