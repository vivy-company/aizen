import SwiftUI

extension MCPInstallConfigSheet {
    func install() async {
        isInstalling = true
        errorMessage = nil

        do {
            try await MCPInstallConfigSupport.install(
                manager: mcpManager,
                installType: installType,
                server: server,
                agentId: agentId,
                selectedPackage: selectedPackage,
                selectedRemote: selectedRemote,
                envValues: envValues
            )
            onInstalled()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isInstalling = false
    }
}
