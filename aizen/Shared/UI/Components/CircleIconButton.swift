//
//  CircleIconButton.swift
//  aizen
//
//  Reusable circular icon button
//

import SwiftUI

struct CircleIconButton: View {
    let systemName: String
    let action: () -> Void
    var size: CGFloat = 12
    var weight: Font.Weight = .semibold
    var foreground: Color = .secondary
    var backgroundColor: Color = Color(nsColor: .separatorColor)
    var backgroundOpacity: Double = 0.5
    var frameSize: CGFloat? = nil
    var padding: CGFloat? = nil

    var body: some View {
        let content = Image(systemName: systemName)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(foreground)
            .modifier(OptionalFrameModifier(size: frameSize))
            .modifier(OptionalPaddingModifier(padding: padding))

        return Button(action: action) {
            content
                .background(
                    Circle()
                        .fill(backgroundColor.opacity(backgroundOpacity))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct OptionalFrameModifier: ViewModifier {
    let size: CGFloat?

    func body(content: Content) -> some View {
        if let size {
            content.frame(width: size, height: size)
        } else {
            content
        }
    }
}

private struct OptionalPaddingModifier: ViewModifier {
    let padding: CGFloat?

    func body(content: Content) -> some View {
        if let padding {
            content.padding(padding)
        } else {
            content
        }
    }
}
