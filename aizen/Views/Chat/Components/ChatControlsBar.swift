//
//  ChatControlsBar.swift
//  aizen
//
//  Agent selector and mode controls bar
//

import SwiftUI

struct ChatControlsBar: View {
    let selectedAgent: String
    let currentAgentSession: AgentSession?
    let hasModes: Bool
    let onAgentSelect: (String) -> Void

    @State private var showingAuthClearedMessage = false

    var body: some View {
        HStack(spacing: 8) {
            AgentSelectorMenu(selectedAgent: selectedAgent, onAgentSelect: onAgentSelect)

            if hasModes, let agentSession = currentAgentSession {
                ModeSelectorView(session: agentSession)
            }

            Spacer()

            if showingAuthClearedMessage {
                Text("Auth cleared. Start new session to re-authenticate.")
                    .font(.caption)
                    .foregroundColor(.green)
                    .transition(.opacity)
            }

            Menu {
                Button("Re-authenticate") {
                    AgentRegistry.shared.clearAuthPreference(for: selectedAgent)

                    // Trigger re-authentication by setting needsAuthentication
                    if let session = currentAgentSession {
                        Task { @MainActor in
                            session.needsAuthentication = true
                        }
                    }

                    withAnimation {
                        showingAuthClearedMessage = true
                    }
                    Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        withAnimation {
                            showingAuthClearedMessage = false
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .help("Session options")
        }
    }
}
