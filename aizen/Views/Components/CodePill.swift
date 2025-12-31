//
//  CodePill.swift
//  aizen
//
//  Monospaced pill for short command hints
//

import SwiftUI

struct CodePill: View {
    let text: String
    var font: Font = .system(.caption, design: .monospaced)
    var textColor: Color = .primary
    var backgroundColor: Color = Color(nsColor: .controlBackgroundColor)
    var cornerRadius: CGFloat = 4
    var horizontalPadding: CGFloat = 6
    var verticalPadding: CGFloat = 6
    var selectable: Bool = false
    var lineLimit: Int? = nil
    var truncationMode: Text.TruncationMode? = nil

    var body: some View {
        label
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(backgroundColor)
            .cornerRadius(cornerRadius)
    }

    private var label: some View {
        Text(text)
            .font(font)
            .foregroundStyle(textColor)
            .modifier(OptionalLineLimitModifier(limit: lineLimit))
            .modifier(OptionalTruncationModeModifier(mode: truncationMode))
            .modifier(OptionalTextSelectionModifier(enabled: selectable))
    }
}

private struct OptionalLineLimitModifier: ViewModifier {
    let limit: Int?

    func body(content: Content) -> some View {
        if let limit {
            content.lineLimit(limit)
        } else {
            content
        }
    }
}

private struct OptionalTruncationModeModifier: ViewModifier {
    let mode: Text.TruncationMode?

    func body(content: Content) -> some View {
        if let mode {
            content.truncationMode(mode)
        } else {
            content
        }
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
