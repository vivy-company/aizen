import Foundation

extension GitHubWorkflowProvider {
    func listWorkflows(repoPath: String) async throws -> [Workflow] {
        let result = try await executeGH(["workflow", "list", "--json", "id,name,path,state"], workingDirectory: repoPath)

        guard let data = result.stdout.data(using: .utf8) else {
            throw WorkflowError.parseError("Invalid UTF-8 output")
        }

        let items = try parseJSON(data, as: [GitHubWorkflowResponse].self)
        var workflows: [Workflow] = []

        for item in items {
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

    func checkWorkflowDispatch(repoPath: String, workflowPath: String) -> Bool {
        let fullPath = (repoPath as NSString).appendingPathComponent(workflowPath)
        guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else {
            return false
        }
        return content.contains("workflow_dispatch")
    }

    func getWorkflowInputs(repoPath: String, workflow: Workflow) async throws -> [WorkflowInput] {
        let result = try await executeGH(["workflow", "view", workflow.name, "--yaml"], workingDirectory: repoPath)
        return GitHubWorkflowDispatchInputParser.parse(yaml: result.stdout)
    }
}
