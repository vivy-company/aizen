//
//  CrossProjectOnboardingView.swift
//  aizen
//
//  Created by Codex on 12.03.26.
//

import SwiftUI

struct CrossProjectOnboardingView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.blue.gradient.opacity(0.16))
                        .frame(width: 76, height: 76)

                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.blue.gradient)
                }

                Text("crossProjectOnboarding.title", bundle: .main)
                    .font(.system(size: 28, weight: .bold))

                Text("crossProjectOnboarding.tagline", bundle: .main)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 40)
            .padding(.horizontal, 48)
            .padding(.bottom, 28)

            VStack(spacing: 20) {
                FeatureRow(
                    icon: "folder.badge.gearshape",
                    iconColor: .blue,
                    title: String(localized: "crossProjectOnboarding.feature.workspaceRoot.title"),
                    description: String(localized: "crossProjectOnboarding.feature.workspaceRoot.description")
                )

                FeatureRow(
                    icon: "link",
                    iconColor: .green,
                    title: String(localized: "crossProjectOnboarding.feature.safeLinks.title"),
                    description: String(localized: "crossProjectOnboarding.feature.safeLinks.description")
                )

                FeatureRow(
                    icon: "brain",
                    iconColor: .orange,
                    title: String(localized: "crossProjectOnboarding.feature.bestForAgents.title"),
                    description: String(localized: "crossProjectOnboarding.feature.bestForAgents.description")
                )
            }
            .padding(.horizontal, 48)
            .padding(.bottom, 28)

            VStack(spacing: 16) {
                Button {
                    dismiss()
                } label: {
                    Text("crossProjectOnboarding.continue", bundle: .main)
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.horizontal, 48)
            .padding(.bottom, 32)
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    CrossProjectOnboardingView()
}
