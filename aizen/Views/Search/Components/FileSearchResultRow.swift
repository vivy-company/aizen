//
//  FileSearchResultRow.swift
//  aizen
//
//  Created on 2025-11-19.
//

import SwiftUI

struct FileSearchResultRow<Trailing: View, Background: View>: View {
    let result: FileSearchResult
    let isSelected: Bool
    var isHovered: Bool = false
    var iconSize: CGFloat = 16
    var spacing: CGFloat = 10
    var titleFont: Font = .system(size: 13)
    var titleColor: Color = .primary
    var selectedTitleColor: Color? = nil
    var subtitleFont: Font = .system(size: 11)
    var subtitleColor: Color = .secondary
    var selectedSubtitleColor: Color? = nil
    var horizontalPadding: CGFloat = 10
    var verticalPadding: CGFloat = 6
    let trailing: Trailing
    let background: (_ isSelected: Bool, _ isHovered: Bool) -> Background

    init(
        result: FileSearchResult,
        isSelected: Bool,
        isHovered: Bool = false,
        iconSize: CGFloat = 16,
        spacing: CGFloat = 10,
        titleFont: Font = .system(size: 13),
        titleColor: Color = .primary,
        selectedTitleColor: Color? = nil,
        subtitleFont: Font = .system(size: 11),
        subtitleColor: Color = .secondary,
        selectedSubtitleColor: Color? = nil,
        horizontalPadding: CGFloat = 10,
        verticalPadding: CGFloat = 6,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder background: @escaping (_ isSelected: Bool, _ isHovered: Bool) -> Background
    ) {
        self.result = result
        self.isSelected = isSelected
        self.isHovered = isHovered
        self.iconSize = iconSize
        self.spacing = spacing
        self.titleFont = titleFont
        self.titleColor = titleColor
        self.selectedTitleColor = selectedTitleColor
        self.subtitleFont = subtitleFont
        self.subtitleColor = subtitleColor
        self.selectedSubtitleColor = selectedSubtitleColor
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.trailing = trailing()
        self.background = background
    }

    init(
        result: FileSearchResult,
        isSelected: Bool,
        isHovered: Bool = false,
        iconSize: CGFloat = 16,
        spacing: CGFloat = 10,
        titleFont: Font = .system(size: 13),
        titleColor: Color = .primary,
        selectedTitleColor: Color? = nil,
        subtitleFont: Font = .system(size: 11),
        subtitleColor: Color = .secondary,
        selectedSubtitleColor: Color? = nil,
        horizontalPadding: CGFloat = 10,
        verticalPadding: CGFloat = 6,
        @ViewBuilder background: @escaping (_ isSelected: Bool, _ isHovered: Bool) -> Background
    ) where Trailing == EmptyView {
        self.init(
            result: result,
            isSelected: isSelected,
            isHovered: isHovered,
            iconSize: iconSize,
            spacing: spacing,
            titleFont: titleFont,
            titleColor: titleColor,
            selectedTitleColor: selectedTitleColor,
            subtitleFont: subtitleFont,
            subtitleColor: subtitleColor,
            selectedSubtitleColor: selectedSubtitleColor,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding,
            trailing: { EmptyView() },
            background: background
        )
    }

    var body: some View {
        HStack(spacing: spacing) {
            FileIconView(path: result.path, size: iconSize)
                .frame(width: iconSize, height: iconSize)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.name)
                    .font(titleFont)
                    .foregroundStyle(isSelected ? (selectedTitleColor ?? titleColor) : titleColor)

                Text(result.relativePath)
                    .font(subtitleFont)
                    .foregroundStyle(isSelected ? (selectedSubtitleColor ?? subtitleColor) : subtitleColor)
                    .lineLimit(1)
            }

            Spacer()

            trailing
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(background(isSelected, isHovered))
        .contentShape(Rectangle())
    }
}
