import ACP
import SwiftUI

extension AgentUsageDetailContent {
    func heroStatCard(
        icon: String,
        iconColor: Color,
        value: String,
        label: String,
        sublabel: String?
    ) -> some View {
        bentoCard {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(iconColor)

                Spacer()

                Text(value)
                    .font(.title)
                    .fontWeight(.bold)
                    .fontDesign(.rounded)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.caption)
                        .fontWeight(.medium)
                    if let sublabel {
                        Text(sublabel)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 120)
    }

    func miniStatCard(
        value: String,
        label: String,
        icon: String,
        color: Color
    ) -> some View {
        bentoCard {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(color)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .fontDesign(.rounded)
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
        }
        .frame(minWidth: 120)
    }

    func planCard(user: UsageUserIdentity) -> some View {
        bentoCard(minHeight: 130) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Account", systemImage: "person.crop.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if let plan = user.plan {
                    Text(plan)
                        .font(.title3)
                        .fontWeight(.bold)
                }

                VStack(alignment: .leading, spacing: 2) {
                    if let email = user.email {
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let org = user.organization {
                        Text(org)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func quotaRingCard(window: UsageQuotaWindow) -> some View {
        bentoCard(maxHeight: .infinity) {
            HStack(spacing: 12) {
                UsageRing(percent: window.usedPercent)
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(window.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if let reset = window.resetDescription {
                        Text(reset)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()
            }
        }
    }

    func bentoCard<Content: View>(
        minHeight: CGFloat? = nil,
        maxHeight: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: maxHeight, alignment: .leading)
            .background(Color.secondary.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
