//
//  OnboardingView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 27.10.25.
//

import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header section with app icon and title
            VStack(spacing: 12) {
                Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 72, height: 72)
                    .cornerRadius(14)

                Text("onboarding.welcome", bundle: .main)
                    .font(.system(size: 28, weight: .bold))

                Text("onboarding.tagline", bundle: .main)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 40)
            .padding(.bottom, 28)

            // Features grid - 3 items
            VStack(spacing: 20) {
                FeatureRow(
                    icon: "rectangle.stack",
                    iconColor: .blue,
                    title: String(localized: "onboarding.feature.workspaces.title"),
                    description: String(localized: "onboarding.feature.workspaces.description")
                )

                FeatureRow(
                    icon: "square.grid.2x2",
                    iconColor: .green,
                    title: String(localized: "onboarding.feature.sessions.title"),
                    description: String(localized: "onboarding.feature.sessions.description")
                )

                FeatureRow(
                    icon: "brain",
                    iconColor: .purple,
                    title: String(localized: "onboarding.feature.agents.title"),
                    description: String(localized: "onboarding.feature.agents.description")
                )
            }
            .padding(.horizontal, 48)
            .padding(.bottom, 28)

            // Action buttons
            VStack(spacing: 16) {
                Button {
                    dismiss()
                } label: {
                    Text("onboarding.getStarted", bundle: .main)
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    if let url = URL(string: "https://discord.gg/eKW7GNesuS") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image("DiscordLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 18, height: 18)
                        Text("onboarding.joinDiscord", bundle: .main)
                            .font(.system(size: 13, weight: .medium))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 48)
            .padding(.bottom, 32)
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct FeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)
                .foregroundStyle(iconColor.gradient)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))

                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
    }
}

#Preview {
    OnboardingView()
}
