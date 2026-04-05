import SwiftUI

extension SettingsView {
    @ViewBuilder
    var detailView: some View {
        switch selection {
        case .general:
            GeneralSettingsView(defaultEditor: $defaultEditor)
                .navigationTitle("General")
                .navigationSubtitle("Default apps, layout, and toolbar")
        case .appearance:
            AppearanceSettingsView()
                .navigationTitle("Appearance")
                .navigationSubtitle("Shared theme, typography, and markdown")
        case .transcription:
            TranscriptionSettingsView()
                .navigationTitle("Transcription")
                .navigationSubtitle("Speech-to-text engine and models")
        case .pro:
            AizenProSettingsView(licenseManager: licenseManager)
                .navigationTitle("Aizen Pro")
                .navigationSubtitle("License and billing")
        case .git:
            GitSettingsView()
                .navigationTitle("Git")
                .navigationSubtitle("Branch templates and preferences")
        case .terminal:
            TerminalSettingsView()
                .navigationTitle("Terminal")
                .navigationSubtitle("Session behavior, copy processing, and presets")
        case .editor:
            EditorSettingsView()
                .navigationTitle("Editor")
                .navigationSubtitle("Editor behavior and file browser options")
        case .agent(let agentId):
            if let index = agents.firstIndex(where: { $0.id == agentId }) {
                AgentDetailView(
                    metadata: $agents[index],
                    isDefault: agentId == defaultACPAgent,
                    onSetDefault: { defaultACPAgent = agentId }
                )
                .navigationTitle(agents[index].name)
                .navigationSubtitle("Agent Configuration")
            }
        case .none:
            GeneralSettingsView(defaultEditor: $defaultEditor)
                .navigationTitle("General")
                .navigationSubtitle("Default apps, layout, and toolbar")
        }
    }
}
