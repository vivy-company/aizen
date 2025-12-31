//
//  IconCountPill.swift
//  aizen
//
//  Capsule pill with an icon and count (optional title)
//

import SwiftUI

struct IconCountPill: View {
    let systemImage: String
    let count: Int
    var title: String? = nil
    var color: Color = .accentColor
    var font: Font = .caption2
    var spacing: CGFloat = 4
    var horizontalPadding: CGFloat = 6
    var verticalPadding: CGFloat = 2
    var backgroundOpacity: Double = 0.14
    var showWhenZero: Bool = false
    var fixedSize: Bool = true

    var body: some View {
        Group {
            if showWhenZero || count > 0 {
                HStack(spacing: spacing) {
                    Image(systemName: systemImage)
                    Text(displayText)
                }
                .font(font)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background(color.opacity(backgroundOpacity))
                .foregroundStyle(color)
                .clipShape(Capsule())
                .lineLimit(1)
                .fixedSize(horizontal: fixedSize, vertical: false)
            }
        }
    }

    private var displayText: String {
        if let title {
            return "\(title) \(count)"
        }
        return "\(count)"
    }
}
