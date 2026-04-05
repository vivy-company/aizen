//
//  WorkflowRunStatusIconView+Presentation.swift
//  aizen
//
//  Created by OpenAI Codex on 06.04.26.
//

import SwiftUI

extension WorkflowRunStatusIconView {
    @ViewBuilder
    var progressView: some View {
        switch progressStyle {
        case .mini:
            ProgressView()
                .controlSize(.mini)
                .tint(colorOverride ?? statusColor)
                .frame(width: progressFrame, height: progressFrame)
        case .scaled(let scale):
            ScaledProgressView(size: progressFrame, scale: scale)
                .tint(colorOverride ?? statusColor)
        }
    }

    var statusColor: Color {
        WorkflowStatusIcon.color(status: run.status, conclusion: run.conclusion)
    }
}
