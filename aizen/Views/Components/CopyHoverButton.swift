//
//  CopyHoverButton.swift
//  aizen
//
//  Reusable copy button with hover label and confirmation state
//

import SwiftUI

struct CopyHoverButton: View {
    let helpText: String
    let isHovered: Bool
    var label: String = "Copy"
    var copiedLabel: String = "Copied"
    var iconSize: CGFloat = 10
    var font: Font = .system(size: 10)
    var cornerRadius: CGFloat = 4
    var horizontalPadding: CGFloat = 6
    var verticalPadding: CGFloat = 3
    var hoverBackgroundOpacity: Double = 0.15
    var confirmationDuration: Double = 1.5
    let action: () -> Void

    @State private var showConfirmation = false

    var body: some View {
        Button(action: handleCopy) {
            HStack(spacing: 4) {
                Image(systemName: showConfirmation ? "checkmark" : "doc.on.doc")
                    .font(.system(size: iconSize))
                if isHovered {
                    Text(showConfirmation ? copiedLabel : label)
                        .font(font)
                }
            }
            .foregroundStyle(showConfirmation ? .green : .secondary)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.secondary.opacity(isHovered ? hoverBackgroundOpacity : 0))
            )
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    private func handleCopy() {
        action()

        withAnimation {
            showConfirmation = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + confirmationDuration) {
            withAnimation {
                showConfirmation = false
            }
        }
    }
}
