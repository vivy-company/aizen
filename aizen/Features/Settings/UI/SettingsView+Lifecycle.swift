import SwiftUI

extension SettingsView {
    @ViewBuilder
    var detailContainer: some View {
        Group {
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
    }

    func settingsViewLifecycle() -> some ViewModifier {
        SettingsViewLifecycleModifier(
            showingAddCustomAgent: $showingAddCustomAgent,
            selection: $selection,
            loadAgents: loadAgents
        )
    }

    func loadAgents() {
        let updatedAgents = AgentRegistry.shared.getAllAgents()
        agents = updatedAgents

        if case .agent(let agentId) = selection,
           !updatedAgents.contains(where: { $0.id == agentId }) {
            selection = updatedAgents.first.map { .agent($0.id) } ?? .general
        }
    }
}

private struct SettingsViewLifecycleModifier: ViewModifier {
    @Binding var showingAddCustomAgent: Bool
    @Binding var selection: SettingsSelection?
    let loadAgents: () -> Void

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .principal) { Text("") }
            }
            .settingsSheetChrome()
            .settingsNativeToolbarGlass()
            .navigationSplitViewStyle(.balanced)
            .frame(minWidth: 860, minHeight: 500)
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
}
