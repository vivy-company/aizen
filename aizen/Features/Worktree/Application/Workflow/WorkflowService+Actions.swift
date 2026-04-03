//
//  WorkflowService+Actions.swift
//  aizen
//
//  Workflow trigger and cancellation actions.
//

import Foundation
import os.log

@MainActor
extension WorkflowService {
    func getWorkflowInputs(workflow: Workflow) async -> [WorkflowInput] {
        do {
            return try await currentProvider?.getWorkflowInputs(repoPath: repoPath, workflow: workflow) ?? []
        } catch {
            logger.error("Failed to get workflow inputs: \(error.localizedDescription)")
            return []
        }
    }

    func triggerWorkflow(_ workflow: Workflow, branch: String, inputs: [String: String]) async -> Bool {
        isLoading = true
        error = nil

        do {
            let newRun = try await currentProvider?.triggerWorkflow(
                repoPath: repoPath,
                workflow: workflow,
                branch: branch,
                inputs: inputs
            )

            await loadRuns()

            if let run = newRun {
                await selectRun(run)
            }

            isLoading = false
            return true
        } catch let workflowError as WorkflowError {
            error = workflowError
            logger.error("Failed to trigger workflow: \(workflowError.localizedDescription)")
        } catch {
            self.error = .executionFailed(error.localizedDescription)
            logger.error("Failed to trigger workflow: \(error.localizedDescription)")
        }

        isLoading = false
        return false
    }

    func cancelRun(_ run: WorkflowRun) async -> Bool {
        stopLogPolling()

        if selectedRun?.id == run.id {
            runLogs = "Cancelling workflow run...\n\nThis may take a moment."
            structuredLogs = nil
        }

        isLoading = true
        error = nil

        do {
            try await currentProvider?.cancelRun(repoPath: repoPath, runId: run.id)

            if selectedRun?.id == run.id {
                var cancelledRun = run
                cancelledRun = WorkflowRun(
                    id: run.id,
                    workflowId: run.workflowId,
                    workflowName: run.workflowName,
                    runNumber: run.runNumber,
                    status: .completed,
                    conclusion: .cancelled,
                    branch: run.branch,
                    commit: run.commit,
                    commitMessage: run.commitMessage,
                    event: run.event,
                    actor: run.actor,
                    startedAt: run.startedAt,
                    completedAt: Date(),
                    url: run.url
                )
                selectedRun = cancelledRun

                if let index = runs.firstIndex(where: { $0.id == run.id }) {
                    runs[index] = cancelledRun
                }

                runLogs = "Workflow run cancelled."
            }

            Task {
                try? await Task.sleep(for: .seconds(2))
                await loadRuns()
                if let updatedRun = try? await currentProvider?.getRun(repoPath: repoPath, runId: run.id) {
                    await MainActor.run {
                        selectedRun = updatedRun
                        if let index = runs.firstIndex(where: { $0.id == run.id }) {
                            runs[index] = updatedRun
                        }
                    }
                }
            }

            isLoading = false
            return true
        } catch let workflowError as WorkflowError {
            error = workflowError
            logger.error("Failed to cancel run: \(workflowError.localizedDescription)")
            runLogs = "Failed to cancel: \(workflowError.localizedDescription)"
        } catch {
            self.error = .executionFailed(error.localizedDescription)
            logger.error("Failed to cancel run: \(error.localizedDescription)")
            runLogs = "Failed to cancel."
        }

        isLoading = false
        return false
    }
}
