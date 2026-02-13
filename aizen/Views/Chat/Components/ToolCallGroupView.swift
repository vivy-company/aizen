//
//  ToolCallGroupView.swift
//  aizen
//
//  Expandable view for grouped tool calls from a completed agent turn
//

import ACP
import SwiftUI

struct ToolCallGroupView: View {
    let group: ToolCallGroup
    var currentIterationId: String? = nil
    var agentSession: AgentSession? = nil
    var onOpenDetails: ((ToolCall) -> Void)? = nil
    var onOpenInEditor: ((String) -> Void)? = nil
    var childToolCallsProvider: (String) -> [ToolCall] = { _ in [] }

    @State private var isExpanded: Bool = false
    @State private var expandedExplorationIds: Set<String> = []

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
        .contextMenu {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded = true
                    expandedExplorationIds = allExplorationIds
                }
            } label: {
                Label("Expand All", systemImage: "arrow.down.right.and.arrow.up.left")
            }

            if let output = copyableOutput {
                Button {
                    Clipboard.copy(output)
                } label: {
                    Label("Copy All Outputs", systemImage: "doc.on.doc")
                }
            }
        }
    }

    // MARK: - Copyable Output

    private var copyableOutput: String? {
        var outputs: [String] = []
        for toolCall in group.toolCalls {
            if let output = toolCall.copyableOutputText {
                outputs.append("# \(toolCall.title)\n\(output)")
            }
        }
        let result = outputs.joined(separator: "\n\n---\n\n")
        return result.isEmpty ? nil : result
    }

    // MARK: - Header

    private var headerView: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }) {
            HStack(spacing: 6) {
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

                // Expand indicator (right after content, no spacer)
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tool Kind Icons

    @ViewBuilder
    private var toolKindIcons: some View {
        let sortedKinds = group.toolKinds.sorted(by: { $0.rawValue < $1.rawValue })
        let kinds = Array(sortedKinds.prefix(4))
        HStack(spacing: 4) {
            ForEach(kinds, id: \.rawValue) { kind in
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
            if let singleCluster = singleExplorationCluster {
                ForEach(singleCluster.toolCalls) { toolCall in
                    toolCallRow(toolCall, leadingPadding: 8)
                }
            } else {
                ForEach(group.displayItems) { item in
                    switch item {
                    case .toolCall(let toolCall):
                        toolCallRow(toolCall, leadingPadding: 8)
                    case .exploration(let cluster):
                        explorationClusterRow(cluster)
                    }
                }
            }
        }
        .padding(.top, 4)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func toolCallRow(_ toolCall: ToolCall, leadingPadding: CGFloat) -> some View {
        ToolCallView(
            toolCall: toolCall,
            currentIterationId: currentIterationId,
            onOpenDetails: onOpenDetails,
            agentSession: agentSession,
            onOpenInEditor: onOpenInEditor,
            childToolCalls: childToolCallsProvider(toolCall.toolCallId)
        )
        .padding(.leading, leadingPadding)
    }

    private func explorationClusterRow(_ cluster: ExplorationCluster) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    toggleExplorationCluster(cluster.id)
                }
            }) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(explorationStatusColor(for: cluster))
                        .frame(width: 6, height: 6)

                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(width: 12, height: 12)

                    Text(cluster.summaryText)
                        .font(.system(size: 11))
                        .foregroundColor(.primary)

                    Image(systemName: isExplorationExpanded(cluster.id) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.tertiary)

                    Spacer(minLength: 6)
                }
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)

            if isExplorationExpanded(cluster.id) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(cluster.toolCalls) { toolCall in
                        toolCallRow(toolCall, leadingPadding: 20)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var allExplorationIds: Set<String> {
        Set(group.displayItems.compactMap { item in
            if case .exploration(let cluster) = item {
                return cluster.id
            }
            return nil
        })
    }

    private var singleExplorationCluster: ExplorationCluster? {
        guard group.displayItems.count == 1,
              case .exploration(let cluster) = group.displayItems[0] else {
            return nil
        }
        return cluster
    }

    private func isExplorationExpanded(_ clusterId: String) -> Bool {
        expandedExplorationIds.contains(clusterId)
    }

    private func toggleExplorationCluster(_ clusterId: String) {
        if expandedExplorationIds.contains(clusterId) {
            expandedExplorationIds.remove(clusterId)
        } else {
            expandedExplorationIds.insert(clusterId)
        }
    }

    // MARK: - Status

    private var statusColor: Color {
        if group.hasFailed { return ToolStatusPresentation.color(for: .failed) }
        if group.isInProgress { return ToolStatusPresentation.color(for: .inProgress) }
        return ToolStatusPresentation.color(for: .completed)
    }

    private func explorationStatusColor(for cluster: ExplorationCluster) -> Color {
        if cluster.hasFailed { return ToolStatusPresentation.color(for: .failed) }
        if cluster.isInProgress { return ToolStatusPresentation.color(for: .inProgress) }
        return ToolStatusPresentation.color(for: .completed)
    }

    private var backgroundColor: Color {
        Color(.controlBackgroundColor).opacity(0.2)
    }
}

// MARK: - File Change Chip

struct FileChangeChip: View {
    let change: FileChangeSummary
    var onOpenInEditor: ((String) -> Void)?

    var body: some View {
        Button(action: {
            onOpenInEditor?(change.path)
        }) {
            HStack(spacing: 3) {
                Text(change.filename)
                    .font(.system(size: 9))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if change.linesAdded > 0 || change.linesRemoved > 0 {
                    HStack(spacing: 1) {
                        if change.linesAdded > 0 {
                            Text("+\(change.linesAdded)")
                                .foregroundColor(.green)
                        }
                        if change.linesRemoved > 0 {
                            Text("-\(change.linesRemoved)")
                                .foregroundColor(.red)
                        }
                    }
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color(.controlBackgroundColor).opacity(0.5))
            .cornerRadius(3)
        }
        .buttonStyle(.plain)
    }
}
