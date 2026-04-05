//
//  WorkflowRunStatusIconView.swift
//  aizen
//
//  Shared status icon for workflow run cells
//

import SwiftUI

struct WorkflowRunStatusIconView: View {
    let run: WorkflowRun
    var iconSize: CGFloat = 12
    var progressFrame: CGFloat = 14
    var progressStyle: WorkflowRunProgressStyle = .mini
    var colorOverride: Color? = nil

    var body: some View {
        if run.isInProgress {
            progressView
        } else {
            Image(systemName: WorkflowStatusIcon.iconName(status: run.status, conclusion: run.conclusion, fillStyle: .fill))
                .font(.system(size: iconSize))
                .foregroundStyle(colorOverride ?? statusColor)
        }
    }
}
