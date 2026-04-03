import ACP
import SwiftUI

extension PlanApprovalPickerView {
    @ViewBuilder
    func optionRow(option: PermissionOption, index: Int) -> some View {
        let isSelected = index == selectedIndex
        Button {
            selectedIndex = index
            submitOption(at: index)
        } label: {
            HStack(spacing: 8) {
                Text("\(index + 1).")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(width: 18, alignment: .trailing)

                Text(option.name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.55) : Color.clear,
                        lineWidth: isSelected ? 1 : 0
                    )
            }
        }
        .buttonStyle(.plain)
        .keyboardShortcut(numberShortcut(for: index), modifiers: [])
    }

    func pickerArrowButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 28, height: 24)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(options.count <= 1)
        .keyboardShortcut(systemName == "arrow.up" ? .upArrow : .downArrow, modifiers: [])
    }

    @ViewBuilder
    var liquidGlassBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        if #available(macOS 26.0, *) {
            GlassEffectContainer {
                shape
                    .fill(.white.opacity(0.001))
                    .glassEffect(.regular, in: shape)
                shape
                    .fill(.white.opacity(0.035))
            }
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }
}
