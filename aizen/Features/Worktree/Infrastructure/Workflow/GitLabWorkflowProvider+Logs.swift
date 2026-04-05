//
//  GitLabWorkflowProvider+Logs.swift
//  aizen
//
//  Pipeline log loading for the GitLab workflow provider
//

import Foundation
import os.log

extension GitLabWorkflowProvider {
    // MARK: - Logs

    func getRunLogs(repoPath: String, runId: String, jobId: String?) async throws -> String {
        if let jobId = jobId {
            let result = try await executeGLab(["api", "projects/:id/jobs/\(jobId)/trace"], workingDirectory: repoPath)
            logger.debug("GitLab trace stdout length: \(result.stdout.count), stderr: \(result.stderr)")
            if result.stdout.isEmpty && !result.stderr.isEmpty {
                return "Error fetching logs: \(result.stderr)"
            }
            return result.stdout
        } else {
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
}
