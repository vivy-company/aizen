//
//  WorkflowRunRow+Presentation.swift
//  aizen
//
//  Created by OpenAI Codex on 06.04.26.
//

import AppKit
import SwiftUI

extension WorkflowRunRow {
    var relativeStartedAt: String? {
        guard let startedAt = run.startedAt else { return nil }
        return RelativeDateFormatter.shared.string(from: startedAt)
    }

    var rowBackground: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(isHovered ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor) : Color.clear)
    }
}
