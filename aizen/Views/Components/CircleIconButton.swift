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
        var content = Image(systemName: systemName)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(foreground)

        if let frameSize = frameSize {
            content = content.frame(width: frameSize, height: frameSize)
        }

        if let padding = padding {
            content = content.padding(padding)
        }

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
