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
            VStack(spacing: 16) {
                Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .cornerRadius(16)

                Text("onboarding.welcome", bundle: .main)
                    .font(.system(size: 32, weight: .bold))

                Text("onboarding.subtitle", bundle: .main)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 500)
            }
            .padding(.top, 48)
            .padding(.bottom, 32)

            // Features grid
            VStack(spacing: 24) {
                FeatureRow(
                    icon: "arrow.triangle.branch",
                    iconColor: .blue,
                    title: String(localized: "onboarding.feature.worktree.title"),
                    description: String(localized: "onboarding.feature.worktree.description")
                )

                FeatureRow(
                    icon: "terminal",
                    iconColor: .green,
                    title: String(localized: "onboarding.feature.terminal.title"),
                    description: String(localized: "onboarding.feature.terminal.description")
                )

                FeatureRow(
                    icon: "brain",
                    iconColor: .purple,
                    title: String(localized: "onboarding.feature.agents.title"),
                    description: String(localized: "onboarding.feature.agents.description")
                )

                FeatureRow(
                    icon: "play.circle",
                    iconColor: .orange,
                    title: String(localized: "onboarding.feature.setup.title"),
                    description: String(localized: "onboarding.feature.setup.description")
                )
            }
            .padding(.horizontal, 48)
            .padding(.bottom, 32)

            Spacer()

            // Get Started button
            Button {
                dismiss()
            } label: {
                Text("onboarding.getStarted", bundle: .main)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 48)
            .padding(.bottom, 32)
        }
        .frame(width: 600, height: 650)
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
