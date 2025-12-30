//
//  WorkflowProviderProtocol.swift
//  aizen
//
//  Common protocol for CI/CD workflow providers
//

import Foundation

protocol WorkflowProviderProtocol {
    var provider: WorkflowProvider { get }

    // Workflows
    func listWorkflows(repoPath: String) async throws -> [Workflow]
    func getWorkflowInputs(repoPath: String, workflow: Workflow) async throws -> [WorkflowInput]

    // Runs
    func listRuns(repoPath: String, workflow: Workflow?, branch: String?, limit: Int) async throws -> [WorkflowRun]
    func getRun(repoPath: String, runId: String) async throws -> WorkflowRun
    func getRunJobs(repoPath: String, runId: String) async throws -> [WorkflowJob]

    // Actions
    func triggerWorkflow(repoPath: String, workflow: Workflow, branch: String, inputs: [String: String]) async throws -> WorkflowRun?
    func cancelRun(repoPath: String, runId: String) async throws

    // Logs
    func getRunLogs(repoPath: String, runId: String, jobId: String?) async throws -> String
    func getStructuredLogs(repoPath: String, runId: String, jobId: String, steps: [WorkflowStep]) async throws -> WorkflowLogs

    // Auth
    func checkAuthentication() async -> Bool
}

// MARK: - Base Implementation Helpers

extension WorkflowProviderProtocol {
    nonisolated func executeCommand(_ executable: String, arguments: [String], workingDirectory: String) async throws -> ProcessResult {
        try await ProcessExecutor.shared.executeWithOutput(
            executable: executable,
            arguments: arguments,
            workingDirectory: workingDirectory
        )
    }

    nonisolated func parseJSON<T: Decodable>(_ data: Data, as type: T.Type) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
}
