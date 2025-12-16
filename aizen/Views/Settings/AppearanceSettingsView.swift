import SwiftUI

struct AppearanceSettingsView: View {
    @AppStorage("showChatTab") private var showChatTab = true
    @AppStorage("showTerminalTab") private var showTerminalTab = true
    @AppStorage("showFilesTab") private var showFilesTab = true
    @AppStorage("showBrowserTab") private var showBrowserTab = true
    @AppStorage("showOpenInApp") private var showOpenInApp = true
    @AppStorage("showGitStatus") private var showGitStatus = true
    @AppStorage("showXcodeBuild") private var showXcodeBuild = true

    @StateObject private var tabConfig = TabConfigurationManager.shared

    var body: some View {
        Form {
            Section {
                List {
                    ForEach(tabConfig.tabOrder) { tab in
                        HStack(spacing: 12) {
                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(.tertiary)
                                .font(.system(size: 12))

                            Image(systemName: tab.icon)
                                .frame(width: 20)
                                .foregroundStyle(.secondary)

                            Text(LocalizedStringKey(tab.localizedKey))

                            Spacer()

                            Toggle("", isOn: visibilityBinding(for: tab.id))
                                .labelsHidden()
                        }
                        .padding(.vertical, 2)
                    }
                    .onMove { source, destination in
                        tabConfig.moveTab(from: source, to: destination)
                    }
                }
                .scrollDisabled(true)
                .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Tab Order & Visibility")
            } footer: {
                Text("Drag to reorder. Toggle to show or hide.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Default Tab", selection: Binding(
                    get: { tabConfig.defaultTab },
                    set: { tabConfig.setDefaultTab($0) }
                )) {
                    ForEach(tabConfig.tabOrder.filter { isTabVisible($0.id) }) { tab in
                        Label(LocalizedStringKey(tab.localizedKey), systemImage: tab.icon)
                            .tag(tab.id)
                    }
                }
                .help("Tab shown when opening a worktree for the first time")

                Button("Reset Tab Order") {
                    tabConfig.resetToDefaults()
                }
            } header: {
                Text("Default Behavior")
            }

            Section {
                Toggle("Open in External App", isOn: $showOpenInApp)
                    .help("Hide the 'Open in...' button for opening worktree in third-party apps like Finder")

                Toggle("Git Status", isOn: $showGitStatus)
                    .help("Hide the Git status indicator showing changes")

                Toggle("Xcode Build", isOn: $showXcodeBuild)
                    .help("Show Xcode build button for projects with .xcodeproj or .xcworkspace")
            } header: {
                Text("Toolbar Items")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Appearance")
    }

    private func visibilityBinding(for tabId: String) -> Binding<Bool> {
        switch tabId {
        case "chat": return $showChatTab
        case "terminal": return $showTerminalTab
        case "files": return $showFilesTab
        case "browser": return $showBrowserTab
        default: return .constant(true)
        }
    }

    private func isTabVisible(_ tabId: String) -> Bool {
        switch tabId {
        case "chat": return showChatTab
        case "terminal": return showTerminalTab
        case "files": return showFilesTab
        case "browser": return showBrowserTab
        default: return false
        }
    }
}

#Preview {
    AppearanceSettingsView()
}
