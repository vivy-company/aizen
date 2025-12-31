//
//  MonospaceTextPanel.swift
//  aizen
//
//  Scrollable monospaced text panel with optional empty state and border
//

import SwiftUI

struct MonospaceTextPanel: View {
    let text: String
    var emptyText: String? = nil
    var maxHeight: CGFloat = 200
    var font: Font = .system(size: 11, design: .monospaced)
    var textColor: Color = .primary
    var emptyTextColor: Color = .tertiary
    var backgroundColor: Color = Color(nsColor: .textBackgroundColor)
    var padding: CGFloat = 8
    var allowsSelection: Bool = true
    var showsBorder: Bool = false
    var borderColor: Color = Color.secondary.opacity(0.2)
    var borderWidth: CGFloat = 1
    var cornerRadius: CGFloat = 4

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            let isEmpty = text.isEmpty
            let displayText = isEmpty ? (emptyText ?? "") : text
            let color = isEmpty ? emptyTextColor : textColor

            let label = Text(displayText)
                .font(font)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)

            if allowsSelection {
                label.textSelection(.enabled)
            } else {
                label
            }
        }
        .frame(maxHeight: maxHeight)
        .padding(padding)
        .background(backgroundColor)
        .overlay(
            Group {
                if showsBorder {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(borderColor, lineWidth: borderWidth)
                }
            }
        )
        .cornerRadius(cornerRadius)
    }
}
