//
//  WorkflowService+RunSelection.swift
//  aizen
//
//  Run selection and job-focused log loading support.
//

import Foundation

@MainActor
extension WorkflowService {
    func selectRun(_ run: WorkflowRun) async {
        let isSameRun = selectedRun?.id == run.id
        if isSameRun && !selectedRunJobs.isEmpty {
            selectedRun = run
            return
        }

        selectedWorkflow = nil
        selectedRun = run
        selectedRunJobs = []
        runLogs = ""
        currentLogJobId = nil
        stopLogPolling()

        let provider = currentProvider
        let path = repoPath
        let runId = run.id

        Task { [weak self] in
            do {
                let jobs = try await provider?.getRunJobs(repoPath: path, runId: runId) ?? []
                await MainActor.run {
                    self?.selectedRunJobs = jobs
                }

                if let firstJob = jobs.first(where: { $0.conclusion == .failure }) ?? jobs.first {
                    await self?.loadLogs(runId: runId, jobId: firstJob.id)
                } else {
                    await self?.loadLogs(runId: runId)
                }

                if run.isInProgress {
                    self?.startLogPolling(runId: run.id)
                }
            } catch {
                await self?.loadLogs(runId: runId)
            }
        }
    }

    func clearSelection() {
        selectedWorkflow = nil
        selectedRun = nil
        selectedRunJobs = []
        runLogs = ""
        structuredLogs = nil
        currentLogJobId = nil
        stopLogPolling()
    }

    func loadJobLogs(_ job: WorkflowJob) async {
        guard let run = selectedRun else { return }
        await loadLogs(runId: run.id, jobId: job.id)
    }
}
