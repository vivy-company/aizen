//
//  AgentPlanInlineView.swift
//  aizen
//
//  Inline view for displaying agent plan above input bar
//

import SwiftUI

struct AgentPlanInlineView: View {
    let plan: Plan
    @State private var isCollapsed: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with collapse toggle
            HStack {
                Image(systemName: "list.bullet.clipboard")
                    .font(.system(size: 11))
                Text("Agent Plan")
                    .font(.system(size: 11, weight: .semibold))

                Spacer()

                // Progress indicator
                Text(progressText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isCollapsed.toggle()
                    }
                } label: {
                    Image(systemName: isCollapsed ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.secondary)

            if !isCollapsed {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(plan.entries.enumerated()), id: \.offset) { _, entry in
                            PlanEntryRow(entry: entry)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var progressText: String {
        let completed = plan.entries.filter { $0.status == .completed }.count
        return "\(completed)/\(plan.entries.count)"
    }
}

struct PlanEntryRow: View {
    let entry: PlanEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.content)
                    .font(.system(size: 12))
                    .foregroundStyle(entry.status == .completed ? .secondary : .primary)
                    .strikethrough(entry.status == .completed)

                if let activeForm = entry.activeForm, entry.status == .inProgress {
                    Text(activeForm)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
        }
    }

    private var statusColor: Color {
        switch entry.status {
        case .pending: return .secondary
        case .inProgress: return .blue
        case .completed: return .green
        case .cancelled: return .red
        }
    }
}
