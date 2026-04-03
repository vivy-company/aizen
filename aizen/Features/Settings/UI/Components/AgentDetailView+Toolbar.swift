import ACP
import SwiftUI
import UniformTypeIdentifiers

extension AgentDetailView {
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if metadata.requiresInstall,
               !isAgentValid,
               !isUpdating {
                if isInstalling {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Button {
                        Task { await installAgent() }
                    } label: {
                        Label("Install", systemImage: "square.and.arrow.down")
                            .labelStyle(.titleAndIcon)
                    }
                    .help("Install agent")
                }
            }

            if canUpdate && (isAgentValid || isUpdating) {
                if isUpdating {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Button {
                        Task { await updateAgent() }
                    } label: {
                        Label("Update", systemImage: "arrow.triangle.2.circlepath")
                            .labelStyle(.titleAndIcon)
                    }
                    .help("Update to latest version")
                }
            }

            if isAgentValid {
                if isTesting {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        Label("Test", systemImage: "antenna.radiowaves.left.and.right")
                            .labelStyle(.titleAndIcon)
                    }
                    .help("Test connection")
                }
            }

            if metadata.isCustom {
                Button {
                    showingEditSheet = true
                } label: {
                    Label("Edit", systemImage: "square.and.pencil")
                        .labelStyle(.titleAndIcon)
                }
                .help("Edit agent")
            }
        }
    }
}
