//
//  TabContainer.swift
//  aizen
//
//  Shared styling for tab rows
//

import SwiftUI

struct TabContainer<Content: View>: View {
    let isSelected: Bool
    let onSelect: () -> Void
    let content: Content

    var height: CGFloat = 36
    var minWidth: CGFloat = 120
    var maxWidth: CGFloat = 200
    var horizontalPadding: CGFloat = 10
    var showsTopAccent: Bool = true
    var showsTrailingSeparator: Bool = true
    var selectedBackground: Color = Color(nsColor: .textBackgroundColor)
    var background: Color = Color(nsColor: .controlBackgroundColor).opacity(0.3)
    var accentColor: Color = .accentColor
    var separatorColor: Color = Color(nsColor: .separatorColor)

    init(
        isSelected: Bool,
        onSelect: @escaping () -> Void,
        height: CGFloat = 36,
        minWidth: CGFloat = 120,
        maxWidth: CGFloat = 200,
        horizontalPadding: CGFloat = 10,
        showsTopAccent: Bool = true,
        showsTrailingSeparator: Bool = true,
        selectedBackground: Color = Color(nsColor: .textBackgroundColor),
        background: Color = Color(nsColor: .controlBackgroundColor).opacity(0.3),
        accentColor: Color = .accentColor,
        separatorColor: Color = Color(nsColor: .separatorColor),
        @ViewBuilder content: () -> Content
    ) {
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.height = height
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.horizontalPadding = horizontalPadding
        self.showsTopAccent = showsTopAccent
        self.showsTrailingSeparator = showsTrailingSeparator
        self.selectedBackground = selectedBackground
        self.background = background
        self.accentColor = accentColor
        self.separatorColor = separatorColor
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, horizontalPadding)
            .frame(height: height)
            .frame(minWidth: minWidth, maxWidth: maxWidth)
            .background(isSelected ? selectedBackground : background)
            .overlay(
                Group {
                    if showsTopAccent {
                        Rectangle()
                            .fill(isSelected ? accentColor : Color.clear)
                            .frame(height: 2)
                    }
                },
                alignment: .top
            )
            .overlay(
                Group {
                    if showsTrailingSeparator {
                        Rectangle()
                            .fill(separatorColor)
                            .frame(width: 1)
                    }
                },
                alignment: .trailing
            )
            .contentShape(Rectangle())
            .onTapGesture {
                onSelect()
            }
    }
}
