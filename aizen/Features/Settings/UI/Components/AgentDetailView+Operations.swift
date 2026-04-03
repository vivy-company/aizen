import ACP
import SwiftUI

extension AgentDetailView {
    func validateAgent() async {
        let isValid = AgentRegistry.shared.validateAgent(named: metadata.id)
        await MainActor.run {
            isAgentValid = isValid
            errorMessage = nil
        }
    }

    func updateAgent() async {
        await MainActor.run {
            isUpdating = true
            testResult = nil
        }

        do {
            try await AgentInstaller.shared.updateAgent(metadata)
            let refreshedMetadata = AgentRegistry.shared.getMetadata(for: metadata.id)
            await MainActor.run {
                if let refreshedMetadata {
                    metadata = refreshedMetadata
                }
                showResult("Updated to latest version")
            }

            await validateAgent()
            let canUpdateState = await AgentInstaller.shared.canUpdate(metadata)
            await MainActor.run {
                canUpdate = canUpdateState
            }

            await AgentVersionChecker.shared.clearCache(for: metadata.id)
            await loadVersion()
        } catch {
            await MainActor.run {
                showResult("Update failed: \(error.localizedDescription)", autoDismiss: false)
            }
        }

        await MainActor.run {
            isUpdating = false
        }
    }

    func installAgent() async {
        await MainActor.run {
            isInstalling = true
            testResult = nil
        }

        do {
            try await AgentInstaller.shared.installAgent(metadata)
            let refreshedMetadata = AgentRegistry.shared.getMetadata(for: metadata.id)
            await MainActor.run {
                if let refreshedMetadata {
                    metadata = refreshedMetadata
                }
            }

            await validateAgent()
            let canUpdateState = await AgentInstaller.shared.canUpdate(metadata)
            await MainActor.run {
                canUpdate = canUpdateState
            }

            await loadVersion()
        } catch {
            await MainActor.run {
                showResult("Install failed: \(error.localizedDescription)", autoDismiss: false)
            }
        }

        await MainActor.run {
            isInstalling = false
        }
    }

    func testConnection() async {
        testTask?.cancel()

        isTesting = true
        testResult = nil

        guard let path = AgentRegistry.shared.getAgentPath(for: metadata.id) else {
            showResult("No executable path set", autoDismiss: false)
            isTesting = false
            return
        }

        testTask = Task {
            do {
                let tempClient = Client()

                let arguments = AgentRegistry.shared.getAgentLaunchArgs(for: metadata.id)
                let environment = await AgentRegistry.shared.resolvedAgentLaunchEnvironment(for: metadata.id)

                try await tempClient.launch(
                    agentPath: path,
                    arguments: arguments,
                    environment: environment.isEmpty ? nil : environment
                )

                let capabilities = ClientCapabilities(
                    fs: FileSystemCapabilities(
                        readTextFile: true,
                        writeTextFile: true
                    ),
                    terminal: true,
                    meta: [
                        "terminal_output": AnyCodable(true),
                        "terminal-auth": AnyCodable(true)
                    ]
                )

                _ = try await tempClient.initialize(
                    protocolVersion: 1,
                    capabilities: capabilities
                )

                await MainActor.run {
                    showResult("Success: Valid ACP executable")
                }

                await tempClient.terminate()
            } catch {
                await MainActor.run {
                    showResult("Failed: \(error.localizedDescription)", autoDismiss: false)
                }
            }

            await MainActor.run {
                isTesting = false
            }
        }

        await testTask?.value
    }

    func loadVersion() async {
        guard isAgentValid else {
            await MainActor.run {
                installedVersion = nil
            }
            return
        }

        let versionInfo = await AgentVersionChecker.shared.checkVersion(for: metadata.id)
        await MainActor.run {
            installedVersion = versionInfo.current
        }
    }

    func showResult(_ message: String, autoDismiss: Bool = true) {
        resultDismissTask?.cancel()
        testResult = message

        if autoDismiss {
            resultDismissTask = Task {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    testResult = nil
                }
            }
        }
    }
}
