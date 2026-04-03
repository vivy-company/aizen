import ACP
import SwiftUI
import UniformTypeIdentifiers

extension AgentDetailView {
    @ViewBuilder
    var usageSection: some View {
        if metadata.isEnabled, supportsUsageMetrics {
            Section("Usage") {
                AgentUsageSummaryView(
                    report: usageMetricsStore.report(for: metadata.id),
                    refreshState: usageMetricsStore.refreshState(for: metadata.id),
                    onRefresh: { usageMetricsStore.refresh(agentId: metadata.id, force: true) },
                    onOpenDetails: { showingUsageDetails = true }
                )
            }
        }
    }

    @ViewBuilder
    var configurationSection: some View {
        if metadata.isEnabled, !configSpec.configFiles.isEmpty {
            Section("Configuration") {
                if let rulesFile = configSpec.rulesFile {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rulesFile.name)
                                    .font(.headline)
                                if let desc = rulesFile.description {
                                    Text(desc)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            Button(rulesFile.exists ? "Edit" : "Create") {
                                showingRulesEditor = true
                            }
                            .buttonStyle(.bordered)
                        }

                        if let preview = rulesPreview, !preview.isEmpty {
                            Text(preview)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(6)
                        }
                    }
                }

                ForEach(configSpec.settingsFiles) { configFile in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(configFile.name)
                                .font(.headline)
                            if let desc = configFile.description {
                                Text(desc)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        Button(configFile.exists ? "Edit" : "Create") {
                            selectedConfigFile = configFile
                            showingConfigEditor = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }
}
