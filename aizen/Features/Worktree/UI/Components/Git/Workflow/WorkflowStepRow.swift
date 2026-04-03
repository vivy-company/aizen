//
//  WorkflowStepRow.swift
//  aizen
//
//  Step row rendering for workflow job details.
//

import SwiftUI

struct StepRow: View {
    let step: WorkflowStep

    var body: some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(GitWindowDividerStyle.color(opacity: 1))
                .frame(width: 1)
                .padding(.vertical, 2)

            stepStatusIcon
                .frame(width: 12)

            Text(step.name)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, 3)
        .padding(.trailing, 12)
    }

    @ViewBuilder
    private var stepStatusIcon: some View {
        if step.status == .inProgress {
            ProgressView()
                .controlSize(.mini)
                .frame(width: 10, height: 10)
        } else {
            Image(systemName: WorkflowStatusIcon.iconName(status: step.status, conclusion: step.conclusion, fillStyle: .outline))
                .font(.system(size: 9))
                .foregroundStyle(WorkflowStatusIcon.color(status: step.status, conclusion: step.conclusion))
        }
    }
}
