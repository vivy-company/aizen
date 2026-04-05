import Foundation

extension GitHubWorkflowProvider {
    func triggerWorkflow(repoPath: String, workflow: Workflow, branch: String, inputs: [String: String]) async throws -> WorkflowRun? {
        var args = ["workflow", "run", workflow.name, "--ref", branch]

        for (key, value) in inputs {
            args.append(contentsOf: ["-f", "\(key)=\(value)"])
        }

        _ = try await executeGH(args, workingDirectory: repoPath)

        try await Task.sleep(for: .seconds(2))

        let runs = try await listRuns(repoPath: repoPath, workflow: workflow, branch: branch, limit: 1)
        return runs.first
    }

    func cancelRun(repoPath: String, runId: String) async throws {
        _ = try await executeGH(["run", "cancel", runId], workingDirectory: repoPath)
    }
}
