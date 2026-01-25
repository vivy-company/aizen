//
//  HoverActionButton.swift
//  aizen
//
//  Small action button that appears on hover
//

import SwiftUI

struct HoverActionButton: View {
    let icon: String
    let help: String
    let action: () -> Void
    var size: CGFloat = 18
    var iconSize: CGFloat = 10
    
    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(isHovering ? .primary : .secondary)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(backgroundColor)
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
    }
    
    private var backgroundColor: Color {
        if isHovering {
            return colorScheme == .dark
                ? Color.white.opacity(0.12)
                : Color.black.opacity(0.08)
        }
        return .clear
    }
}

struct HoverActionBar: View {
    let actions: [HoverAction]
    var spacing: CGFloat = 4
    var showOnHover: Bool = true
    
    @Binding var isParentHovering: Bool
    
    struct HoverAction: Identifiable {
        let id = UUID()
        let icon: String
        let help: String
        let action: () -> Void
    }
    
    var body: some View {
        HStack(spacing: spacing) {
            ForEach(actions) { action in
                HoverActionButton(
                    icon: action.icon,
                    help: action.help,
                    action: action.action
                )
            }
        }
        .opacity(showOnHover ? (isParentHovering ? 1 : 0) : 1)
        .animation(.easeInOut(duration: 0.15), value: isParentHovering)
    }
}

extension HoverActionBar {
    init(actions: [HoverAction], spacing: CGFloat = 4, isHovering: Bool) {
        self.actions = actions
        self.spacing = spacing
        self.showOnHover = true
        self._isParentHovering = .constant(isHovering)
    }
}

// MARK: - Preview

#Preview("Hover Action Buttons") {
    VStack(spacing: 20) {
        HStack(spacing: 8) {
            Text("Hover over buttons:")
            
            HoverActionButton(icon: "doc.on.doc", help: "Copy") {
                print("Copy")
            }
            
            HoverActionButton(icon: "arrow.up.forward.square", help: "Open") {
                print("Open")
            }
            
            HoverActionButton(icon: "info.circle", help: "Info") {
                print("Info")
            }
        }
        
        HStack(spacing: 8) {
            Text("Action bar (always visible):")
            
            HoverActionBar(
                actions: [
                    .init(icon: "doc.on.doc", help: "Copy", action: {}),
                    .init(icon: "arrow.up.forward.square", help: "Open", action: {}),
                    .init(icon: "trash", help: "Delete", action: {})
                ],
                isHovering: true
            )
        }
    }
    .padding()
    .frame(width: 400, height: 200)
}
