//
//  SelectableRowModifier.swift
//  aizen
//
//  Shared row background treatment for selectable list items
//

import SwiftUI

struct SelectableRowModifier: ViewModifier {
    let isSelected: Bool
    let isHovered: Bool
    var showsIdleBackground: Bool = true
    var cornerRadius: CGFloat = 8

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(macOS 26.0, *) {
            content
                .background {
                    if isSelected {
                        GlassEffectContainer {
                            shape
                                .fill(.white.opacity(0.001))
                                .glassEffect(.regular.tint(.accentColor.opacity(0.24)).interactive(), in: shape)
                            shape
                                .fill(Color.accentColor.opacity(0.10))
                        }
                    } else if isHovered {
                        shape
                            .fill(Color.white.opacity(0.05))
                    } else if showsIdleBackground {
                        shape
                            .fill(Color.white.opacity(0.02))
                    }
                }
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            isSelected
                                ? Color(nsColor: .selectedContentBackgroundColor)
                                : (isHovered ? Color.white.opacity(0.06) : (showsIdleBackground ? Color.white.opacity(0.02) : .clear))
                        )
                )
        }
    }
}
