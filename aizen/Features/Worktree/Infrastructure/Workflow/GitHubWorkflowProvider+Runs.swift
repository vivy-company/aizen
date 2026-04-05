import Foundation

extension GitHubWorkflowProvider {
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
        let result = try await executeGH(
            ["run", "view", runId, "--json", "databaseId,workflowDatabaseId,workflowName,number,status,conclusion,headBranch,headSha,event,createdAt,updatedAt,url,displayTitle"],
            workingDirectory: repoPath
        )

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
}
