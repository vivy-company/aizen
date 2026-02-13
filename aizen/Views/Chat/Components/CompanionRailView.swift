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
    @Environment(\.colorScheme) private var colorScheme

    let side: CompanionSide
    let availablePanels: [CompanionPanel]
    let onSelect: (CompanionPanel) -> Void

    @State private var isHovered = false

    private var collapsedSize: CGSize {
        CGSize(width: 10, height: 24)
    }

    private var expandedSize: CGSize {
        let buttonHeight: CGFloat = 34
        let spacing: CGFloat = 4
        let verticalPadding: CGFloat = 16
        let rows = CGFloat(availablePanels.count)
        let totalSpacing = spacing * CGFloat(max(availablePanels.count - 1, 0))
        return CGSize(width: 50, height: rows * buttonHeight + totalSpacing + verticalPadding)
    }

    private var triggerStrokeColor: Color {
        colorScheme == .dark ? .white.opacity(0.10) : .black.opacity(0.07)
    }

    private var pickerStrokeColor: Color {
        colorScheme == .dark ? .white.opacity(0.16) : .black.opacity(0.09)
    }

    private var railShadowOpacity: Double {
        isHovered ? (colorScheme == .dark ? 0.08 : 0.05) : 0
    }

    private var railAnimation: Animation {
        .spring(response: 0.26, dampingFraction: 0.86)
    }

    var body: some View {
        ZStack {
            railSurface
            edgeHint
                .opacity(isHovered ? 0 : 1)
                .scaleEffect(isHovered ? 0.82 : 1)

            pickerOverlay
                .opacity(isHovered ? 1 : 0)
                .scaleEffect(isHovered ? 1 : 0.94)
                .allowsHitTesting(isHovered)
        }
        .frame(width: isHovered ? expandedSize.width : collapsedSize.width, height: isHovered ? expandedSize.height : collapsedSize.height)
        .contentShape(Capsule())
        .onHover { hovering in
            withAnimation(railAnimation) {
                isHovered = hovering
            }
        }
        .padding(side == .left ? .leading : .trailing, 8)
    }

    private var edgeHint: some View {
        VStack(spacing: 3) {
            ForEach(0..<4, id: \.self) { _ in
                Circle()
                    .fill(Color.primary.opacity(0.26))
                    .frame(width: 5, height: 5)
            }
        }
    }

    private var pickerOverlay: some View {
        VStack(spacing: 4) {
            ForEach(availablePanels) { panel in
                PanelPickerButton(panel: panel, onTap: { onSelect(panel) })
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var railSurface: some View {
        let shape = Capsule()

        Group {
            if #available(macOS 26.0, *) {
                shape
                    .fill(.white.opacity(0.001))
                    .glassEffect(.regular, in: shape)
            } else {
                shape
                    .fill(.ultraThinMaterial)
            }
        }
        .opacity(isHovered ? 1 : 0)
        .overlay {
            Capsule()
                .strokeBorder(isHovered ? pickerStrokeColor : triggerStrokeColor, lineWidth: isHovered ? 0.7 : 0)
        }
        .shadow(color: .black.opacity(railShadowOpacity), radius: isHovered ? 6 : 0, x: 0, y: isHovered ? 2 : 0)
        .animation(railAnimation, value: isHovered)
    }
}

private struct PanelPickerButton: View {
    let panel: CompanionPanel
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: panel.icon)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 34, height: 34)
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
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
