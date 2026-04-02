import AppKit
import SwiftUI

struct WorkspaceRow: View {
    let workspace: Workspace
    let isSelected: Bool
    let isHovered: Bool
    let colorFromHex: (String) -> Color
    let onSelect: () -> Void
    let onEdit: () -> Void
    @Environment(\.controlActiveState) private var controlActiveState

    private var selectionFillColor: Color {
        let base = NSColor.unemphasizedSelectedContentBackgroundColor
        let alpha: Double = controlActiveState == .key ? 0.26 : 0.18
        return Color(nsColor: base).opacity(alpha)
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(colorFromHex(workspace.colorHex ?? "#0000FF"))
                .frame(width: 8, height: 8)

            Text(workspace.name ?? String(localized: "workspace.untitled"))
                .font(.body)
                .fontWeight(.semibold)
                .foregroundStyle(isSelected ? Color(nsColor: .selectedTextColor) : Color.primary)
                .lineLimit(1)

            Spacer(minLength: 8)

            if isHovered || isSelected {
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundStyle(isSelected ? Color(nsColor: .selectedTextColor).opacity(0.9) : .secondary)
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
                .help("workspace.edit")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            isSelected
                ? RoundedRectangle(cornerRadius: 6)
                    .fill(selectionFillColor)
                : nil
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}
