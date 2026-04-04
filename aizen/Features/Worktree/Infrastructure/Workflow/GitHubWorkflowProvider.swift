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

    func listWorkflows(repoPath: String) async throws -> [Workflow] {
        let result = try await executeGH(["workflow", "list", "--json", "id,name,path,state"], workingDirectory: repoPath)

        guard let data = result.stdout.data(using: .utf8) else {
            throw WorkflowError.parseError("Invalid UTF-8 output")
        }

        let items = try parseJSON(data, as: [GitHubWorkflowResponse].self)
        var workflows: [Workflow] = []

        for item in items {
            // Check if workflow supports manual trigger by reading the YAML
            let supportsManualTrigger = checkWorkflowDispatch(repoPath: repoPath, workflowPath: item.path)

            workflows.append(Workflow(
                id: String(item.id),
                name: item.name,
                path: item.path,
                state: item.state == "active" ? .active : .disabled,
                provider: .github,
                supportsManualTrigger: supportsManualTrigger
            ))
        }

        return workflows
    }

    private func checkWorkflowDispatch(repoPath: String, workflowPath: String) -> Bool {
        let fullPath = (repoPath as NSString).appendingPathComponent(workflowPath)
        guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else {
            return false
        }
        // Check for workflow_dispatch in the on: section
        return content.contains("workflow_dispatch")
    }

    func getWorkflowInputs(repoPath: String, workflow: Workflow) async throws -> [WorkflowInput] {
        // Get workflow YAML content
        let result = try await executeGH(["workflow", "view", workflow.name, "--yaml"], workingDirectory: repoPath)

        return GitHubWorkflowDispatchInputParser.parse(yaml: result.stdout)
    }

    // MARK: - Runs

    func listRuns(repoPath: String, workflow: Workflow?, branch: String?, limit: Int) async throws -> [WorkflowRun] {
        var args = ["run", "list", "--json", "databaseId,workflowDatabaseId,workflowName,number,status,conclusion,headBranch,headSha,event,createdAt,updatedAt,url,displayTitle"]
        args.append(contentsOf: ["--limit", String(limit)])

        if let workflow = workflow {
            args.append(contentsOf: ["--workflow", workflow.name])
        }

        if let branch = branch {
            args.append(contentsOf: ["--branch", branch])
        }

        let result = try await executeGH(args, workingDirectory: repoPath)

        guard let data = result.stdout.data(using: .utf8) else {
            throw WorkflowError.parseError("Invalid UTF-8 output")
        }

        let items = try parseJSON(data, as: [GitHubRunResponse].self)
        return items.map { item in
            WorkflowRun(
                id: String(item.databaseId),
                workflowId: String(item.workflowDatabaseId ?? 0),
                workflowName: item.workflowName,
                runNumber: item.number,
                status: parseRunStatus(item.status),
                conclusion: item.conclusion.flatMap { parseConclusion($0) },
                branch: item.headBranch,
                commit: String(item.headSha.prefix(7)),
                commitMessage: item.displayTitle,
                event: item.event,
                actor: "",
                startedAt: item.createdAt,
                completedAt: item.updatedAt,
                url: item.url
            )
        }
    }

    func getRun(repoPath: String, runId: String) async throws -> WorkflowRun {
        let result = try await executeGH(["run", "view", runId, "--json", "databaseId,workflowDatabaseId,workflowName,number,status,conclusion,headBranch,headSha,event,createdAt,updatedAt,url,displayTitle"], workingDirectory: repoPath)

        guard let data = result.stdout.data(using: .utf8) else {
            throw WorkflowError.parseError("Invalid UTF-8 output")
        }

        let item = try parseJSON(data, as: GitHubRunResponse.self)
        return WorkflowRun(
            id: String(item.databaseId),
            workflowId: String(item.workflowDatabaseId ?? 0),
            workflowName: item.workflowName,
            runNumber: item.number,
            status: parseRunStatus(item.status),
            conclusion: item.conclusion.flatMap { parseConclusion($0) },
            branch: item.headBranch,
            commit: String(item.headSha.prefix(7)),
            commitMessage: item.displayTitle,
            event: item.event,
            actor: "",
            startedAt: item.createdAt,
            completedAt: item.updatedAt,
            url: item.url
        )
    }

    func getRunJobs(repoPath: String, runId: String) async throws -> [WorkflowJob] {
        let result = try await executeGH(["run", "view", runId, "--json", "jobs"], workingDirectory: repoPath)

        guard let data = result.stdout.data(using: .utf8) else {
            throw WorkflowError.parseError("Invalid UTF-8 output")
        }

        let response = try parseJSON(data, as: GitHubJobsResponse.self)
        return response.jobs.map { job in
            WorkflowJob(
                id: String(job.databaseId),
                name: job.name,
                status: parseRunStatus(job.status),
                conclusion: job.conclusion.flatMap { parseConclusion($0) },
                startedAt: job.startedAt,
                completedAt: job.completedAt,
                steps: job.steps.enumerated().map { index, step in
                    WorkflowStep(
                        id: "\(job.databaseId)-\(index)",
                        number: step.number,
                        name: step.name,
                        status: parseRunStatus(step.status),
                        conclusion: step.conclusion.flatMap { parseConclusion($0) },
                        startedAt: step.startedAt,
                        completedAt: step.completedAt
                    )
                }
            )
        }
    }

    // MARK: - Actions

    func triggerWorkflow(repoPath: String, workflow: Workflow, branch: String, inputs: [String: String]) async throws -> WorkflowRun? {
        var args = ["workflow", "run", workflow.name, "--ref", branch]

        for (key, value) in inputs {
            args.append(contentsOf: ["-f", "\(key)=\(value)"])
        }

        _ = try await executeGH(args, workingDirectory: repoPath)

        // gh workflow run doesn't return the run ID, so we need to fetch the latest run
        try await Task.sleep(for: .seconds(2))

        let runs = try await listRuns(repoPath: repoPath, workflow: workflow, branch: branch, limit: 1)
        return runs.first
    }

    func cancelRun(repoPath: String, runId: String) async throws {
        _ = try await executeGH(["run", "cancel", runId], workingDirectory: repoPath)
    }

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
