import SwiftUI

extension AgentUsageDetailContent {
    var heroSection: some View {
        HStack(spacing: gridSpacing) {
            heroStatCard(
                icon: "bolt.fill",
                iconColor: .purple,
                value: totalCostString,
                label: "Total cost",
                sublabel: "This month"
            )
            heroStatCard(
                icon: "text.word.spacing",
                iconColor: .blue,
                value: totalTokensString,
                label: "Tokens",
                sublabel: "This month"
            )
            if let primaryQuota = report.quota.first {
                heroStatCard(
                    icon: "gauge.with.dots.needle.50percent",
                    iconColor: quotaColor(primaryQuota.usedPercent),
                    value: UsageFormatter.percentString(primaryQuota.usedPercent),
                    label: primaryQuota.title,
                    sublabel: primaryQuota.resetDescription
                )
            } else {
                heroStatCard(
                    icon: "gauge.with.dots.needle.50percent",
                    iconColor: .secondary,
                    value: "N/A",
                    label: "Usage",
                    sublabel: nil
                )
            }
        }
    }

    var accountAndActivitySection: some View {
        HStack(alignment: .top, spacing: gridSpacing) {
            if showActivity {
                VStack(spacing: gridSpacing) {
                    HStack(spacing: gridSpacing) {
                        miniStatCard(
                            value: "\(activityStats.sessionsStarted)",
                            label: "Sessions",
                            icon: "bubble.left.and.bubble.right.fill",
                            color: .green
                        )
                        miniStatCard(
                            value: "\(activityStats.promptsSent)",
                            label: "Prompts",
                            icon: "arrow.up.circle.fill",
                            color: .blue
                        )
                    }
                    HStack(spacing: gridSpacing) {
                        miniStatCard(
                            value: "\(activityStats.agentMessages)",
                            label: "Responses",
                            icon: "arrow.down.circle.fill",
                            color: .indigo
                        )
                        miniStatCard(
                            value: "\(activityStats.toolCalls)",
                            label: "Tool calls",
                            icon: "wrench.and.screwdriver.fill",
                            color: .orange
                        )
                    }
                }
                .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: 8) {
                if let user = report.user, hasAccountDetails(user) {
                    planCard(user: user)
                } else {
                    bentoCard(minHeight: 130) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Account", systemImage: "person.crop.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("Not signed in")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    var usageAndQuotaSection: some View {
        HStack(alignment: .top, spacing: gridSpacing) {
            bentoCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Token usage", systemImage: "chart.bar.fill")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    if report.periods.isEmpty {
                        Spacer()
                        Text("No data")
                            .foregroundStyle(.tertiary)
                        Spacer()
                    } else {
                        tokenPeriodsList
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)

            if report.quota.count > 1 {
                VStack(spacing: gridSpacing) {
                    ForEach(report.quota.dropFirst()) { window in
                        quotaRingCard(window: window)
                            .frame(maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 200, maxHeight: .infinity)
            } else {
                bentoCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Last active", systemImage: "clock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(lastUsedText)
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
                .frame(minWidth: 200)
            }
        }
        .frame(minHeight: 180)
    }

    var footerSection: some View {
        HStack(alignment: .top, spacing: gridSpacing) {
            if !report.notes.isEmpty || !report.errors.isEmpty {
                bentoCard(maxHeight: .infinity) {
                    VStack(alignment: .leading, spacing: 8) {
                        if !report.notes.isEmpty {
                            ForEach(report.notes, id: \.self) { note in
                                Label(note, systemImage: "info.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if !report.errors.isEmpty {
                            ForEach(report.errors, id: \.self) { error in
                                Label(error, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
            }

            bentoCard(maxHeight: .infinity) {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.secondary)
                    Text(UsageFormatter.relativeDateString(report.updatedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    refreshButton
                }
            }
            .frame(minWidth: 200)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
