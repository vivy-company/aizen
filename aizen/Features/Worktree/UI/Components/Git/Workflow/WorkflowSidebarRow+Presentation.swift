import SwiftUI

extension WorkflowSidebarRow {
    var selectedHighlightColor: Color {
        controlActiveState == .key ? Color(nsColor: .systemRed) : Color(nsColor: .systemRed).opacity(0.78)
    }

    var selectionFillColor: Color {
        let base = NSColor.unemphasizedSelectedContentBackgroundColor
        let alpha: Double = controlActiveState == .key ? 0.26 : 0.18
        return Color(nsColor: base).opacity(alpha)
    }

    var triggerButtonIcon: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isButtonHovered ? .white : .secondary)
            .frame(width: 34, height: 34)
            .background(
                Circle()
                    .fill(isButtonHovered ? Color.accentColor : Color.white.opacity(0.05))
            )
    }

    var backgroundFill: some View {
        Group {
            if isSelected {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selectionFillColor)
            } else if isHovered {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06))
            } else {
                Color.clear
            }
        }
    }
}
