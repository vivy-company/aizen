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
    var onOpenDetails: ((ToolCall) -> Void)? = nil
    var onOpenInEditor: ((String) -> Void)? = nil
    var childToolCallsProvider: (String) -> [ToolCall] = { _ in [] }

    @State private var isExpanded: Bool = false
    @State private var userExpanded: Bool = false
    @State private var isHovering: Bool = false
    @State private var expandedToolCalls: Set<String> = []
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(ChatSettings.toolCallExpansionModeKey) private var expansionModeSetting = ChatSettings.defaultToolCallExpansionMode

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView

            if isExpanded {
                Divider()
                    .opacity(0.3)
                
                expandedContent
            }
        }
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(borderColor, lineWidth: 0.5)
        )
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 6)
                .fill(statusColor)
                .frame(width: 3)
        }
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.15 : 0.05),
            radius: isHovering ? 3 : 1,
            x: 0,
            y: 1
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu { contextMenuContent }
        .onAppear {
            if !userExpanded {
                isExpanded = computeInitialExpansion()
            }
        }
    }
    
    private func computeInitialExpansion() -> Bool {
        let mode = ToolCallExpansionMode(rawValue: expansionModeSetting) ?? .smart
        
        switch mode {
        case .expanded:
            return true
        case .collapsed:
            return false
        case .smart:
            return false
        }
    }

    // MARK: - Context Menu
    
    @ViewBuilder
    private var contextMenuContent: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded = true
            }
        } label: {
            Label("Expand Group", systemImage: "arrow.down.right.and.arrow.up.left")
        }
        
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded = false
            }
        } label: {
            Label("Collapse Group", systemImage: "arrow.up.left.and.arrow.down.right")
        }
        
        Divider()

        if let output = copyableOutput {
            Button {
                Clipboard.copy(output)
            } label: {
                Label("Copy All Outputs", systemImage: "doc.on.doc")
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
                userExpanded = true
            }
        }) {
            HStack(spacing: 8) {
                statusIndicator
                
                toolKindIcons

                summaryContent
                
                Spacer()
                
                if !isExpanded {
                    collapsedSummary
                }

                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(headerBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private var statusIndicator: some View {
        Group {
            if group.isInProgress {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
            } else {
                Image(systemName: group.hasFailed ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(statusColor)
            }
        }
    }
    
    private var summaryContent: some View {
        Text(richSummaryText)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.primary)
    }
    
    private var collapsedSummary: some View {
        HStack(spacing: 6) {
            if let duration = group.formattedDuration {
                Text(duration)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            
            if group.hasFileChanges {
                fileChangeSummaryBadge
            }
        }
    }
    
    private var fileChangeSummaryBadge: some View {
        let changes = group.fileChanges
        let totalAdded = changes.reduce(0) { $0 + $1.linesAdded }
        let totalRemoved = changes.reduce(0) { $0 + $1.linesRemoved }
        
        return HStack(spacing: 4) {
            Text("\(changes.count) file\(changes.count == 1 ? "" : "s")")
                .font(.system(size: 9))
            
            if totalAdded > 0 || totalRemoved > 0 {
                HStack(spacing: 2) {
                    if totalAdded > 0 {
                        Text("+\(totalAdded)")
                            .foregroundStyle(.green)
                    }
                    if totalRemoved > 0 {
                        Text("-\(totalRemoved)")
                            .foregroundStyle(.red)
                    }
                }
                .font(.system(size: 8, weight: .medium, design: .monospaced))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .clipShape(Capsule())
    }
    
    private var richSummaryText: String {
        let counts = toolKindCounts
        var parts: [String] = []
        
        if let editCount = counts[.edit], editCount > 0 {
            parts.append("\(editCount) edit\(editCount == 1 ? "" : "s")")
        }
        if let readCount = counts[.read], readCount > 0 {
            parts.append("\(readCount) read\(readCount == 1 ? "" : "s")")
        }
        if let executeCount = counts[.execute], executeCount > 0 {
            parts.append("\(executeCount) command\(executeCount == 1 ? "" : "s")")
        }
        if let searchCount = counts[.search], searchCount > 0 {
            parts.append("\(searchCount) search\(searchCount == 1 ? "" : "es")")
        }
        
        let otherCount = group.toolCalls.count - parts.reduce(0) { result, part in
            let num = Int(part.components(separatedBy: " ").first ?? "0") ?? 0
            return result + num
        }
        if otherCount > 0 && parts.isEmpty {
            parts.append("\(group.toolCalls.count) tool call\(group.toolCalls.count == 1 ? "" : "s")")
        } else if otherCount > 0 {
            parts.append("\(otherCount) other")
        }
        
        if parts.isEmpty {
            return "\(group.toolCalls.count) tool call\(group.toolCalls.count == 1 ? "" : "s")"
        }
        
        return parts.joined(separator: ", ")
    }
    
    private var toolKindCounts: [ToolKind: Int] {
        var counts: [ToolKind: Int] = [:]
        for call in group.toolCalls {
            if let kind = call.kind {
                counts[kind, default: 0] += 1
            }
        }
        return counts
    }

    // MARK: - Tool Kind Icons

    @ViewBuilder
    private var toolKindIcons: some View {
        let kinds = Array(group.toolKinds.prefix(4))
        HStack(spacing: 3) {
            ForEach(kinds.sorted(by: { $0.rawValue < $1.rawValue }), id: \.rawValue) { kind in
                Image(systemName: kind.symbolName)
                    .font(.system(size: 9))
                    .foregroundStyle(kind.accentColor.opacity(0.8))
                    .frame(width: 14, height: 14)
                    .background(kind.accentColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            if group.toolKinds.count > 4 {
                Text("+\(group.toolKinds.count - 4)")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(group.toolCalls) { toolCall in
                ToolCallView(
                    toolCall: toolCall,
                    currentIterationId: currentIterationId,
                    onOpenDetails: onOpenDetails,
                    agentSession: agentSession,
                    onOpenInEditor: onOpenInEditor,
                    childToolCalls: childToolCallsProvider(toolCall.toolCallId)
                )
            }
        }
        .padding(10)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Styling

    private var statusColor: Color {
        if group.hasFailed { return ToolStatusPresentation.color(for: .failed) }
        if group.isInProgress { return ToolStatusPresentation.color(for: .inProgress) }
        return ToolStatusPresentation.color(for: .completed)
    }

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(.controlBackgroundColor).opacity(0.25)
            : Color(.controlBackgroundColor).opacity(0.4)
    }
    
    private var headerBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.02)
            : Color.black.opacity(0.01)
    }
    
    private var borderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.08)
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
        .help(change.path)
    }
}
