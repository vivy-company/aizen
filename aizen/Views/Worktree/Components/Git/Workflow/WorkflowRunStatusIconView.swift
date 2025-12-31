//
//  WorkflowRunStatusIconView.swift
//  aizen
//
//  Shared status icon for workflow run cells
//

import SwiftUI

enum WorkflowRunProgressStyle {
    case mini
    case scaled(CGFloat)
}

struct WorkflowRunStatusIconView: View {
    let run: WorkflowRun
    var iconSize: CGFloat = 12
    var progressFrame: CGFloat = 14
    var progressStyle: WorkflowRunProgressStyle = .mini

    var body: some View {
        if run.isInProgress {
            progressView
        } else {
            Image(systemName: WorkflowStatusIcon.iconName(status: run.status, conclusion: run.conclusion, fillStyle: .fill))
                .font(.system(size: iconSize))
                .foregroundStyle(statusColor)
        }
    }

    @ViewBuilder
    private var progressView: some View {
        switch progressStyle {
        case .mini:
            ProgressView()
                .controlSize(.mini)
                .frame(width: progressFrame, height: progressFrame)
        case .scaled(let scale):
            ScaledProgressView(size: progressFrame, scale: scale)
        }
    }

    private var statusColor: Color {
        WorkflowStatusIcon.color(status: run.status, conclusion: run.conclusion)
    }
}
