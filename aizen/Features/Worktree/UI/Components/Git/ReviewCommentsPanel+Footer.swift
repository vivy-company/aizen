import SwiftUI

extension ReviewCommentsPanel {
    var footerButtons: some View {
        VStack(spacing: Layout.footerButtonSpacing) {
            footerButton(
                title: "Copy All",
                systemImage: "doc.on.doc",
                iconSize: 12,
                prominent: false,
                action: onCopyAll
            )

            footerButton(
                title: "Send to Agent",
                systemImage: "paperplane.fill",
                iconSize: 11,
                prominent: true,
                action: onSendToAgent
            )
        }
        .padding(.horizontal, Layout.contentPadding)
        .padding(.top, Layout.footerTopPadding)
        .padding(.bottom, Layout.footerBottomPadding)
    }

    func footerButton(
        title: String,
        systemImage: String,
        iconSize: CGFloat,
        prominent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: iconSize))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: Layout.footerButtonHeight)
            .background(
                RoundedRectangle(cornerRadius: Layout.footerButtonCornerRadius, style: .continuous)
                    .fill(prominent ? Color.accentColor : Color.white.opacity(0.08))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(prominent ? Color.white : Color.primary)
    }
}
