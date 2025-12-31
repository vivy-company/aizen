//  AgentPlanInlineView.swift
//  aizen
//
//  Compact chip view for displaying agent plan progress
//

import SwiftUI

struct AgentPlanInlineView: View {
    let plan: Plan
    @State private var showingSheet = false

    private var completedCount: Int {
        plan.entries.filter { $0.status == .completed }.count
    }

    private var totalCount: Int {
        plan.entries.count
    }

    private var isAllDone: Bool {
        completedCount == totalCount
    }

    private var currentEntry: PlanEntry? {
        plan.entries.first { $0.status == .inProgress }
            ?? plan.entries.first { $0.status == .pending }
    }

    var body: some View {
        if !isAllDone {
            Button {
                showingSheet = true
            } label: {
                HStack(spacing: 6) {
                    // Animated dot indicator
                    Circle()
                        .fill(currentEntry?.status == .inProgress ? Color.blue : Color.secondary)
                        .frame(width: 6, height: 6)
                        .overlay {
                            if currentEntry?.status == .inProgress {
                                Circle()
                                    .stroke(Color.blue.opacity(0.4), lineWidth: 2)
                                    .scaleEffect(1.5)
                            }
                        }

                    // Current task text
                    if let entry = currentEntry {
                        Text(entry.activeForm ?? entry.content)
                            .font(.system(size: 11))
                            .lineLimit(1)
                    }

                    // Progress counter
                    PillBadge(
                        text: "\(completedCount)/\(totalCount)",
                        color: .secondary,
                        textColor: .secondary,
                        font: .system(size: 10, weight: .medium),
                        horizontalPadding: 6,
                        verticalPadding: 2,
                        backgroundOpacity: 0.25
                    )
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showingSheet) {
                AgentPlanSheet(plan: plan)
            }
        }
    }
}

struct AgentPlanSheet: View {
    let plan: Plan
    @Environment(\.dismiss) private var dismiss

    private var completedCount: Int {
        plan.entries.filter { $0.status == .completed }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            DetailHeaderBar(showsBackground: false) {
                Text("Agent Plan")
                    .font(.headline)
            } trailing: {
                HStack(spacing: 12) {
                    Text("\(completedCount)/\(plan.entries.count) completed")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    DetailCloseButton { dismiss() }
                }
            }

            Divider()

            // Plan entries
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(plan.entries.enumerated()), id: \.offset) { index, entry in
                        PlanEntryRow(entry: entry, index: index + 1)
                    }
                }
                .padding()
            }
        }
        .frame(width: 400, height: 300)
    }
}

struct PlanEntryRow: View {
    let entry: PlanEntry
    var index: Int = 0

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Status icon
            Group {
                switch entry.status {
                case .completed:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .inProgress:
                    Image(systemName: "circle.dotted")
                        .foregroundStyle(.blue)
                case .pending:
                    Image(systemName: "circle")
                        .foregroundStyle(.secondary)
                case .cancelled:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }
            .font(.system(size: 14))
            .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.content)
                    .font(.system(size: 13))
                    .foregroundStyle(entry.status == .completed ? .secondary : .primary)
                    .strikethrough(entry.status == .completed)

                if let activeForm = entry.activeForm, entry.status == .inProgress {
                    Text(activeForm)
                        .font(.system(size: 11))
                        .foregroundStyle(.blue)
                        .italic()
                }
            }
        }
        .padding(.vertical, 4)
    }
}
