//
//  AboutView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 16.12.25.
//

import SwiftUI

struct AboutView: View {
    private let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    private let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"

    var body: some View {
        VStack(spacing: 0) {
            // App icon and name
            VStack(spacing: 12) {
                Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 96)
                    .cornerRadius(18)
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)

                Text("Aizen")
                    .font(.system(size: 24, weight: .bold))

                Text("Version \(appVersion) (\(buildNumber))")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 32)
            .padding(.bottom, 24)

            // Tagline
            Text("Bring order to your repos.\nSwitch worktrees, not windows.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)

            // Links
            VStack(spacing: 12) {
                LinkButton(
                    title: "Join Discord Community",
                    icon: "DiscordLogo",
                    isSystemImage: false,
                    url: "https://discord.gg/zemMZtrkSb"
                )

                LinkButton(
                    title: "View on GitHub",
                    icon: "link",
                    isSystemImage: true,
                    url: "https://github.com/vivy-company/aizen"
                )

                LinkButton(
                    title: "Report an Issue",
                    icon: "exclamationmark.bubble",
                    isSystemImage: true,
                    url: "https://github.com/vivy-company/aizen/issues"
                )
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)

            Divider()
                .padding(.horizontal, 32)

            // Copyright
            Text("© 2025 Vivy Technologies Co., Limited")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.vertical, 16)
        }
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct LinkButton: View {
    let title: String
    let icon: String
    let isSystemImage: Bool
    let url: String

    var body: some View {
        Button {
            if let url = URL(string: url) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 10) {
                if isSystemImage {
                    Image(systemName: icon)
                        .frame(width: 18, height: 18)
                } else {
                    Image(icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)
                }

                Text(title)
                    .font(.system(size: 13, weight: .medium))

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.quaternary.opacity(0.5))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AboutView()
}
