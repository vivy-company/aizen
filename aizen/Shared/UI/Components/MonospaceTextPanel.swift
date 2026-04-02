//
//  MonospaceTextPanel.swift
//  aizen
//
//  Scrollable monospaced text panel with optional empty state and border
//

import SwiftUI

struct MonospaceTextPanel: View {
    let text: String
    var attributedText: AttributedString? = nil
    var emptyText: String? = nil
    var maxHeight: CGFloat = 200
    var font: Font = .system(size: 11, design: .monospaced)
    var textColor: Color = .primary
    var emptyTextColor: Color = .secondary
    var backgroundColor: Color = Color(nsColor: .textBackgroundColor)
    var padding: CGFloat = 8
    var allowsSelection: Bool = true
    var showsBorder: Bool = false
    var borderColor: Color = Color.secondary.opacity(0.2)
    var borderWidth: CGFloat = 1
    var cornerRadius: CGFloat = 4

    private var isEmpty: Bool {
        text.isEmpty && attributedText == nil
    }

    private var displayText: String {
        isEmpty ? (emptyText ?? "") : text
    }

    private var resolvedTextColor: Color {
        isEmpty ? emptyTextColor : textColor
    }

    private var baseText: Text {
        if let attributedText {
            return Text(attributedText)
        }
        return Text(displayText)
            .font(font)
            .foregroundColor(resolvedTextColor)
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            baseText
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(OptionalTextSelectionModifier(enabled: allowsSelection))
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

private struct OptionalTextSelectionModifier: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.textSelection(.enabled)
        } else {
            content
        }
    }
}
