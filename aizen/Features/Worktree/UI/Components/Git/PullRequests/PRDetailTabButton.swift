import SwiftUI

struct PRDetailTabButton: View {
    let tab: PullRequestDetailPane.DetailTab
    let isSelected: Bool
    let badge: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(tab.rawValue)
                    .foregroundStyle(isSelected ? .primary : .secondary)

                if let count = badge {
                    Text("(\(count))")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 11, weight: isSelected ? .medium : .regular))
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(isSelected ? Color(NSColor.textBackgroundColor) : Color.clear)
            .overlay(
                Rectangle()
                    .fill(isSelected ? Color.accentColor : Color.clear)
                    .frame(height: 2),
                alignment: .top
            )
            .overlay(
                Rectangle()
                    .fill(GitWindowDividerStyle.color(opacity: 1))
                    .frame(width: 1),
                alignment: .trailing
            )
        }
        .buttonStyle(.plain)
    }
}
