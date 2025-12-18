//
//  ToolCallGroupView.swift
//  aizen
//
//  Expandable view for grouped tool calls from a completed agent turn
//

import SwiftUI

struct ToolCallGroupView: View {
    let group: ToolCallGroup
    var currentIterationId: String? = nil
    var agentSession: AgentSession? = nil
    var onOpenInEditor: ((String) -> Void)? = nil
    var childToolCallsProvider: (String) -> [ToolCall] = { _ in [] }

    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            headerView

            if isExpanded {
                expandedContent
            }
        }
        .background(backgroundColor)
        .cornerRadius(3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Header

    private var headerView: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }) {
            HStack(spacing: 8) {
                // Status indicator
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)

                // Tool kind icons (up to 4)
                toolKindIcons

                // Summary text
                Text(group.summaryText)
                    .font(.system(size: 11))
                    .foregroundColor(.primary)

                Spacer(minLength: 6)

                // Expand indicator
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tool Kind Icons

    @ViewBuilder
    private var toolKindIcons: some View {
        let kinds = Array(group.toolKinds.prefix(4))
        HStack(spacing: 4) {
            ForEach(kinds.sorted(by: { $0.rawValue < $1.rawValue }), id: \.rawValue) { kind in
                Image(systemName: kind.symbolName)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 12, height: 12)
            }
            if group.toolKinds.count > 4 {
                Text("+\(group.toolKinds.count - 4)")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(group.toolCalls) { toolCall in
                ToolCallView(
                    toolCall: toolCall,
                    currentIterationId: currentIterationId,
                    agentSession: agentSession,
                    onOpenInEditor: onOpenInEditor,
                    childToolCalls: childToolCallsProvider(toolCall.toolCallId)
                )
                .padding(.leading, 8)
            }
        }
        .padding(.top, 4)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Status

    private var statusColor: Color {
        if group.hasFailed { return .red }
        if group.isInProgress { return .blue }
        return .green
    }

    private var backgroundColor: Color {
        Color(.controlBackgroundColor).opacity(0.2)
    }
}
