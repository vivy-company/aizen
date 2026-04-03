//
//  GeneralSettingsView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI
import os.log
import AppKit
import CoreData

enum AppearanceMode: String, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// View modifier that applies the app-wide appearance setting
struct AppearanceModifier: ViewModifier {
    @AppStorage("appearanceMode") var appearanceMode: String = AppearanceMode.system.rawValue

    private var colorScheme: ColorScheme? {
        switch AppearanceMode(rawValue: appearanceMode) ?? .system {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(colorScheme)
            .id("appearance-\(appearanceMode)")
    }
}

// MARK: - Appearance Picker View

struct AppearancePickerView: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppearanceMode.allCases, id: \.self) { mode in
                AppearanceOptionView(
                    mode: mode,
                    isSelected: selection == mode.rawValue
                )
                .frame(maxWidth: .infinity)
                .onTapGesture {
                    selection = mode.rawValue
                }
            }
        }
    }
}

struct AppearanceOptionView: View {
    let mode: AppearanceMode
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Preview card
                AppearancePreviewCard(mode: mode)
                    .frame(width: 100, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                    )
                    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
            }

            Text(mode.label)
                .font(.caption)
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
    }
}

struct AppearancePreviewCard: View {
    let mode: AppearanceMode

    var body: some View {
        switch mode {
        case .system:
            // Split view showing both light and dark
            HStack(spacing: 0) {
                miniWindowPreview(isDark: false)
                miniWindowPreview(isDark: true)
            }
        case .light:
            miniWindowPreview(isDark: false)
        case .dark:
            miniWindowPreview(isDark: true)
        }
    }

    private func miniWindowPreview(isDark: Bool) -> some View {
        let bgColor = isDark ? Color(white: 0.15) : Color(white: 0.95)
        let windowBg = isDark ? Color(white: 0.22) : Color.white
        let sidebarBg = isDark ? Color(white: 0.18) : Color(white: 0.92)
        let accentBar = isDark ? Color.pink.opacity(0.8) : Color.pink
        let dotColors: [Color] = [.red, .yellow, .green]

        return ZStack {
            // Background
            bgColor

            // Mini window
            VStack(spacing: 0) {
                // Title bar
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(dotColors[i])
                            .frame(width: 5, height: 5)
                    }
                    Spacer()
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(windowBg)

                // Content area
                HStack(spacing: 0) {
                    // Sidebar
                    Rectangle()
                        .fill(sidebarBg)
                        .frame(width: 16)

                    // Main content
                    VStack(spacing: 4) {
                        // Top bar accent
                        RoundedRectangle(cornerRadius: 2)
                            .fill(accentBar)
                            .frame(height: 8)
                            .padding(.horizontal, 4)
                            .padding(.top, 4)

                        Spacer()
                    }
                    .background(windowBg)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .padding(6)
        }
    }
}

// MARK: - Language

enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case english = "en"
    case chinese = "zh-Hans"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return String(localized: "System")
        case .english: return "English"
        case .chinese: return "简体中文"
        }
    }
}

struct GeneralSettingsView: View {
    private let logger = Logger.settings

