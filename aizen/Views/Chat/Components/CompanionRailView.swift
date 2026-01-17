//
//  CompanionRailView.swift
//  aizen
//
//  Hover-activated overlay for companion panel selection
//

import SwiftUI

enum CompanionSide {
    case left
    case right
}

struct CompanionRailView: View {
    let side: CompanionSide
    let availablePanels: [CompanionPanel]
    let onSelect: (CompanionPanel) -> Void

    @State private var isHovering = false

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 24)
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovering = hovering
                }
            }
            .overlay(alignment: side == .left ? .leading : .trailing) {
                if isHovering {
                    pickerOverlay
                        .padding(side == .left ? .leading : .trailing, 8)
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: side == .left ? .leading : .trailing)))
                } else {
                    edgeHint
                        .transition(.opacity)
                }
            }
    }

    private var edgeHint: some View {
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                Circle()
                    .fill(Color.primary.opacity(0.15))
                    .frame(width: 4, height: 4)
            }
        }
        .padding(side == .left ? .leading : .trailing, 6)
    }

    private var pickerOverlay: some View {
        VStack(spacing: 6) {
            ForEach(availablePanels) { panel in
                PanelPickerButton(panel: panel, onTap: { onSelect(panel) })
            }
        }
        .padding(8)
        .background {
            Capsule()
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        }
        .overlay {
            Capsule()
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 0.5)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

private struct PanelPickerButton: View {
    let panel: CompanionPanel
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            Image(systemName: panel.icon)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 36, height: 36)
                .background {
                    Circle()
                        .fill(isHovered ? Color.primary.opacity(0.08) : .clear)
                }
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .help(panel.label)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.2)
        HStack {
            CompanionRailView(side: .left, availablePanels: CompanionPanel.allCases, onSelect: { _ in })
            Spacer()
            CompanionRailView(side: .right, availablePanels: CompanionPanel.allCases, onSelect: { _ in })
        }
    }
    .frame(width: 400, height: 300)
}
