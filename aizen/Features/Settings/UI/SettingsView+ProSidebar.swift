import SwiftUI

extension SettingsView {
    var proSidebarRow: some View {
        Button {
            selection = .pro
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.pink, Color.orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 18, height: 18)
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }

                Text("Aizen Pro")
                    .fontWeight(.semibold)

                Spacer()

                PillBadge(
                    text: proBadgeTitle,
                    color: proBadgeColor,
                    font: .caption2,
                    fontWeight: .semibold,
                    backgroundOpacity: 0.18,
                    lineLimit: 1,
                    minimumScaleFactor: 0.7
                )
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selection == .pro ? Color.white.opacity(0.06) : Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(selection == .pro ? 0.12 : 0.06), lineWidth: 1)
        )
    }

    var proBadgeTitle: String {
        switch licenseManager.status {
        case .active, .offlineGrace:
            return "PRO"
        case .checking:
            return "CHECK"
        case .unlicensed, .expired, .invalid, .error:
            return "OFF"
        }
    }

    var proBadgeColor: Color {
        switch licenseManager.status {
        case .active, .offlineGrace:
            return .orange
        case .checking:
            return .yellow
        case .unlicensed, .expired, .invalid, .error:
            return .red
        }
    }
}
