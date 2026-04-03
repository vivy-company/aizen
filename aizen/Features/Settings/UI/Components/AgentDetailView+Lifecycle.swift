import ACP
import SwiftUI
import UniformTypeIdentifiers

extension AgentDetailView {
    func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                metadata.executablePath = url.path
                Task {
                    await AgentRegistry.shared.updateAgent(metadata)
                    await validateAgent()
                }
            }
        case .failure(let error):
            errorMessage = "Failed to select file: \(error.localizedDescription)"
        }
    }

    func performAgentLoad() async {
        await validateAgent()
        canUpdate = await AgentInstaller.shared.canUpdate(metadata)
        loadAuthStatus()
        await loadVersion()
        loadRulesPreview()
        loadCommands()
        await mcpManager.syncInstalled(agentId: metadata.id)
    }

    func refreshUsageIfNeeded() {
        if supportsUsageMetrics {
            usageMetricsStore.refreshIfNeeded(agentId: metadata.id)
        }
    }

    func handleDisappear() {
        testTask?.cancel()
        flushEnvironmentSaveIfNeeded()
    }
}
