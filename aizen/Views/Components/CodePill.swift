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

    var body: some View {
        label
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(backgroundColor)
            .cornerRadius(cornerRadius)
    }

    @ViewBuilder
    private var label: some View {
        let base = Text(text)
            .font(font)
            .foregroundStyle(textColor)

        if selectable {
            base.textSelection(.enabled)
        } else {
            base
        }
    }
}
