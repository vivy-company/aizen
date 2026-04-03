import SwiftUI

extension GeneralSettingsView {
    @ViewBuilder
    var defaultAppsSection: some View {
        Section("Default Apps") {
            Picker("Terminal", selection: $defaultTerminalBundleId) {
                Text("System Default")
                    .tag(nil as String?)

                if !appDetector.getTerminals().isEmpty {
                    Divider()
                    ForEach(appDetector.getTerminals()) { app in
                        HStack {
                            if let icon = app.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 16, height: 16)
                            }
                            Text(app.name)
                        }
                        .tag(app.bundleIdentifier as String?)
                    }
                }
            }
            .help("Choose which terminal application to use when opening environments")

            Picker("Editor", selection: $defaultEditorBundleId) {
                Text("System Default")
                    .tag(nil as String?)

                if !appDetector.getEditors().isEmpty {
                    Divider()
                    ForEach(appDetector.getEditors()) { app in
                        HStack {
                            if let icon = app.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 16, height: 16)
                            }
                            Text(app.name)
                        }
                        .tag(app.bundleIdentifier as String?)
                    }
                }
            }
            .help("Choose which code editor to use when opening projects")

            Toggle("Use CLI command instead", isOn: $useCliEditor)
                .help("Use a command-line tool instead of an installed application")

            if useCliEditor {
                TextField(LocalizedStringKey("settings.general.editor.command"), text: $defaultEditor)
                    .help(LocalizedStringKey("settings.general.editor.help"))

                Text("settings.general.editor.examples")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
