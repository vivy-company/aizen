import AppKit
import SwiftUI

struct SupportSheet: View {
    @Environment(\.dismiss) private var dismiss

    private struct ContactOption: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let icon: String
        let iconImage: String?
        let iconText: String?
        let color: Color
        let url: String
    }

    private let contactOptions: [ContactOption] = [
        ContactOption(title: "Aizen", subtitle: "@aizenwin", icon: "", iconImage: nil, iconText: "𝕏", color: .primary, url: "https://x.com/aizenwin"),
        ContactOption(title: "Developer", subtitle: "@wiedymi", icon: "", iconImage: nil, iconText: "𝕏", color: .primary, url: "https://x.com/wiedymi"),
        ContactOption(title: "Discord", subtitle: "Join Community", icon: "", iconImage: "DiscordLogo", iconText: nil, color: Color(red: 0.345, green: 0.396, blue: 0.949), url: "https://discord.gg/zemMZtrkSb"),
        ContactOption(title: "Email", subtitle: "dev@aizen.win", icon: "envelope.fill", iconImage: nil, iconText: nil, color: .orange, url: "mailto:dev@aizen.win"),
        ContactOption(title: "GitHub", subtitle: "Report Issue", icon: "exclamationmark.triangle.fill", iconImage: nil, iconText: nil, color: .red, url: "https://github.com/vivy-company/aizen/issues")
    ]

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.blue)

                    Text("sidebar.support.title")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("sidebar.support.subtitle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
                .padding(.bottom, 20)

                DetailCloseButton { dismiss() }
                    .padding(12)
            }

            Divider()

            VStack(spacing: 0) {
                ForEach(contactOptions) { option in
                    Button {
                        if let url = URL(string: option.url) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 14) {
                            Group {
                                if let imageName = option.iconImage {
                                    Image(imageName)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                } else if let text = option.iconText {
                                    Text(text)
                                        .font(.system(size: 18, weight: .bold))
                                } else {
                                    Image(systemName: option.icon)
                                }
                            }
                            .frame(width: 24, height: 24)
                            .foregroundStyle(option.color)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.title)
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.primary)

                                Text(option.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if option.id != contactOptions.last?.id {
                        Divider()
                            .padding(.leading, 58)
                    }
                }
            }

            Button {
                if let url = URL(string: "https://x.com/vivytech") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Vivy Technologies Co., Limited")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.quaternary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 340)
        .settingsSheetChrome()
    }
}
