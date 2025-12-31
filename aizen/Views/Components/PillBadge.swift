//
//  PillBadge.swift
//  aizen
//
//  Reusable capsule badge for short labels
//

import SwiftUI

struct PillBadge: View {
    let text: String
    var color: Color = .secondary
    var textColor: Color? = nil
    var font: Font = .caption2
    var fontWeight: Font.Weight? = nil
    var horizontalPadding: CGFloat = 6
    var verticalPadding: CGFloat = 2
    var backgroundOpacity: Double = 0.18
    var lineLimit: Int? = nil
    var minimumScaleFactor: CGFloat? = nil

    var body: some View {
        var label = Text(text).font(font)
        if let fontWeight = fontWeight {
            label = label.fontWeight(fontWeight)
        }
        if let lineLimit = lineLimit {
            label = label.lineLimit(lineLimit)
        }
        if let minimumScaleFactor = minimumScaleFactor {
            label = label.minimumScaleFactor(minimumScaleFactor)
        }

        let resolvedTextColor = textColor ?? (backgroundOpacity >= 0.9 ? .white : color)

        return label
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .foregroundStyle(resolvedTextColor)
            .background(Capsule().fill(color.opacity(backgroundOpacity)))
    }
}
