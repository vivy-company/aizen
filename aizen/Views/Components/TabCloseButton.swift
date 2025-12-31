//
//  TabCloseButton.swift
//  aizen
//
//  Reusable close button for tab headers with hover feedback
//

import SwiftUI

struct TabCloseButton: View {
    let action: () -> Void
    var size: CGFloat = 10
    var weight: Font.Weight = .medium
    var frameSize: CGFloat = 16
    var primaryColor: Color = .primary
    var secondaryColor: Color = .secondary

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: size, weight: weight))
                .foregroundColor(isHovering ? primaryColor : secondaryColor)
        }
        .buttonStyle(.plain)
        .frame(width: frameSize, height: frameSize)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
