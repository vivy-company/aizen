import SwiftUI

struct ProjectSearchResultRow<Trailing: View, Background: View>: View {
    let result: ProjectSearchResult
    let isSelected: Bool
    var isHovered: Bool = false
    var iconSize: CGFloat = 16
    var spacing: CGFloat = 10
    var titleFont: Font = .system(size: 13)
    var subtitleFont: Font = .system(size: 11)
    var horizontalPadding: CGFloat = 10
    var verticalPadding: CGFloat = 6
    let trailing: Trailing
    let background: (_ isSelected: Bool, _ isHovered: Bool) -> Background

    init(
        result: ProjectSearchResult,
        isSelected: Bool,
        isHovered: Bool = false,
        iconSize: CGFloat = 16,
        spacing: CGFloat = 10,
        titleFont: Font = .system(size: 13),
        subtitleFont: Font = .system(size: 11),
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
        self.subtitleFont = subtitleFont
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.trailing = trailing()
        self.background = background
    }

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            FileIconView(path: result.path, size: iconSize)
                .frame(width: iconSize, height: iconSize)

            VStack(alignment: .leading, spacing: contentSpacing) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(result.name)
                        .font(titleFont)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let locationBadgeText {
                        Text(locationBadgeText)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(isSelected ? Color.white.opacity(0.08) : Color.white.opacity(0.05))
                            )
                    }
                }

                Text(result.relativePath)
                    .font(subtitleFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let contentSnippet {
                    Text(contentSnippet)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            trailing
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(background(isSelected, isHovered))
        .contentShape(Rectangle())
    }

    private var contentSpacing: CGFloat {
        switch result {
        case .file:
            return 2
        case .content:
            return 4
        }
    }

    private var locationBadgeText: String? {
        guard case .content(let result) = result else { return nil }
        return "L\(result.lineNumber)"
    }

    private var contentSnippet: String? {
        guard case .content(let result) = result else { return nil }

        let snippet = result.lineContent.trimmingCharacters(in: .whitespacesAndNewlines)
        return snippet.isEmpty ? nil : snippet
    }
}
