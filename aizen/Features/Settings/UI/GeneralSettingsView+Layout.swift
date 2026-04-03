import SwiftUI

extension GeneralSettingsView {
    @ViewBuilder
    var layoutSection: some View {
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

            Picker("Default Tab", selection: Binding(
                get: { tabConfig.defaultTab },
                set: { tabConfig.setDefaultTab($0) }
            )) {
                ForEach(tabConfig.tabOrder.filter { isTabVisible($0.id) }) { tab in
                    Label(LocalizedStringKey(tab.localizedKey), systemImage: tab.icon)
                        .tag(tab.id)
                }
            }
            .help("Tab shown when opening an environment for the first time")

            Button("Reset Tab Order") {
                tabConfig.resetToDefaults()
            }
        } header: {
            Text("Layout")
        } footer: {
            Text("Drag to reorder. Toggle to show or hide.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    var toolbarSection: some View {
        Section("Toolbar") {
            Toggle("Open in External App", isOn: $showOpenInApp)
                .help("Show the 'Open in...' button for opening environment in third-party apps")

            Toggle("Git Status", isOn: $showGitStatus)
                .help("Show the Git status indicator")

            Toggle("Xcode Build", isOn: $showXcodeBuild)
                .help("Show Xcode build button for projects with .xcodeproj or .xcworkspace")
        }
    }

    func visibilityBinding(for tabId: String) -> Binding<Bool> {
        switch tabId {
        case "chat": return $showChatTab
        case "terminal": return $showTerminalTab
        case "files": return $showFilesTab
        case "browser": return $showBrowserTab
        default: return .constant(true)
        }
    }

    func isTabVisible(_ tabId: String) -> Bool {
        switch tabId {
        case "chat": return showChatTab
        case "terminal": return showTerminalTab
        case "files": return showFilesTab
        case "browser": return showBrowserTab
        default: return false
        }
    }
}
