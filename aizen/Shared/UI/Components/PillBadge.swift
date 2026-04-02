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
        let resolvedTextColor = textColor ?? (backgroundOpacity >= 0.9 ? .white : color)

        return Text(text)
            .font(font)
            .modifier(OptionalFontWeightModifier(weight: fontWeight))
            .modifier(OptionalLineLimitModifier(limit: lineLimit))
            .modifier(OptionalMinimumScaleFactorModifier(factor: minimumScaleFactor))
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .foregroundStyle(resolvedTextColor)
            .background(Capsule().fill(color.opacity(backgroundOpacity)))
    }
}

private struct OptionalFontWeightModifier: ViewModifier {
    let weight: Font.Weight?

    func body(content: Content) -> some View {
        if let weight {
            content.fontWeight(weight)
        } else {
            content
        }
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

private struct OptionalMinimumScaleFactorModifier: ViewModifier {
    let factor: CGFloat?

    func body(content: Content) -> some View {
        if let factor {
            content.minimumScaleFactor(factor)
        } else {
            content
        }
    }
}
