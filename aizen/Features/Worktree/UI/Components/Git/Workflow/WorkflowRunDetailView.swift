//
//  WorkflowRunDetailView.swift
//  aizen
//
//  Displays workflow run details including jobs, steps, and logs
//

import SwiftUI

struct WorkflowRunDetailView: View {
    @ObservedObject var service: WorkflowService

    @State var selectedJobId: String?
    @State private var selectedRunId: String?
    @State var showCancelConfirmation: Bool = false

    @AppStorage("editorFontFamily") private var editorFontFamily: String = "Menlo"

    var run: WorkflowRun? { service.selectedRun }
    var jobs: [WorkflowJob] { service.selectedRunJobs }

    private struct SelectionSyncKey: Hashable {
        let runId: String
        let jobs: [WorkflowJob]
    }

    var body: some View {
        if let run = run {
            VStack(spacing: 0) {
                // Run header
                runHeader(run)

                GitWindowDivider()

                // Jobs and logs
            HSplitView {
                // Jobs panel
                jobsPanel
                    .frame(minWidth: 200, idealWidth: 250, maxWidth: 350)

                    // Logs panel
                    logsPanel
                }
            }
            .task(id: SelectionSyncKey(runId: run.id, jobs: jobs)) {
                syncSelectedJob(for: run, jobs: jobs)
            }
        } else {
            Text("No run selected")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func syncSelectedJob(for run: WorkflowRun, jobs: [WorkflowJob]) {
        if selectedRunId != run.id {
            selectedRunId = run.id
            selectedJobId = nil
        } else if let selectedJobId, !jobs.contains(where: { $0.id == selectedJobId }) {
            self.selectedJobId = nil
        }

        if selectedJobId == nil && !jobs.isEmpty {
            selectedJobId = jobs.first(where: { $0.conclusion == .failure })?.id ?? jobs.first?.id
        }
    }

}
