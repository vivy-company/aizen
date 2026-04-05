import Foundation

extension GitHubWorkflowProvider {
    func getRunLogs(repoPath: String, runId: String, jobId: String?) async throws -> String {
        var args = ["run", "view", runId, "--log"]
        if let jobId = jobId {
            args.append(contentsOf: ["--job", jobId])
        }

        let result = try await executeGH(args, workingDirectory: repoPath)
        return result.stdout
    }

    nonisolated static let timestampRegex = try? NSRegularExpression(pattern: #"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})"#)
}
