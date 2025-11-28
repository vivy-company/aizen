//
//  GeneralSettingsView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI

struct GeneralSettingsView: View {
    @Binding var defaultEditor: String
    @AppStorage("defaultTerminalBundleId") private var defaultTerminalBundleId: String?
    @AppStorage("defaultEditorBundleId") private var defaultEditorBundleId: String?
    @AppStorage("useCliEditor") private var useCliEditor = false
    @AppStorage("branchNameTemplates") private var branchNameTemplatesData: Data = Data()

    @ObservedObject private var appDetector = AppDetector.shared

    @State private var newTemplate = ""

    private var branchNameTemplates: [String] {
        get { (try? JSONDecoder().decode([String].self, from: branchNameTemplatesData)) ?? [] }
        set { branchNameTemplatesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var body: some View {
        Form {
            // Terminal Settings
            Section("Terminal") {
                Picker("Default Terminal", selection: $defaultTerminalBundleId) {
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
                .help("Choose which terminal application to use when opening worktrees")
            }

            // Editor Settings
            Section("Editor") {
                Picker("Default Editor", selection: $defaultEditorBundleId) {
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

            Section("Branch Templates") {
                ForEach(Array(branchNameTemplates.enumerated()), id: \.offset) { index, template in
                    HStack {
                        TextField("Template", text: Binding(
                            get: { template },
                            set: { updateTemplate(at: index, with: $0) }
                        ))
                        .textFieldStyle(.plain)

                        Button {
                            removeTemplate(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    TextField("Add template (e.g., aizen/, feature/)", text: $newTemplate)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            addTemplate()
                        }
                    Button {
                        addTemplate()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                    .disabled(newTemplate.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func addTemplate() {
        guard !newTemplate.isEmpty else { return }
        var templates = branchNameTemplates
        if !templates.contains(newTemplate) {
            templates.append(newTemplate)
            branchNameTemplatesData = (try? JSONEncoder().encode(templates)) ?? Data()
        }
        newTemplate = ""
    }

    private func updateTemplate(at index: Int, with value: String) {
        var templates = branchNameTemplates
        guard index < templates.count else { return }
        templates[index] = value
        branchNameTemplatesData = (try? JSONEncoder().encode(templates)) ?? Data()
    }

    private func removeTemplate(at index: Int) {
        var templates = branchNameTemplates
        guard index < templates.count else { return }
        templates.remove(at: index)
        branchNameTemplatesData = (try? JSONEncoder().encode(templates)) ?? Data()
    }
}
