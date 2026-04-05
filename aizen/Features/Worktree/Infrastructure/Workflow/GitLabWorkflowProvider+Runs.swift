//
//  GitLabWorkflowProvider+Runs.swift
//  aizen
//
//  Pipeline and job loading for the GitLab workflow provider
//

import Foundation

extension GitLabWorkflowProvider {
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
                steps: []
            )
        }
    }
}
