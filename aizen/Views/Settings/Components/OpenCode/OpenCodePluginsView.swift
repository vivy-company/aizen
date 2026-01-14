//
//  OpenCodePluginsView.swift
//  aizen
//
//  OpenCode-specific plugin management UI
//  Handles oh-my-opencode and auth plugins with proper global npm install and config registration
//

import SwiftUI

struct OpenCodePluginsView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var plugins: [OpenCodePluginInfo] = []
    @State private var isLoading = true
    @State private var configExists = false
    @State private var configPath = ""
    @State private var omoConfigExists = false
    @State private var omoConfigPath = ""
    
    @State private var installingPlugin: String?
    @State private var installLogs = ""
    @State private var showingInstallSheet = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var installTask: Task<Void, Never>?
    @State private var pluginEnabledStates: [String: Bool] = [:]
    
    private let maxLogSize = 50_000
    
    var body: some View {
        Form {
            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading plugin status...")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                configSection
                pluginsSection
                omoConfigSection
            }
        }
        .formStyle(.grouped)
        .navigationTitle("OpenCode Plugins")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    dismiss()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
            }
        }
        .task {
            await loadPluginStatus()
        }
        .sheet(isPresented: $showingInstallSheet) {
            installProgressSheet
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }
    
    @ViewBuilder
    private var configSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Config File")
                        .font(.body)
                    Text(configPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if configExists {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.orange)
                }
            }
            
            HStack {
                Button("Open in Finder") {
                    Task {
                        await OpenCodeConfigService.shared.openConfigInFinder()
                    }
                }
                .disabled(!configExists)
            }
        } header: {
            Text("OpenCode Configuration")
        } footer: {
            if !configExists {
                Text("Config file will be created when you enable a plugin.")
            }
        }
    }
    
    @ViewBuilder
    private var pluginsSection: some View {
        Section {
            ForEach(plugins, id: \.name) { plugin in
                pluginRow(plugin)
            }
        } header: {
            Text("Available Plugins")
        } footer: {
            Text("Plugins are installed globally via npm and registered in OpenCode's config file.")
        }
    }
    
    @ViewBuilder
    private var omoConfigSection: some View {
        if plugins.first(where: { $0.name == "oh-my-opencode" })?.isInstalled == true {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Oh My OpenCode Config")
                            .font(.body)
                        Text(omoConfigPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    if omoConfigExists {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)
                    }
                }
                
                if omoConfigExists {
                    Button("Open in Editor") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: omoConfigPath))
                    }
                }
            } header: {
                Text("OMO Configuration")
            } footer: {
                if omoConfigExists {
                    Text("Edit to customize agents, hooks, MCPs, and more.")
                } else {
                    Text("Config file will be created automatically when OpenCode runs with OMO enabled.")
                }
            }
        }
    }
    
    @ViewBuilder
    private func pluginRow(_ plugin: OpenCodePluginInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(plugin.displayName)
                        .font(.body)
                    Text(plugin.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if plugin.isInstalled && plugin.isRegistered {
                    statusBadge("Active", color: .green)
                }
            }
            
            HStack(spacing: 12) {
                if plugin.isInstalled {
                    if let version = plugin.installedVersion {
                        Text("v\(version)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Toggle(isOn: Binding(
                        get: { 
                            pluginEnabledStates[plugin.name] ?? plugin.isRegistered 
                        },
                        set: { enabled in
                            pluginEnabledStates[plugin.name] = enabled
                            Task {
                                await togglePluginEnabled(plugin, enabled: enabled)
                            }
                        }
                    )) {
                        Text("Enabled")
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(.accentColor)
                    .labelsHidden()
                    
                    Button("Uninstall") {
                        Task {
                            await uninstallPlugin(plugin)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundStyle(.red)
                } else {
                    Spacer()
                    
                    Button("Install") {
                        Task {
                            await installPlugin(plugin)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private func statusBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
    
    @ViewBuilder
    private var installProgressSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text("Installing \(installingPlugin ?? "plugin")...")
                        .font(.headline)
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                }
                .padding(.horizontal)
                .padding(.top)
                
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(installLogs)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .id("logsBottom")
                    }
                    .onChange(of: installLogs) { _, _ in
                        withAnimation {
                            proxy.scrollTo("logsBottom", anchor: .bottom)
                        }
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(8)
                .padding(.horizontal)
                .padding(.bottom)
            }
            .frame(maxHeight: .infinity)
            .navigationTitle("Installing Plugin")
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(installingPlugin != nil)
    }
    
    private func loadPluginStatus() async {
        isLoading = true
        
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        configPath = "\(home)/.config/opencode/opencode.json"
        omoConfigPath = "\(home)/.config/opencode/oh-my-opencode.json"
        configExists = await OpenCodeConfigService.shared.configExists()
        omoConfigExists = FileManager.default.fileExists(atPath: omoConfigPath)
        plugins = await OpenCodePluginInstaller.shared.getAllPluginInfo()
        
        for plugin in plugins {
            if pluginEnabledStates[plugin.name] == nil {
                pluginEnabledStates[plugin.name] = plugin.isRegistered
            }
        }
        
        isLoading = false
    }
    
    private func installPlugin(_ plugin: OpenCodePluginInfo) async {
        installTask?.cancel()
        
        installTask = Task {
            installingPlugin = plugin.displayName
            installLogs = ""
            showingInstallSheet = true
            
            defer { installTask = nil }
            
            do {
                try await OpenCodePluginInstaller.shared.installAndRegister(plugin.name) { log in
                    Task { @MainActor in
                        installLogs += log
                        if installLogs.count > maxLogSize {
                            let trimAmount = installLogs.count - maxLogSize + 1000
                            installLogs = "... (trimmed \(trimAmount) bytes) ...\n" + installLogs.suffix(maxLogSize - 1000)
                        }
                    }
                }
                
                await MainActor.run {
                    showingInstallSheet = false
                    installingPlugin = nil
                    installLogs = ""
                }
                
                await loadPluginStatus()
            } catch {
                await MainActor.run {
                    showingInstallSheet = false
                    installingPlugin = nil
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
        
        await installTask?.value
    }
    
    private func togglePluginEnabled(_ plugin: OpenCodePluginInfo, enabled: Bool) async {
        do {
            try await OpenCodePluginInstaller.shared.setPluginEnabled(plugin.name, enabled: enabled)
            await loadPluginStatus()
        } catch {
            pluginEnabledStates[plugin.name] = !enabled
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
    
    private func uninstallPlugin(_ plugin: OpenCodePluginInfo) async {
        do {
            try await OpenCodePluginInstaller.shared.uninstallAndUnregister(plugin.name)
            await loadPluginStatus()
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
}

#Preview {
    NavigationStack {
        OpenCodePluginsView()
    }
}
