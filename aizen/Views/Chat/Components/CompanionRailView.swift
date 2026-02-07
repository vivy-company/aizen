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
        CGSize(width: 16, height: 34)
    }

    private var expandedSize: CGSize {
        let buttonHeight: CGFloat = 36
        let spacing: CGFloat = 6
        let verticalPadding: CGFloat = 16
        let rows = CGFloat(availablePanels.count)
        let totalSpacing = spacing * CGFloat(max(availablePanels.count - 1, 0))
        return CGSize(width: 52, height: rows * buttonHeight + totalSpacing + verticalPadding)
    }

    private var triggerStrokeColor: Color {
        colorScheme == .dark ? .white.opacity(0.10) : .black.opacity(0.07)
    }

    private var pickerStrokeColor: Color {
        colorScheme == .dark ? .white.opacity(0.12) : .black.opacity(0.08)
    }

    private var railShadowOpacity: Double {
        isHovered ? (colorScheme == .dark ? 0.10 : 0.06) : 0
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
            ForEach(0..<3, id: \.self) { _ in
                Circle()
                    .fill(Color.primary.opacity(0.26))
                    .frame(width: 4, height: 4)
            }
        }
    }

    private var pickerOverlay: some View {
        VStack(spacing: 6) {
            ForEach(availablePanels) { panel in
                PanelPickerButton(panel: panel, onTap: { onSelect(panel) })
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var railSurface: some View {
        let shape = Capsule()

        Group {
            if #available(macOS 26.0, *) {
                shape
                    .fill(.white.opacity(0.001))
                    .glassEffect(.clear, in: shape)
            } else {
                shape
                    .fill(.ultraThinMaterial)
            }
        }
        .overlay {
            Capsule()
                .strokeBorder(isHovered ? pickerStrokeColor : triggerStrokeColor, lineWidth: 0.55)
        }
        .shadow(color: .black.opacity(railShadowOpacity), radius: isHovered ? 8 : 0, x: 0, y: isHovered ? 3 : 0)
        .animation(railAnimation, value: isHovered)
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
                    buttonBackground
                }
                .foregroundStyle(.primary)
                .scaleEffect(isHovered ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .help(panel.label)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }

    @ViewBuilder
    private var buttonBackground: some View {
        let shape = Circle()

        if #available(macOS 26.0, *) {
            shape
                .fill(.clear)
                .glassEffect(isHovered ? .clear.interactive() : .clear, in: shape)
        } else {
            shape
                .fill(isHovered ? Color.primary.opacity(0.06) : .clear)
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
