//
//  ChatSessionView+Presentation.swift
//  aizen
//
//  Sheets and alerts attached to the chat session screen.
//

import AppKit
import SwiftUI

extension ChatSessionView {
    func applyPresentationModifiers<Content: View>(to content: Content) -> some View {
        content
            .sheet(isPresented: viewModel.needsAuthBinding) {
                if let agentSession = viewModel.currentAgentSession {
                    AuthenticationSheet(session: agentSession)
                }
            }
            .sheet(isPresented: viewModel.needsSetupBinding) {
                if let agentSession = viewModel.currentAgentSession {
                    AgentSetupDialog(session: agentSession)
                }
            }
            .sheet(isPresented: viewModel.needsUpdateBinding) {
                if let versionInfo = viewModel.versionInfo {
                    AgentUpdateSheet(
                        agentName: viewModel.selectedAgent,
                        versionInfo: versionInfo
                    )
                }
            }
            .sheet(isPresented: $showingUsageSheet) {
                AgentUsageSheet(
                    agentId: viewModel.selectedAgent,
                    agentName: viewModel.selectedAgentDisplayName
                )
            }
            .alert(String(localized: "chat.agent.switch.title"), isPresented: $viewModel.showingAgentSwitchWarning) {
                Button(String(localized: "chat.button.cancel"), role: .cancel) {
                    viewModel.pendingAgentSwitch = nil
                }
                Button(String(localized: "chat.button.switch"), role: .destructive) {
                    if let newAgent = viewModel.pendingAgentSwitch {
                        viewModel.performAgentSwitch(to: newAgent)
                    }
                }
            } message: {
                Text("chat.agent.switch.message", bundle: .main)
            }
            .alert(String(localized: "chat.permission.title"), isPresented: $showingPermissionError) {
                Button(String(localized: "chat.permission.openSettings")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button(String(localized: "chat.button.cancel"), role: .cancel) {}
            } message: {
                Text(permissionErrorMessage)
            }
    }
}
