import SwiftUI

extension GeneralSettingsView {
    @ViewBuilder
    var cliSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                if let linkPath = cliStatus.linkPath {
                    Text("Symlink: \(linkPath)")
                        .font(.footnote)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }

                if let targetPath = cliStatus.targetPath {
                    Text("Target: \(targetPath)")
                        .font(.footnote)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Button(cliStatus.isInstalled ? "Reinstall CLI" : "Install CLI") {
                        installCLI()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Refresh") {
                        refreshCLIStatus()
                    }
                }
            }
        } header: {
            HStack(spacing: 8) {
                Text("CLI")
                Text(cliStatus.isInstalled ? "Installed" : "Not installed")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(cliStatus.isInstalled ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                    .foregroundStyle(cliStatus.isInstalled ? .green : .orange)
                    .clipShape(Capsule())
            }
        }
    }

    func refreshCLIStatus() {
        cliStatus = CLISymlinkService.status()
    }

    func installCLI() {
        let result = CLISymlinkService.install()
        cliAlertMessage = result.message
        showingCLIAlert = true
        refreshCLIStatus()
    }
}
