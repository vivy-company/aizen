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
        return items.map { item in
            Workflow(
                id: String(item.id),
                name: item.name,
                path: item.path,
                state: item.state == "active" ? .active : .disabled,
                provider: .github
            )
        }
    }

    func getWorkflowInputs(repoPath: String, workflow: Workflow) async throws -> [WorkflowInput] {
        // Get workflow YAML content
        let result = try await executeGH(["workflow", "view", workflow.name, "--yaml"], workingDirectory: repoPath)

        return parseWorkflowDispatchInputs(yaml: result.stdout)
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

    // Pre-compiled regex patterns for log parsing
    private static let timestampRegex = try? NSRegularExpression(pattern: #"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})"#)
    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    func getStructuredLogs(repoPath: String, runId: String, jobId: String, steps: [WorkflowStep]) async throws -> WorkflowLogs {
        // Use gh api to get raw logs for the job
        // Note: This only works after job completion - returns 404 for in-progress jobs
        let result = try await executeGH(["api", "repos/{owner}/{repo}/actions/jobs/\(jobId)/logs"], workingDirectory: repoPath)
        let rawLogs = result.stdout

        // Sort steps by start time (descending) for proper matching
        let sortedSteps = steps.sorted { step1, step2 in
            guard let start1 = step1.startedAt, let start2 = step2.startedAt else {
                return step1.number > step2.number
            }
            return start1 > start2
        }

        // Parse log lines and correlate with steps
        var logLines: [WorkflowLogLine] = []
        logLines.reserveCapacity(rawLogs.count / 80)

        let lines = rawLogs.components(separatedBy: .newlines)
        var lineIndex = 0

        for line in lines {
            guard !line.isEmpty else { continue }

            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            var timestamp: Date?
            var content = line

            // Parse timestamp from line (format: 2025-12-17T07:30:39.5778140Z ...)
            if let match = Self.timestampRegex?.firstMatch(in: line, range: range),
               let timestampRange = Range(match.range(at: 1), in: line) {
                let timestampStr = String(line[timestampRange])
                timestamp = Self.dateFormatter.date(from: timestampStr + "Z")

                // Remove timestamp from content
                if let fullRange = Range(match.range, in: line) {
                    content = String(line[fullRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                    // Remove microseconds suffix (e.g., ".5778140Z ")
                    if content.hasPrefix(".") {
                        if let spaceIndex = content.firstIndex(of: " ") {
                            content = String(content[content.index(after: spaceIndex)...])
                        }
                    }
                }
            }

            // Find matching step by timestamp (checking newest first)
            var stepName = "Setup"
            var stepNumber: Int?

            if let ts = timestamp {
                for step in sortedSteps {
                    if let stepStart = step.startedAt, ts >= stepStart {
                        stepName = step.name
                        stepNumber = step.number
                        break
                    }
                }
            }

            // Check for error markers
            let isError = content.contains("##[error]")

            // Check for group markers
            let isGroupStart = content.contains("##[group]")
            let isGroupEnd = content.contains("##[endgroup]")
            var groupName: String?

            if isGroupStart {
                groupName = content.replacingOccurrences(of: "##[group]", with: "")
            }

            // Clean up GitHub Actions markers
            content = content
                .replacingOccurrences(of: "##[error]", with: "")
                .replacingOccurrences(of: "##[warning]", with: "")
                .replacingOccurrences(of: "##[group]", with: "")
                .replacingOccurrences(of: "##[endgroup]", with: "")

            logLines.append(WorkflowLogLine(
                id: lineIndex,
                stepName: stepName,
                stepNumber: stepNumber,
                content: content,
                timestamp: timestamp,
                isError: isError,
                isGroupStart: isGroupStart,
                isGroupEnd: isGroupEnd,
                groupName: groupName
            ))
            lineIndex += 1
        }

        return WorkflowLogs(
            runId: runId,
            jobId: jobId,
            lines: logLines,
            rawContent: rawLogs,
            lastUpdated: Date()
        )
    }

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

    private func executeGH(_ arguments: [String], workingDirectory: String) async throws -> ProcessResult {
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

    private func parseRunStatus(_ status: String) -> RunStatus {
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

    private func parseConclusion(_ conclusion: String) -> RunConclusion? {
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

    private func parseWorkflowDispatchInputs(yaml: String) -> [WorkflowInput] {
        var inputs: [WorkflowInput] = []

        let lines = yaml.components(separatedBy: .newlines)
        var inInputs = false
        var inputsBaseIndent = 0
        var currentInput: String?
        var currentDescription = ""
        var currentRequired = false
        var currentDefault: String?
        var currentType: WorkflowInputType = .string
        var currentOptions: [String] = []

        func saveCurrentInput() {
            if let name = currentInput, !name.isEmpty {
                inputs.append(WorkflowInput(
                    id: name,
                    description: currentDescription,
                    required: currentRequired,
                    type: currentType,
                    defaultValue: currentDefault
                ))
            }
            currentInput = nil
            currentDescription = ""
            currentRequired = false
            currentDefault = nil
            currentType = .string
            currentOptions = []
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let indent = line.prefix(while: { $0 == " " }).count

            // Look for workflow_dispatch inputs section
            if trimmed == "inputs:" || trimmed.hasPrefix("inputs:") {
                // Check if this is under workflow_dispatch (not under jobs)
                // Simple heuristic: inputs at indent 4-6 are likely workflow_dispatch
                if indent >= 4 && indent <= 6 {
                    inInputs = true
                    inputsBaseIndent = indent
                    continue
                }
            }

            if inInputs {
                let inputNameIndent = inputsBaseIndent + 2
                let propertyIndent = inputsBaseIndent + 4

                // Exit if we hit a line at same or lower indent than inputs section
                if indent <= inputsBaseIndent && !trimmed.hasPrefix("-") {
                    saveCurrentInput()
                    inInputs = false
                    continue
                }

                // New input name (at inputNameIndent, ends with :, no spaces in name)
                if indent == inputNameIndent && trimmed.hasSuffix(":") {
                    let potentialName = String(trimmed.dropLast())
                    // Validate it's a simple name (no spaces, not a property)
                    if !potentialName.contains(" ") && !potentialName.contains("'") {
                        saveCurrentInput()
                        currentInput = potentialName
                        continue
                    }
                }

                // Input properties (at propertyIndent or deeper)
                if indent >= propertyIndent && currentInput != nil {
                    if trimmed.hasPrefix("description:") {
                        currentDescription = extractYAMLValue(trimmed, key: "description")
                    } else if trimmed.hasPrefix("required:") {
                        currentRequired = extractYAMLValue(trimmed, key: "required").lowercased() == "true"
                    } else if trimmed.hasPrefix("default:") {
                        currentDefault = extractYAMLValue(trimmed, key: "default")
                    } else if trimmed.hasPrefix("type:") {
                        let typeStr = extractYAMLValue(trimmed, key: "type")
                        switch typeStr.lowercased() {
                        case "boolean": currentType = .boolean
                        case "choice": currentType = .choice([])
                        case "environment": currentType = .environment
                        default: currentType = .string
                        }
                    } else if trimmed.hasPrefix("options:") {
                        currentOptions = []
                    } else if trimmed.hasPrefix("- ") {
                        if case .choice = currentType {
                            let option = String(trimmed.dropFirst(2)).trimmingCharacters(in: .init(charactersIn: "'\""))
                            currentOptions.append(option)
                            currentType = .choice(currentOptions)
                        }
                    }
                }
            }
        }

        // Save last input if any
        saveCurrentInput()

        return inputs
    }

    private func extractYAMLValue(_ line: String, key: String) -> String {
        let parts = line.components(separatedBy: ":")
        guard parts.count >= 2 else { return "" }
        return parts.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces).trimmingCharacters(in: .init(charactersIn: "'\""))
    }
}

// MARK: - Response Types

private struct GitHubWorkflowResponse: Decodable {
    let id: Int
    let name: String
    let path: String
    let state: String
}

private struct GitHubRunResponse: Decodable {
    let databaseId: Int
    let workflowDatabaseId: Int?
    let workflowName: String
    let number: Int
    let status: String
    let conclusion: String?
    let headBranch: String
    let headSha: String
    let event: String
    let createdAt: Date?
    let updatedAt: Date?
    let url: String?
    let displayTitle: String?
}

private struct GitHubJobsResponse: Decodable {
    let jobs: [GitHubJob]
}

private struct GitHubJob: Decodable {
    let databaseId: Int
    let name: String
    let status: String
    let conclusion: String?
    let startedAt: Date?
    let completedAt: Date?
    let steps: [GitHubStep]
}

private struct GitHubStep: Decodable {
    let number: Int
    let name: String
    let status: String
    let conclusion: String?
    let startedAt: Date?
    let completedAt: Date?
}
