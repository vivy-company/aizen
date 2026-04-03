//
//  WorkflowJobRow.swift
//  aizen
//
//  Job row rendering for workflow run details.
//

import SwiftUI

struct JobRow: View {
    let job: WorkflowJob
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onSelect) {
                HStack(spacing: 8) {
                    if !job.steps.isEmpty {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isExpanded.toggle()
                            }
                        } label: {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .frame(width: 12)
                    } else {
                        Spacer()
                            .frame(width: 12)
                    }

                    jobStatusIcon

                    Text(job.name)
                        .font(.system(size: 12))
                        .lineLimit(1)

                    Spacer()

                    if !job.durationString.isEmpty {
                        Text(job.durationString)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .modifier(JobRowSelectionModifier(isSelected: isSelected))
            }
            .buttonStyle(.plain)

            if isExpanded && !job.steps.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(job.steps) { step in
                        StepRow(step: step)
                    }
                }
                .padding(.leading, 32)
            }
        }
    }

    @ViewBuilder
    private var jobStatusIcon: some View {
        if job.status == .inProgress {
            ProgressView()
                .controlSize(.mini)
                .frame(width: 14, height: 14)
        } else {
            Image(systemName: WorkflowStatusIcon.iconName(status: job.status, conclusion: job.conclusion, fillStyle: .fill))
                .font(.system(size: 12))
                .foregroundStyle(WorkflowStatusIcon.color(status: job.status, conclusion: job.conclusion))
        }
    }
}
