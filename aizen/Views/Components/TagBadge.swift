//
//  TagBadge.swift
//  aizen
//
//  Reusable colored badge for short tags
//

import SwiftUI

struct TagBadge: View {
    let text: String
    let color: Color
    var cornerRadius: CGFloat = 4
    var font: Font = .caption2
    var fontWeight: Font.Weight? = nil
    var horizontalPadding: CGFloat = 6
    var verticalPadding: CGFloat = 2
    var backgroundOpacity: Double = 0.15
    var textColor: Color? = nil
    var iconSystemName: String? = nil
    var iconSize: CGFloat? = nil
    var spacing: CGFloat = 4

    var body: some View {
        var label = Text(text).font(font)
        if let fontWeight = fontWeight {
            label = label.fontWeight(fontWeight)
        }
        let resolvedTextColor = textColor ?? color

        return HStack(spacing: spacing) {
            if let iconSystemName = iconSystemName {
                let image = Image(systemName: iconSystemName)
                if let iconSize = iconSize {
                    image
                        .font(.system(size: iconSize))
                        .foregroundStyle(resolvedTextColor)
                } else {
                    image
                        .font(font)
                        .foregroundStyle(resolvedTextColor)
                }
            }

            label
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(color.opacity(backgroundOpacity))
        .foregroundColor(resolvedTextColor)
        .cornerRadius(cornerRadius)
    }
}
