//
//  WorkflowRunsListView.swift
//  aizen
//
//  Displays list of workflow runs for the current branch
//

import SwiftUI

struct WorkflowRunsListView: View {
    let runs: [WorkflowRun]
    let branch: String
    let isLoading: Bool
    let onSelectRun: (WorkflowRun) -> Void
    let onCancelRun: (WorkflowRun) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if isLoading && runs.isEmpty {
                loadingState
            } else if runs.isEmpty {
                emptyState
            } else {
                ForEach(runs) { run in
                    WorkflowRunRow(
                        run: run,
                        onSelect: { onSelectRun(run) },
                        onCancel: { onCancelRun(run) }
                    )
                }
            }
        }
    }
}
