//
//  CompanionDivider.swift
//  aizen
//
//  Resizable divider for companion panel
//

import AppKit
import SwiftUI

struct CompanionDivider: View {
    @Binding var panelWidth: Double
    let minWidth: CGFloat
    let maxWidth: CGFloat
    let containerWidth: CGFloat
    let coordinateSpace: String
    var side: CompanionSide = .right
    @Binding var isDragging: Bool
    var onDragEnd: (() -> Void)?

    @AppStorage("terminalThemeName") private var terminalThemeName = "Aizen Dark"
    @State private var didPushCursor = false
    @State private var cachedDividerColor: Color = Color(
        nsColor: GhosttyThemeParser.loadDividerColor(named: "Aizen Dark")
    )
    private let lineWidth: CGFloat = 1
    private let hitWidth: CGFloat = 14

    var body: some View {
        ZStack {
            Rectangle()
                .fill(cachedDividerColor)
                .frame(width: lineWidth)
        }
        .frame(width: hitWidth)
        .contentShape(Rectangle())
        .padding(.horizontal, -(hitWidth - lineWidth) / 2)
        .onHover { hovering in
            if hovering && !didPushCursor {
                NSCursor.resizeLeftRight.push()
                didPushCursor = true
            } else if !hovering && didPushCursor {
                NSCursor.pop()
                didPushCursor = false
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .named(coordinateSpace))
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                    }

                    let locationX = value.location.x
                    let newWidth = side == .left ? locationX : containerWidth - locationX
                    let resolvedMaxWidth = max(maxWidth, minWidth)
                    let clampedWidth = min(max(newWidth, minWidth), resolvedMaxWidth)

                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        panelWidth = Double(clampedWidth)
                    }
                }
                .onEnded { _ in
                    isDragging = false
                    onDragEnd?()
                }
        )
            .onAppear {
                cachedDividerColor = Color(nsColor: GhosttyThemeParser.loadDividerColor(named: terminalThemeName))
            }
            .onChange(of: terminalThemeName) { _, _ in
                cachedDividerColor = Color(nsColor: GhosttyThemeParser.loadDividerColor(named: terminalThemeName))
            }
            .onDisappear {
                if didPushCursor {
                    NSCursor.pop()
                    didPushCursor = false
                }
                if isDragging {
                    isDragging = false
                }
            }
    }
}

#Preview {
    HStack(spacing: 0) {
        Color.blue.opacity(0.2)
        CompanionDivider(
            panelWidth: .constant(400),
            minWidth: 250,
            maxWidth: 700,
            containerWidth: 1000,
            coordinateSpace: "preview",
            side: .right,
            isDragging: .constant(false)
        )
        Color.green.opacity(0.2)
            .frame(width: 400)
    }
    .frame(width: 800, height: 400)
}
