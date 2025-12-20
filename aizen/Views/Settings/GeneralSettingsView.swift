//
//  GeneralSettingsView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI
import os.log

struct GeneralSettingsView: View {
    private let logger = Logger.settings

    @Binding var defaultEditor: String

    // Default Apps
    @AppStorage("defaultTerminalBundleId") private var defaultTerminalBundleId: String?
    @AppStorage("defaultEditorBundleId") private var defaultEditorBundleId: String?
    @AppStorage("useCliEditor") private var useCliEditor = false

    // Layout
    @AppStorage("showChatTab") private var showChatTab = true
    @AppStorage("showTerminalTab") private var showTerminalTab = true
    @AppStorage("showFilesTab") private var showFilesTab = true
    @AppStorage("showBrowserTab") private var showBrowserTab = true

    // Toolbar
    @AppStorage("showOpenInApp") private var showOpenInApp = true
    @AppStorage("showGitStatus") private var showGitStatus = true
    @AppStorage("showXcodeBuild") private var showXcodeBuild = true

    @ObservedObject private var appDetector = AppDetector.shared
    @StateObject private var tabConfig = TabConfigurationManager.shared

    @State private var showingResetConfirmation = false

    var body: some View {
        Form {
            // MARK: - Default Apps

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
                .help("Choose which terminal application to use when opening worktrees")

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

            // MARK: - Layout

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
                .help("Tab shown when opening a worktree for the first time")

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

            // MARK: - Toolbar

            Section("Toolbar") {
                Toggle("Open in External App", isOn: $showOpenInApp)
                    .help("Show the 'Open in...' button for opening worktree in third-party apps")

                Toggle("Git Status", isOn: $showGitStatus)
                    .help("Show the Git status indicator")

                Toggle("Xcode Build", isOn: $showXcodeBuild)
                    .help("Show Xcode build button for projects with .xcodeproj or .xcworkspace")
            }

            // MARK: - Advanced

            Section("Advanced") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("settings.advanced.reset.title")
                        .font(.headline)

                    Text("settings.advanced.reset.description")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button(role: .destructive) {
                        showingResetConfirmation = true
                    } label: {
                        Label("settings.advanced.reset.button", systemImage: "trash")
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .formStyle(.grouped)
        .alert(LocalizedStringKey("settings.advanced.reset.alert.title"), isPresented: $showingResetConfirmation) {
            Button(LocalizedStringKey("settings.advanced.reset.alert.cancel"), role: .cancel) {}
            Button(LocalizedStringKey("settings.advanced.reset.alert.confirm"), role: .destructive) {
                resetApp()
            }
        } message: {
            Text("settings.advanced.reset.alert.message")
        }
    }

    // MARK: - Tab Visibility Helpers

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

    // MARK: - Reset App

    private func resetApp() {
        let bundleURL = Bundle.main.bundleURL
        let currentPID = ProcessInfo.processInfo.processIdentifier

        guard let bundleID = Bundle.main.bundleIdentifier else {
            logger.error("Cannot get bundle identifier")
            return
        }

        let coordinator = PersistenceController.shared.container.persistentStoreCoordinator
        let storeURL = coordinator.persistentStores.first?.url?.deletingLastPathComponent().path ?? ""
        let storeName = coordinator.persistentStores.first?.url?.deletingPathExtension().lastPathComponent ?? "aizen"

        let script = """
        #!/bin/bash

        kill -9 \(currentPID) 2>/dev/null || true
        sleep 0.5

        defaults delete "\(bundleID)" 2>/dev/null || true

        if [ -n "\(storeURL)" ]; then
            rm -f "\(storeURL)/\(storeName).sqlite"* 2>/dev/null || true
        fi

        rm -rf ~/Library/Application\\ Support/"\(bundleID)"/*.sqlite* 2>/dev/null || true
        rm -rf ~/Library/Containers/"\(bundleID)"/Data/Library/Application\\ Support/*.sqlite* 2>/dev/null || true

        open -n "\(bundleURL.path)"

        rm -f "$0"
        """

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("aizen-reset-\(UUID().uuidString).sh")

        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/bash")
            task.arguments = [scriptURL.path]
            try task.run()

            for window in NSApplication.shared.windows {
                window.close()
            }
        } catch {
            logger.error("Failed to create reset script: \(error.localizedDescription)")
        }
    }
}
