//
//  WorkflowService+Loading.swift
//  aizen
//
//  Workflow and run list loading support.
//

import Foundation
import os.log

@MainActor
extension WorkflowService {
    func loadWorkflows() async {
        guard provider != .none else { return }

        isLoading = true
        error = nil

        do {
            workflows = try await currentProvider?.listWorkflows(repoPath: repoPath) ?? []
        } catch let workflowError as WorkflowError {
            error = workflowError
            logger.error("Failed to load workflows: \(workflowError.localizedDescription)")
        } catch {
            self.error = .executionFailed(error.localizedDescription)
            logger.error("Failed to load workflows: \(error.localizedDescription)")
        }

        isLoading = false
        isStateStale = false
    }

    func loadRuns() async {
        guard provider != .none else { return }

        isLoading = true
        error = nil

        do {
            runs = try await currentProvider?.listRuns(
                repoPath: repoPath,
                workflow: nil,
                branch: currentBranch,
                limit: runsLimit
            ) ?? []
        } catch let workflowError as WorkflowError {
            error = workflowError
            logger.error("Failed to load runs: \(workflowError.localizedDescription)")
        } catch {
            self.error = .executionFailed(error.localizedDescription)
            logger.error("Failed to load runs: \(error.localizedDescription)")
        }

        isLoading = false
        isStateStale = false
    }

    func refresh() async {
        guard provider != .none else { return }
        await loadWorkflows()
        await loadRuns()

        if let selected = selectedRun {
            await selectRun(selected)
        }
    }
}