    @Binding var defaultEditor: String

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Workspace.order, ascending: true)],
        animation: .default
    )
    private var workspaces: FetchedResults<Workspace>

    // Appearance
    @AppStorage("appearanceMode") var appearanceMode: String = AppearanceMode.system.rawValue

    // Language
    @State var selectedLanguage: AppLanguage = .system
    @State var showingRestartAlert = false
    @State var hasLoadedLanguage = false

    // Default Apps
    @AppStorage("defaultTerminalBundleId") private var defaultTerminalBundleId: String?
    @AppStorage("defaultEditorBundleId") private var defaultEditorBundleId: String?
    @AppStorage("useCliEditor") private var useCliEditor = false
    @AppStorage("defaultCloneLocation") private var defaultCloneLocation = "~/.aizen/repos"
    @AppStorage("defaultWorkspaceId") private var defaultWorkspaceId = ""

    // Layout
    @AppStorage("showChatTab") var showChatTab = true
    @AppStorage("showTerminalTab") var showTerminalTab = true
    @AppStorage("showFilesTab") var showFilesTab = true
    @AppStorage("showBrowserTab") var showBrowserTab = true

    // Toolbar
    @AppStorage("showOpenInApp") var showOpenInApp = true
    @AppStorage("showGitStatus") var showGitStatus = true
    @AppStorage("showXcodeBuild") var showXcodeBuild = true

    @ObservedObject private var appDetector = AppDetector.shared
    @StateObject var tabConfig = TabConfigurationStore.shared

    @State private var showingResetConfirmation = false
    @State private var cliStatus = CLISymlinkService.status()
    @State private var showingCLIAlert = false
    @State private var cliAlertMessage = ""

    var body: some View {
        Form {
            appearanceSection

            languageSection

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

            // MARK: - Repositories

            Section("Projects") {
                HStack(spacing: 12) {
                    TextField("Default Clone Location", text: $defaultCloneLocation)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose") {
                        selectDefaultCloneLocation()
                    }
                }
                .help("Used by the CLI when cloning projects without --destination")

                Picker("Default Workspace", selection: $defaultWorkspaceId) {
                    Text("None")
                        .tag("")
                    ForEach(workspaces) { workspace in
                        Text(workspace.name ?? "")
                            .tag(workspace.id?.uuidString ?? "")
                    }
                }
                .help("Used by the CLI when adding projects without --workspace")
            }

            layoutSection

            toolbarSection

            // MARK: - CLI

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    if let linkPath = cliStatus.linkPath {
                        Text("Symlink: \(linkPath)")
                            .font(.footnote)
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                    }

                    if let targetPath = cliStatus.targetPath {
                        Text("Target: \(targetPath)")
                            .font(.footnote)
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {
                        Button(cliStatus.isInstalled ? "Reinstall CLI" : "Install CLI") {
                            installCLI()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Refresh") {
                            refreshCLIStatus()
                        }
                    }
                }
            } header: {
                HStack(spacing: 8) {
                    Text("CLI")
                    Text(cliStatus.isInstalled ? "Installed" : "Not installed")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(cliStatus.isInstalled ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                        .foregroundStyle(cliStatus.isInstalled ? .green : .orange)
                        .clipShape(Capsule())
                }
            }

            // MARK: - Danger Zone

            Section {
                Text("settings.advanced.reset.description")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button(role: .destructive) {
                    showingResetConfirmation = true
                } label: {
                    Label("settings.advanced.reset.button", systemImage: "trash")
                }
            } header: {
                Text("settings.advanced.reset.title")
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .settingsSurface()
        .onAppear {
            loadCurrentLanguage()
            refreshCLIStatus()
        }
        .alert(LocalizedStringKey("settings.advanced.reset.alert.title"), isPresented: $showingResetConfirmation) {
            Button(LocalizedStringKey("settings.advanced.reset.alert.cancel"), role: .cancel) {}
            Button(LocalizedStringKey("settings.advanced.reset.alert.confirm"), role: .destructive) {
                resetApp()
            }
        } message: {
            Text("settings.advanced.reset.alert.message")
        }
        .alert("CLI Installation", isPresented: $showingCLIAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(cliAlertMessage)
        }
        .alert("Restart Required", isPresented: $showingRestartAlert) {
            Button("Later", role: .cancel) {}
            Button("Restart Now") {
                restartApp()
            }
        } message: {
            Text("Please restart the app to apply the language change.")
        }
    }

    // MARK: - CLI

    private func refreshCLIStatus() {
        cliStatus = CLISymlinkService.status()
    }

    private func installCLI() {
        let result = CLISymlinkService.install()
        cliAlertMessage = result.message
        showingCLIAlert = true
        refreshCLIStatus()
    }

    private func selectDefaultCloneLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select default clone location"

        if panel.runModal() == .OK, let url = panel.url {
            defaultCloneLocation = url.path
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
