//
//  RemovableChip.swift
//  aizen
//
//  Capsule chip with a label and remove action
//

import SwiftUI

struct RemovableChip: View {
    let text: String
    let onRemove: () -> Void
    var font: Font = .caption
    var textColor: Color = .primary
    var backgroundColor: Color = .accentColor
    var backgroundOpacity: Double = 0.2
    var horizontalPadding: CGFloat = 8
    var verticalPadding: CGFloat = 4
    var spacing: CGFloat = 4
    var closeSize: CGFloat = 8
    var closeWeight: Font.Weight = .bold

    var body: some View {
        HStack(spacing: spacing) {
            Text(text)
                .font(font)
                .foregroundStyle(textColor)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: closeSize, weight: closeWeight))
                    .foregroundStyle(textColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(backgroundColor.opacity(backgroundOpacity))
        .clipShape(Capsule())
    }
}
