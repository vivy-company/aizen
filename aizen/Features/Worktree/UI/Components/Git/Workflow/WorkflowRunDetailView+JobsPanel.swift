//
//  WorkflowRunDetailView+JobsPanel.swift
//  aizen
//
//  Jobs panel rendering for workflow run details.
//

import SwiftUI

extension WorkflowRunDetailView {
    var jobsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Jobs")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    Task {
                        await service.refresh()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh")
            }
            .frame(height: 32)
            .padding(.horizontal, 12)

            GitWindowDivider()

            if jobs.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading jobs...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(jobs) { job in
                            JobRow(
                                job: job,
                                isSelected: selectedJobId == job.id,
                                onSelect: {
                                    selectedJobId = job.id
                                    Task {
                                        await service.loadLogs(runId: run?.id ?? "", jobId: job.id)
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}
