//  AgentPlanInlineView.swift
//  aizen
//
//  Inline plan card for displaying agent plan progress
//

import ACP
import SwiftUI

struct AgentPlanInlineView: View {
    let plan: Plan
    @State private var showingSheet = false
    @State private var isExpanded = false

    private var completedCount: Int {
        plan.entries.filter { $0.status == .completed }.count
    }

    private var totalCount: Int {
        plan.entries.count
    }

    private var isAllDone: Bool {
        totalCount > 0 && completedCount == totalCount
    }

    private var previewEntries: [PlanEntry] {
        if isExpanded {
            return plan.entries
        }
        return Array(plan.entries.prefix(5))
    }

    private var hasMoreEntries: Bool {
        totalCount > previewEntries.count
    }

    private var progressLabel: String {
        "\(completedCount)/\(totalCount) completed"
    }

    private var progressColor: Color {
        if plan.entries.contains(where: { $0.status == .inProgress }) {
            return .blue
        }
        return .secondary
    }

    var body: some View {
        if !plan.entries.isEmpty && !isAllDone {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 10) {
                    Text("Plan")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 8)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(progressColor)
                            .frame(width: 8, height: 8)
                        Text(progressLabel)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Label(isExpanded ? "Collapse" : "Expand", systemImage: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.16), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        showingSheet = true
                    } label: {
                        Label("Open sheet", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.16), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                ZStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(previewEntries.enumerated()), id: \.offset) { index, entry in
                            PlanEntryRow(entry: entry, index: index + 1)
                        }

                        if hasMoreEntries {
                            Text("+\(totalCount - previewEntries.count) more")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if hasMoreEntries {
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color(nsColor: .windowBackgroundColor).opacity(0.25),
                                Color(nsColor: .windowBackgroundColor).opacity(0.55)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 54)
                        .allowsHitTesting(false)
                    }
                }
            }
            .padding(16)
            .background { cardBackground }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.separator.opacity(0.3), lineWidth: 0.8)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onTapGesture {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
                    isExpanded.toggle()
                }
            }
            .sheet(isPresented: $showingSheet) {
                AgentPlanSheet(plan: plan)
                    .frame(minWidth: 920, minHeight: 740)
            }
        }
    }

    @ViewBuilder
    private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        if #available(macOS 26.0, *) {
            GlassEffectContainer {
                shape
                    .fill(.white.opacity(0.001))
                    .glassEffect(.regular.interactive(), in: shape)
                shape
                    .fill(.white.opacity(0.03))
            }
        } else {
            shape.fill(.ultraThinMaterial)
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
            DetailHeaderBar(showsBackground: false) {
                Text("Agent Plan")
                    .font(.title3)
                    .fontWeight(.semibold)
            } trailing: {
                HStack(spacing: 12) {
                    Text("\(completedCount)/\(plan.entries.count) completed")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    DetailCloseButton { dismiss() }
                }
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(plan.entries.enumerated()), id: \.offset) { index, entry in
                        PlanEntryRow(entry: entry, index: index + 1)
                    }
                }
                .padding()
            }
        }
        .background(.ultraThinMaterial)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PlanEntryRow: View {
    let entry: PlanEntry
    var index: Int = 0

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
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
                Text(index > 0 ? "\(index). \(entry.content)" : entry.content)
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
