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
            HStack {
                Text("Recent Runs")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Spacer()

                TagBadge(
                    text: branch,
                    color: Color(nsColor: .controlBackgroundColor),
                    font: .caption,
                    backgroundOpacity: 1,
                    textColor: .secondary
                )
            }

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
