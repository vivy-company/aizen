//
//  WorktreeSessionTabs+NewTabButton.swift
//  aizen
//
//  New tab button for chat and terminal sessions
//

import SwiftUI

struct NewTabButton: View {
    let selectedTab: String
    let onCreateChatSession: () -> Void
    let onCreateTerminalSession: () -> Void
    var onCreateChatWithAgent: ((String) -> Void)?
    var onCreateTerminalWithPreset: ((TerminalPreset) -> Void)?

    @StateObject private var presetManager = TerminalPresetStore.shared
    @State private var enabledAgents: [AgentMetadata] = []
    @State private var isHovering = false
    @State private var clickTrigger = 0

    var body: some View {
        if selectedTab == "chat" && !enabledAgents.isEmpty {
            Menu {
                ForEach(enabledAgents, id: \.id) { agentMetadata in
                    Button {
                        onCreateChatWithAgent?(agentMetadata.id)
                    } label: {
                        HStack {
                            AgentIconView(metadata: agentMetadata, size: 14)
                            Text(agentMetadata.name)
                        }
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11))
                    .frame(width: 24, height: 24)
                    .background(
                        isHovering ? Color(nsColor: .separatorColor).opacity(0.5) : Color.clear,
                        in: Circle()
                    )
            } primaryAction: {
                clickTrigger += 1
                onCreateChatSession()
            }
            .menuStyle(.button)
            .menuIndicator(.visible)
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovering = hovering
            }
            .help("Click for new chat, or click arrow for agents")
            .onAppear {
                enabledAgents = AgentRegistry.shared.getEnabledAgents()
            }
            .onReceive(NotificationCenter.default.publisher(for: .agentMetadataDidChange)) { _ in
                enabledAgents = AgentRegistry.shared.getEnabledAgents()
            }
        } else if selectedTab == "terminal" && !presetManager.presets.isEmpty {
            Menu {
                Button {
                    onCreateTerminalSession()
                } label: {
                    Label("New Terminal", systemImage: "terminal")
                }

                Divider()

                ForEach(presetManager.presets) { preset in
                    Button {
                        onCreateTerminalWithPreset?(preset)
                    } label: {
                        Label(preset.name, systemImage: preset.icon)
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11))
                    .frame(width: 24, height: 24)
                    .background(
                        isHovering ? Color(nsColor: .separatorColor).opacity(0.5) : Color.clear,
                        in: Circle()
                    )
            } primaryAction: {
                clickTrigger += 1
                onCreateTerminalSession()
            }
            .menuStyle(.button)
            .menuIndicator(.visible)
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovering = hovering
            }
            .help("Click for new terminal, or click arrow for presets")
        } else {
            let button = Button {
                clickTrigger += 1
                if selectedTab == "chat" {
                    onCreateChatSession()
                } else {
                    onCreateTerminalSession()
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11))
                    .frame(width: 24, height: 24)
                    .background(
                        isHovering ? Color(nsColor: .separatorColor).opacity(0.5) : Color.clear,
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovering = hovering
            }
            .help("New \(selectedTab == "chat" ? "Chat" : "Terminal") Session")
            .onAppear {
                if selectedTab == "chat" {
                    enabledAgents = AgentRegistry.shared.getEnabledAgents()
                }
            }

            if #available(macOS 14.0, *) {
                button.symbolEffect(.bounce, value: clickTrigger)
            } else {
                button
            }
        }
    }
}
