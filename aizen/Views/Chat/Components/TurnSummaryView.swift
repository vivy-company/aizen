//
//  TurnSummaryView.swift
//  aizen
//
//  Summary view shown at the end of a completed agent turn
//

import SwiftUI

struct TurnSummaryView: View {
    let summary: TurnSummary
    var onOpenInEditor: ((String) -> Void)?
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var separatorColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
    }
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color(white: 0.08) : Color(white: 0.96)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Rectangle()
                    .fill(separatorColor)
                    .frame(height: 1)
                
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                    
                    Text("Turn completed")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                
                Rectangle()
                    .fill(separatorColor)
                    .frame(height: 1)
            }
            .padding(.vertical, 8)
            
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 9))
                    Text("\(summary.toolCallCount)")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(backgroundColor)
                )
                
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 9))
                    Text(summary.formattedDuration)
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(backgroundColor)
                )
                
                Spacer()

                if !summary.fileChanges.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(summary.fileChanges.prefix(3)) { change in
                            TurnFileChip(change: change, onOpenInEditor: onOpenInEditor)
                        }

                        if summary.fileChanges.count > 3 {
                            Text("+\(summary.fileChanges.count - 3) more")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Turn File Chip (Compact)

struct TurnFileChip: View {
    let change: FileChangeSummary
    var onOpenInEditor: ((String) -> Void)?

    @State private var isHovering = false

    var body: some View {
        Button {
            onOpenInEditor?(change.path)
        } label: {
            HStack(spacing: 3) {
                // Filename
                Text(change.filename)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                // Line changes
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
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(isHovering ? 0.08 : 0.04))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .help(change.path)
    }
}
