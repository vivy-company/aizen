//
//  WorkflowRunsListView+Header.swift
//  aizen
//
//  Created by OpenAI Codex on 06.04.26.
//

import SwiftUI

extension WorkflowRunsListView {
    var header: some View {
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
    }
}
