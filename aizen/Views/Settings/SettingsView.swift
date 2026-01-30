//
//  SettingsView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI

private extension View {
    @ViewBuilder
    func removingSidebarToggle() -> some View {
        if #available(macOS 14.0, *) {
            self.toolbar(removing: .sidebarToggle)
        } else {
            self
        }
    }
}

// MARK: - Settings Selection

enum SettingsSelection: Hashable {
    case general
    case transcription
    case pro
    case git
    case terminal
    case editor
    case chat
    case agent(String) // agent id
}

// MARK: - Settings View

struct SettingsView: View {
    @AppStorage("defaultEditor") private var defaultEditor = "code"
    @AppStorage("defaultACPAgent") private var defaultACPAgent = "claude"
    @AppStorage("terminalFontName") private var terminalFontName = "Menlo"
    @AppStorage("terminalFontSize") private var terminalFontSize = 12.0

    @State private var selection: SettingsSelection? = .general
    @State private var agents: [AgentMetadata] = []
    @State private var showingAddCustomAgent = false
    @StateObject private var licenseManager = LicenseManager.shared

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    // Static settings items
                    Label("General", systemImage: "gear")
                        .tag(SettingsSelection.general)

                    Label("Transcription", systemImage: "waveform")
                        .tag(SettingsSelection.transcription)

                    Label("Git", systemImage: "arrow.triangle.branch")
                        .tag(SettingsSelection.git)

                    Label("Terminal", systemImage: "terminal")
                        .tag(SettingsSelection.terminal)

                    Label("Editor", systemImage: "doc.text")
                        .tag(SettingsSelection.editor)

                    Label("Chat", systemImage: "bubble.left.and.bubble.right")
                        .tag(SettingsSelection.chat)

                    // Agents section
                    Section("Agents") {
                        ForEach(agents, id: \.id) { agent in
                            HStack(spacing: 8) {
                                AgentIconView(metadata: agent, size: 20)
                                Text(agent.name)
                                Spacer()
                                if agent.id == defaultACPAgent {
                                    Circle()
                                        .fill(.blue)
                                        .frame(width: 8, height: 8)
                                }
                            }
                            .tag(SettingsSelection.agent(agent.id))
                            .contextMenu {
                                if agent.id != defaultACPAgent {
                                    Button("Make Default") {
                                        defaultACPAgent = agent.id
                                    }
                                }
                            }
                        }

                        Button {
                            showingAddCustomAgent = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(.secondary)
                                Text("Add Custom Agent")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.sidebar)
                .frame(minWidth: 220, maxHeight: .infinity)
                .navigationSplitViewColumnWidth(220)
                .removingSidebarToggle()

                Divider()

                proSidebarRow
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
        } detail: {
            if #available(macOS 14.0, *) {
                NavigationStack {
                    detailView
                }
            } else {
                NavigationStack {
                    detailView
                }
            }
        }
        .toolbar {
            // Forces creation of an NSToolbar so the window's unified toolbar style applies.
            ToolbarItem(placement: .principal) { Text("") }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 750, minHeight: 500)
        .onAppear {
            loadAgents()
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentMetadataDidChange)) { _ in
            loadAgents()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsPro)) { _ in
            selection = .pro
        }
        .sheet(isPresented: $showingAddCustomAgent) {
            CustomAgentFormView(
                onSave: { _ in
                    loadAgents()
                },
                onCancel: {}
            )
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .general:
            GeneralSettingsView(defaultEditor: $defaultEditor)
                .navigationTitle("General")
                .navigationSubtitle("Default apps, layout, and toolbar")
        case .transcription:
            TranscriptionSettingsView()
                .navigationTitle("Transcription")
                .navigationSubtitle("Speech-to-text engine and models")
        case .pro:
            AizenProSettingsView(licenseManager: licenseManager)
                .navigationTitle("Aizen Pro")
                .navigationSubtitle("License and billing")
        case .git:
            GitSettingsView()
                .navigationTitle("Git")
                .navigationSubtitle("Branch templates and preferences")
        case .terminal:
            TerminalSettingsView(
                fontName: $terminalFontName,
                fontSize: $terminalFontSize
            )
            .navigationTitle("Terminal")
            .navigationSubtitle("Font, theme, and session settings")
        case .editor:
            EditorSettingsView()
                .navigationTitle("Editor")
                .navigationSubtitle("Theme, font, and display options")
        case .chat:
            ChatSettingsView()
                .navigationTitle("Chat")
                .navigationSubtitle("Font size and markdown spacing")
        case .agent(let agentId):
            if let index = agents.firstIndex(where: { $0.id == agentId }) {
                AgentDetailView(
                    metadata: $agents[index],
                    isDefault: agentId == defaultACPAgent,
                    onSetDefault: { defaultACPAgent = agentId }
                )
                .navigationTitle(agents[index].name)
                .navigationSubtitle("Agent Configuration")
            }
        case .none:
            GeneralSettingsView(defaultEditor: $defaultEditor)
                .navigationTitle("General")
                .navigationSubtitle("Default apps, layout, and toolbar")
        }
    }

    private func loadAgents() {
        agents = AgentRegistry.shared.getAllAgents()
    }

    private var proSidebarRow: some View {
        Button {
            selection = .pro
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.pink, Color.orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 18, height: 18)
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }

                Text("Aizen Pro")
                    .fontWeight(.semibold)

                Spacer()

                PillBadge(
                    text: proBadgeTitle,
                    color: proBadgeColor,
                    font: .caption2,
                    fontWeight: .semibold,
                    backgroundOpacity: 0.18,
                    lineLimit: 1,
                    minimumScaleFactor: 0.7
                )
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selection == .pro ? Color.white.opacity(0.06) : Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(selection == .pro ? 0.12 : 0.06), lineWidth: 1)
        )
    }

    private var proBadgeTitle: String {
        switch licenseManager.status {
        case .active, .offlineGrace:
            return "PRO"
        case .checking:
            return "CHECK"
        case .unlicensed, .expired, .invalid, .error:
            return "OFF"
        }
    }

    private var proBadgeColor: Color {
        switch licenseManager.status {
        case .active, .offlineGrace:
            return .orange
        case .checking:
            return .yellow
        case .unlicensed, .expired, .invalid, .error:
            return .red
        }
    }
}
