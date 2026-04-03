import AppKit
import SwiftUI

extension GeneralSettingsView {
    @ViewBuilder
    var projectsSection: some View {
        Section("Projects") {
            HStack(spacing: 12) {
                TextField("Default Clone Location", text: $defaultCloneLocation)
                    .textFieldStyle(.roundedBorder)
                Button("Choose") {
                    selectDefaultCloneLocation()
                }
            }
            .help("Used by the CLI when cloning projects without --destination")

            Picker("Default Workspace", selection: $defaultWorkspaceId) {
                Text("None")
                    .tag("")
                ForEach(workspaces) { workspace in
                    let workspaceName = workspace.name ?? ""
                    let workspaceID = workspace.id?.uuidString ?? ""
                    Text(workspaceName)
                        .tag(workspaceID)
                }
            }
            .help("Used by the CLI when adding projects without --workspace")
        }
    }

    func selectDefaultCloneLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select default clone location"

        if panel.runModal() == .OK, let url = panel.url {
            defaultCloneLocation = url.path
        }
    }
}
