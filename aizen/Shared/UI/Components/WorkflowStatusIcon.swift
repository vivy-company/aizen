//
//  WorkflowStatusIcon.swift
//  aizen
//
//  Shared mapping for workflow status/conclusion icons and colors
//

import SwiftUI

enum WorkflowStatusIconFillStyle {
    case fill
    case outline
}

enum WorkflowStatusIcon {
    static func iconName(
        status: RunStatus,
        conclusion: RunConclusion?,
        fillStyle: WorkflowStatusIconFillStyle
    ) -> String {
        if let conclusion = conclusion {
            switch (conclusion, fillStyle) {
            case (.success, .fill): return "checkmark.circle.fill"
            case (.failure, .fill): return "xmark.circle.fill"
            case (.cancelled, .fill): return "stop.circle.fill"
            case (.skipped, .fill): return "arrow.right.circle.fill"
            case (.timedOut, .fill): return "clock.badge.exclamationmark.fill"
            case (.actionRequired, .fill): return "exclamationmark.circle.fill"
            case (.neutral, .fill): return "minus.circle.fill"
            case (.success, .outline): return "checkmark"
            case (.failure, .outline): return "xmark"
            case (.cancelled, .outline): return "stop"
            case (.skipped, .outline): return "arrow.right"
            case (.timedOut, .outline): return "clock.badge.exclamationmark"
            case (.actionRequired, .outline): return "exclamationmark.circle"
            case (.neutral, .outline): return "circle"
            }
        }

        switch (status, fillStyle) {
        case (.queued, .fill), (.pending, .fill), (.waiting, .fill): return "clock.fill"
        case (.inProgress, .fill): return "play.circle.fill"
        case (.completed, .fill): return "checkmark.circle.fill"
        case (.requested, .fill): return "hourglass"
        case (.queued, .outline), (.pending, .outline), (.waiting, .outline): return "clock"
        case (.inProgress, .outline): return "play"
        case (.completed, .outline): return "checkmark"
        case (.requested, .outline): return "hourglass"
        }
    }

    static func color(status: RunStatus, conclusion: RunConclusion?) -> Color {
        if let conclusion = conclusion {
            switch conclusion {
            case .success: return .green
            case .failure: return .red
            case .cancelled, .skipped, .neutral: return .gray
            case .timedOut: return .orange
            case .actionRequired: return .yellow
            }
        }
        switch status {
        case .queued, .pending, .waiting, .requested: return .yellow
        case .inProgress: return .yellow
        case .completed: return .green
        }
    }

    static func badgeBackgroundColor(status: RunStatus, conclusion: RunConclusion?) -> Color {
        if let conclusion = conclusion {
            switch conclusion {
            case .success:
                return Color(red: 0.25, green: 0.6, blue: 0.35)
            case .failure:
                return Color(red: 0.7, green: 0.25, blue: 0.25)
            case .timedOut:
                return Color(red: 0.75, green: 0.45, blue: 0.2)
            case .actionRequired:
                return Color(red: 0.7, green: 0.6, blue: 0.2)
            case .cancelled, .skipped, .neutral:
                return Color(nsColor: .controlBackgroundColor)
            }
        }
        switch status {
        case .queued, .pending, .waiting, .requested, .inProgress:
            return Color(red: 0.7, green: 0.6, blue: 0.2)
        case .completed:
            return Color(red: 0.25, green: 0.6, blue: 0.35)
        }
    }
}
