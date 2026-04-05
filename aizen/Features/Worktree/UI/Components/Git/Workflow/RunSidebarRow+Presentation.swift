//
//  RunSidebarRow+Presentation.swift
//  aizen
//
//  Created by OpenAI Codex on 06.04.26.
//

import AppKit
import SwiftUI

extension RunSidebarRow {
    var selectedHighlightColor: Color {
        controlActiveState == .key ? Color(nsColor: .systemRed) : Color(nsColor: .systemRed).opacity(0.78)
    }

    var selectionFillColor: Color {
        let base = NSColor.unemphasizedSelectedContentBackgroundColor
        let alpha: Double = controlActiveState == .key ? 0.26 : 0.18
        return Color(nsColor: base).opacity(alpha)
    }

    var shortCommit: String {
        String(run.commit.prefix(7))
    }

    var relativeTimestamp: String? {
        if let startedAt = run.startedAt {
            return RelativeDateFormatter.shared.string(from: startedAt)
        }
        if let completedAt = run.completedAt {
            return RelativeDateFormatter.shared.string(from: completedAt)
        }
        return nil
    }

    var statusColor: Color {
        if let conclusion = run.conclusion {
            switch conclusion {
            case .success:
                return .green
            case .failure, .timedOut, .actionRequired:
                return .red
            case .cancelled, .skipped, .neutral:
                return .secondary
            }
        }

        switch run.status {
        case .inProgress, .queued, .pending, .waiting:
            return .orange
        default:
            return .secondary
        }
    }

    @ViewBuilder
    var backgroundFill: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(selectionFillColor)
        } else if isHovered {
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.06))
        } else {
            Color.clear
        }
    }
}
