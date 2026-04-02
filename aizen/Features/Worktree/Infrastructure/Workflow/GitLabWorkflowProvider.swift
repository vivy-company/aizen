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

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "GitLabWorkflow")
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

        return parseGitLabVariables(yaml: content)
    }

    // MARK: - Runs (Pipelines)

    func listRuns(repoPath: String, workflow: Workflow?, branch: String?, limit: Int) async throws -> [WorkflowRun] {
        var args = ["ci", "list", "--output", "json"]

        if let branch = branch {
            args.append(contentsOf: ["--ref", branch])
        }

        let result = try await executeGLab(args, workingDirectory: repoPath)

        guard let data = result.stdout.data(using: .utf8) else {
            throw WorkflowError.parseError("Invalid UTF-8 output")
        }

        let items = try parseJSON(data, as: [GitLabPipelineResponse].self)
        return items.prefix(limit).map { item in
            WorkflowRun(
                id: String(item.id),
                workflowId: "gitlab-ci",
                workflowName: "GitLab CI",
                runNumber: item.id,
                status: parseRunStatus(item.status),
                conclusion: parseConclusion(item.status),
                branch: item.ref,
                commit: String(item.sha.prefix(7)),
                commitMessage: nil,
                event: item.source ?? "push",
                actor: item.user?.username ?? "unknown",
                startedAt: item.createdAt,
                completedAt: item.updatedAt,
                url: item.webUrl
            )
        }
    }

    func getRun(repoPath: String, runId: String) async throws -> WorkflowRun {
        let result = try await executeGLab(["ci", "get", runId, "--output", "json"], workingDirectory: repoPath)

        guard let data = result.stdout.data(using: .utf8) else {
            throw WorkflowError.parseError("Invalid UTF-8 output")
        }

        let item = try parseJSON(data, as: GitLabPipelineResponse.self)
        return WorkflowRun(
            id: String(item.id),
            workflowId: "gitlab-ci",
            workflowName: "GitLab CI",
            runNumber: item.id,
            status: parseRunStatus(item.status),
            conclusion: parseConclusion(item.status),
            branch: item.ref,
            commit: String(item.sha.prefix(7)),
            commitMessage: nil,
            event: item.source ?? "push",
            actor: item.user?.username ?? "unknown",
            startedAt: item.createdAt,
            completedAt: item.updatedAt,
            url: item.webUrl
        )
    }

    func getRunJobs(repoPath: String, runId: String) async throws -> [WorkflowJob] {
        // glab doesn't have a direct jobs JSON output, use API via glab api
        let result = try await executeGLab(["api", "projects/:id/pipelines/\(runId)/jobs"], workingDirectory: repoPath)

        guard let data = result.stdout.data(using: .utf8) else {
            throw WorkflowError.parseError("Invalid UTF-8 output")
        }

        let items = try parseJSON(data, as: [GitLabJobResponse].self)
        return items.map { job in
            WorkflowJob(
                id: String(job.id),
                name: job.name,
                status: parseRunStatus(job.status),
                conclusion: parseConclusion(job.status),
                startedAt: job.startedAt,
                completedAt: job.finishedAt,
                steps: []  // GitLab jobs don't have steps in the same way
            )
        }
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

    // MARK: - Logs

    func getRunLogs(repoPath: String, runId: String, jobId: String?) async throws -> String {
        if let jobId = jobId {
            // Get specific job trace
            let result = try await executeGLab(["api", "projects/:id/jobs/\(jobId)/trace"], workingDirectory: repoPath)
            logger.debug("GitLab trace stdout length: \(result.stdout.count), stderr: \(result.stderr)")
            if result.stdout.isEmpty && !result.stderr.isEmpty {
                return "Error fetching logs: \(result.stderr)"
            }
            return result.stdout
        } else {
            // Get all job logs for the pipeline
            let jobs = try await getRunJobs(repoPath: repoPath, runId: runId)
            var allLogs = ""

            for job in jobs {
                let jobLog = try await executeGLab(["api", "projects/:id/jobs/\(job.id)/trace"], workingDirectory: repoPath)
                allLogs += "=== \(job.name) ===\n"
                allLogs += jobLog.stdout
                allLogs += "\n\n"
            }

            return allLogs
        }
    }

    func getStructuredLogs(repoPath: String, runId: String, jobId: String, steps: [WorkflowStep]) async throws -> WorkflowLogs {
        // GitLab doesn't have steps like GitHub, so just return the job trace as a single block
        let result = try await executeGLab(["api", "projects/:id/jobs/\(jobId)/trace"], workingDirectory: repoPath)
        let rawLogs = result.stdout

        let lines = rawLogs.components(separatedBy: .newlines).enumerated().map { index, line in
            WorkflowLogLine(
                id: index,
                stepName: "Job Output",
                content: line
            )
        }

        return WorkflowLogs(
            runId: runId,
            jobId: jobId,
            lines: lines,
            rawContent: rawLogs,
            lastUpdated: Date()
        )
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

    private func executeGLab(_ arguments: [String], workingDirectory: String) async throws -> ProcessResult {
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

    private func parseRunStatus(_ status: String) -> RunStatus {
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

    private func parseConclusion(_ status: String) -> RunConclusion? {
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

    private func parseGitLabVariables(yaml: String) -> [WorkflowInput] {
        var seenNames: Set<String> = []
        var inputs: [WorkflowInput] = []
        let lines = yaml.components(separatedBy: .newlines)

        var inVariables = false
        var variableIndent = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let indent = line.prefix(while: { $0 == " " }).count

            if trimmed.hasPrefix("variables:") && !trimmed.contains("$") {
                inVariables = true
                variableIndent = indent + 2
                continue
            }

            if inVariables {
                // Check if we've exited variables section
                if indent < variableIndent && !trimmed.isEmpty {
                    inVariables = false
                    continue
                }

                // Parse variable: value
                if indent == variableIndent && trimmed.contains(":") {
                    let parts = trimmed.split(separator: ":", maxSplits: 1)
                    if parts.count >= 1 {
                        let name = String(parts[0]).trimmingCharacters(in: .whitespaces)
                        let defaultValue = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: .init(charactersIn: "'\"")) : nil

                        // Skip GitLab predefined variables and duplicates
                        guard !name.hasPrefix("CI_"), !name.hasPrefix("GITLAB_") else { continue }
                        guard !seenNames.contains(name) else { continue }

                        seenNames.insert(name)
                        inputs.append(WorkflowInput(
                            id: name,
                            description: "",
                            required: false,
                            type: .string,
                            defaultValue: defaultValue
                        ))
                    }
                }
            }
        }

        return inputs
    }
}

// MARK: - Response Types

private struct GitLabPipelineResponse: Decodable {
    let id: Int
    let ref: String
    let sha: String
    let status: String
    let source: String?
    let createdAt: Date?
    let updatedAt: Date?
    let webUrl: String?
    let user: GitLabUser?
}

private struct GitLabUser: Decodable {
    let username: String
}

private struct GitLabJobResponse: Decodable {
    let id: Int
    let name: String
    let status: String
    let stage: String
    let startedAt: Date?
    let finishedAt: Date?
    let webUrl: String?
}
