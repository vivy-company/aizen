//
//  TabLabel.swift
//  aizen
//
//  Shared tab label with optional leading/trailing content and close button
//

import SwiftUI

struct TabLabel<Leading: View, Trailing: View>: View {
    let title: String
    let isSelected: Bool
    let onClose: () -> Void
    let leading: Leading
    let trailing: Trailing
    var titleFont: Font = .system(size: 11)
    var spacing: CGFloat = 6

    init(
        title: String,
        isSelected: Bool,
        onClose: @escaping () -> Void,
        titleFont: Font = .system(size: 11),
        spacing: CGFloat = 6,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.isSelected = isSelected
        self.onClose = onClose
        self.titleFont = titleFont
        self.spacing = spacing
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: spacing) {
            leading

            Text(title)
                .font(titleFont)
                .foregroundColor(isSelected ? .primary : .secondary)
                .lineLimit(1)

            trailing

            TabCloseButton(action: onClose)
        }
    }
}
