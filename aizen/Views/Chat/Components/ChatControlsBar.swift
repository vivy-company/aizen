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
    let attachments: [ChatAttachment]
    let onRemoveAttachment: (ChatAttachment) -> Void
    let plan: Plan?
    let onShowUsage: () -> Void
    let onNewSession: () -> Void
    let showsUsage: Bool

    @State private var showingAuthClearedMessage = false

    var body: some View {
        HStack(spacing: 8) {
            // Left side: Attachments, Plan
            if !attachments.isEmpty {
                ForEach(attachments) { attachment in
                    ChatAttachmentChip(attachment: attachment) {
                        onRemoveAttachment(attachment)
                    }
                }
            }

            if let plan = plan {
                AgentPlanInlineView(plan: plan)
            }

            Spacer()

            // Right side: Auth message, Mode picker, More options
            if showingAuthClearedMessage {
                Text("Auth cleared. Start new session to re-authenticate.")
                    .font(.caption)
                    .foregroundColor(.green)
                    .transition(.opacity)
            }

            if hasModes, let agentSession = currentAgentSession {
                ModeSelectorView(session: agentSession)
            }

            if showsUsage {
                Button(action: onShowUsage) {
                    Image(systemName: "chart.bar")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Usage")
            }

            Menu {
                Button("New Session") {
                    onNewSession()
                }

                Divider()

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
