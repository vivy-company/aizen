//
//  WorkflowService+Logs.swift
//  aizen
//
//  Run log loading and polling support.
//

import Foundation
import os.log

@MainActor
extension WorkflowService {
    func loadLogs(runId: String, jobId: String? = nil) async {
        if let jobId = jobId, jobId == currentLogJobId, !runLogs.isEmpty {
            return
        }

        isLoadingLogs = true
        currentLogJobId = jobId
        structuredLogs = nil

        let providerImpl = currentProvider
        let providerType = self.provider
        let path = repoPath
        let jobs = selectedRunJobs

        if providerType == .github {
            if let jobId = jobId, let job = jobs.first(where: { $0.id == jobId }) {
                if job.status == .queued || job.status == .waiting || job.status == .pending {
                    runLogs = "Waiting for job to start...\n\nLogs will be available when the job completes."
                    isLoadingLogs = false
                    return
                }
                if job.status == .inProgress || job.conclusion == nil {
                    runLogs = "Job is running...\n\nLogs will be available when the job completes."
                    isLoadingLogs = false
                    return
                }
            } else if selectedRun?.isInProgress == true {
                runLogs = "Workflow is running...\n\nLogs will be available when jobs complete."
                isLoadingLogs = false
                return
            }
        }

        do {
            if let jobId = jobId,
               let job = jobs.first(where: { $0.id == jobId }),
               !job.steps.isEmpty {
                let structured = try await providerImpl?.getStructuredLogs(
                    repoPath: path,
                    runId: runId,
                    jobId: jobId,
                    steps: job.steps
                )

                if let structured = structured {
                    structuredLogs = structured
                    runLogs = structured.rawContent
                    isLoadingLogs = false
                    return
                }
            }

            let logs = try await providerImpl?.getRunLogs(repoPath: path, runId: runId, jobId: jobId) ?? ""
            logger.debug("Loaded plain text logs, length: \(logs.count)")
            runLogs = logs.isEmpty ? "No logs available for this job." : logs
        } catch {
            logger.error("Failed to load logs: \(error.localizedDescription)")
            runLogs = "Failed to load logs: \(error.localizedDescription)"
        }

        isLoadingLogs = false
    }

    func refreshLogs() async {
        guard let run = selectedRun else { return }
        await loadLogs(runId: run.id)
    }

    func startLogPolling(runId: String) {
        stopLogPolling()

        let provider = currentProvider
        let path = repoPath
        let jobId = currentLogJobId

        logPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                if let provider = provider {
                    do {
                        let updatedRun = try await provider.getRun(repoPath: path, runId: runId)
                        let jobs = try await provider.getRunJobs(repoPath: path, runId: runId)

                        await MainActor.run { [weak self] in
                            self?.selectedRun = updatedRun
                            self?.selectedRunJobs = jobs

                            if let index = self?.runs.firstIndex(where: { $0.id == runId }) {
                                self?.runs[index] = updatedRun
                            }

                            if !updatedRun.isInProgress {
                                self?.stopLogPolling()
                            }
                        }

                        let targetJobId = jobs.first(where: { $0.conclusion == .failure })?.id
                            ?? jobs.first(where: { $0.status == .inProgress })?.id
                            ?? jobId
                            ?? jobs.first?.id

                        if let targetJobId = targetJobId {
                            await self?.loadLogsForPolling(runId: runId, jobId: targetJobId)
                        }
                    } catch {
                        // Continue polling on transient provider errors.
                    }
                }

                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stopLogPolling() {
        logPollingTask?.cancel()
        logPollingTask = nil
    }

    private func loadLogsForPolling(runId: String, jobId: String) async {
        let providerImpl = currentProvider
        let providerType = self.provider
        let path = repoPath
        let jobs = selectedRunJobs
        let currentContent = runLogs

        if providerType == .github {
            if let job = jobs.first(where: { $0.id == jobId }) {
                if job.status == .queued || job.status == .waiting || job.status == .pending {
                    if !runLogs.contains("Waiting for job") {
                        runLogs = "Waiting for job to start...\n\nLogs will be available when the job completes."
                        structuredLogs = nil
                    }
                    return
                }
                if job.status == .inProgress || job.conclusion == nil {
                    if !runLogs.contains("Job is running") {
                        runLogs = "Job is running...\n\nLogs will be available when the job completes."
                        structuredLogs = nil
                    }
                    return
                }
            } else if selectedRun?.isInProgress == true {
                if !runLogs.contains("Workflow is running") {
                    runLogs = "Workflow is running...\n\nLogs will be available when jobs complete."
                    structuredLogs = nil
                }
                return
            }
        }

        do {
            if let job = jobs.first(where: { $0.id == jobId }), !job.steps.isEmpty {
                let structured = try await providerImpl?.getStructuredLogs(
                    repoPath: path,
                    runId: runId,
                    jobId: jobId,
                    steps: job.steps
                )

                if let structured = structured {
                    if structured.rawContent != currentContent {
                        structuredLogs = structured
                        runLogs = structured.rawContent
                        currentLogJobId = jobId
                    }
                    return
                }
            }

            let logs = try await providerImpl?.getRunLogs(repoPath: path, runId: runId, jobId: jobId) ?? ""

            if logs != currentContent {
                runLogs = logs
                structuredLogs = nil
            }
        } catch {
            logger.error("Failed to fetch logs: \(error.localizedDescription)")
        }
    }
}
