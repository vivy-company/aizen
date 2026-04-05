import SwiftUI

extension WorkflowRunsListView {
    var loadingState: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)

            Text("Loading runs...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 12)
    }

    var emptyState: some View {
        HStack {
            Image(systemName: "clock.badge.questionmark")
                .foregroundStyle(.tertiary)

            Text("No runs found for this branch")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 12)
    }
}
