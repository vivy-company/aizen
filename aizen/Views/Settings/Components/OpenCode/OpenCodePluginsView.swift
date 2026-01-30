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

    @State private var installingPlugin: OpenCodePluginInfo?
    @State private var installProgress = ""
    @State private var installLogs = ""
    @State private var installError: String?
    @State private var showingInstallSheet = false
    @State private var showInstallDetails = false

    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var installTask: Task<Void, Never>?
    @State private var pluginEnabledStates: [String: Bool] = [:]
    @State private var busyPlugins = Set<String>()

    private let maxLogSize = 50_000

    var body: some View {
        Form {
            Section(
                header: Text("Configuration"),
                footer: VStack(alignment: .leading, spacing: 4) {
                    if !configExists {
                        Text("Config file will be created when you enable a plugin.")
                    }
                    if shouldShowOMOConfig && !omoConfigExists {
                        Text("Config file will be created automatically when OpenCode runs with OMO enabled.")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            ) {
                configStatusView
            }

            Section(header: Text("Plugins")) {
                pluginsContent
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("OpenCode Plugins")
        .task {
            await loadPluginStatus(showLoading: true)
        }
        .sheet(isPresented: $showingInstallSheet) {
            installProgressSheet
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    dismiss()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .labelStyle(.iconOnly)
                .help("Back")
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    // MARK: - Header

    // MARK: - Config Status

    @ViewBuilder
    private var configStatusView: some View {
        VStack(alignment: .leading, spacing: 12) {
            configRow(
                title: "OpenCode Config",
                path: configPath,
                statusText: configExists ? "Active" : "Missing",
                statusColor: configExists ? .green : .orange,
                actionTitle: "Open in Finder",
                action: {
                    Task {
                        await OpenCodeConfigService.shared.openConfigInFinder()
                    }
                }
            )

            if shouldShowOMOConfig {
                configRow(
                    title: "Oh My OpenCode Config",
                    path: omoConfigPath,
                    statusText: omoConfigExists ? "Active" : "Auto-generate",
                    statusColor: omoConfigExists ? .green : .blue,
                    actionTitle: omoConfigExists ? "Open in Editor" : nil,
                    action: {
                        if omoConfigExists {
                            NSWorkspace.shared.open(URL(fileURLWithPath: omoConfigPath))
                        }
                    }
                )
            }
        }
    }

    private var shouldShowOMOConfig: Bool {
        plugins.first(where: { $0.name == "oh-my-opencode" })?.isInstalled == true
    }

    @ViewBuilder
    private func configRow(
        title: String,
        path: String,
        statusText: String,
        statusColor: Color,
        actionTitle: String?,
        action: @escaping () -> Void
    ) -> some View {
        LabeledContent {
            VStack(alignment: .leading, spacing: 6) {
                Text(path.isEmpty ? "Not configured" : path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 8) {
                    TagBadge(
                        text: statusText,
                        color: statusColor,
                        cornerRadius: 6,
                        font: .caption2,
                        horizontalPadding: 8,
                        verticalPadding: 3,
                        backgroundOpacity: 0.18
                    )

                    Spacer()

                    if let actionTitle = actionTitle {
                        Button(actionTitle) {
                            action()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        } label: {
            Text(title)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var pluginsContent: some View {
        if isLoading {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading plugin status...")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } else if plugins.isEmpty {
            Text("No plugins found")
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
        } else {
            ForEach(plugins, id: \.name) { plugin in
                pluginRow(plugin)
            }
        }
    }

    // MARK: - Plugin Rows

    @ViewBuilder
    private func pluginRow(_ plugin: OpenCodePluginInfo) -> some View {
        let accent = pluginAccentColor(for: plugin)
        let isEnabled = isPluginEnabled(plugin)
        let isBusy = busyPlugins.contains(plugin.name)
        LabeledContent {
            VStack(alignment: .trailing, spacing: 8) {
                Toggle(isOn: Binding(
                    get: { isPluginEnabled(plugin) },
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
                .disabled(isBusy)

                HStack(spacing: 8) {
                    if plugin.isInstalled && plugin.needsUpdate {
                        Button("Update") {
                            Task {
                                await installPlugin(plugin)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isBusy)
                    }

                    if plugin.isInstalled {
                        Button("Uninstall") {
                            Task {
                                await uninstallPlugin(plugin)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .foregroundStyle(.red)
                        .disabled(isBusy)
                    } else {
                        Button("Install") {
                            Task {
                                await installPlugin(plugin)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isBusy)
                    }
                }
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: pluginIconName(for: plugin))
                    .font(.title2)
                    .foregroundStyle(accent)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(plugin.displayName)
                            .font(.headline)

                        if plugin.isInstalled {
                            TagBadge(text: "Installed", color: .green, cornerRadius: 4, backgroundOpacity: 0.2)
                        }

                        if isEnabled {
                            TagBadge(text: "Enabled", color: .blue, cornerRadius: 4, backgroundOpacity: 0.2)
                        }

                        if plugin.needsUpdate {
                            TagBadge(text: "Update", color: .orange, cornerRadius: 4, backgroundOpacity: 0.2)
                        }
                    }

                    Text(plugin.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        if let version = plugin.installedVersion {
                            TagBadge(text: "v\(version)", color: .secondary)
                        }
                        if let latest = plugin.latestVersion, plugin.needsUpdate {
                            TagBadge(text: "Latest v\(latest)", color: .orange)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }

    private func pluginIconName(for plugin: OpenCodePluginInfo) -> String {
        if let iconName = plugin.iconName, !iconName.isEmpty {
            return iconName
        }
        switch plugin.name {
        case "oh-my-opencode":
            return "sparkles"
        case "opencode-openai-codex-auth":
            return "key.fill"
        case "opencode-gemini-auth":
            return "bolt.shield.fill"
        case "opencode-antigravity-auth":
            return "person.crop.circle.badge.checkmark"
        default:
            return "puzzlepiece.extension"
        }
    }

    private func pluginAccentColor(for plugin: OpenCodePluginInfo) -> Color {
        if let colorName = plugin.accentColorName,
           let color = colorFromName(colorName) {
            return color
        }
        switch plugin.name {
        case "oh-my-opencode":
            return .purple
        case "opencode-openai-codex-auth":
            return .blue
        case "opencode-gemini-auth":
            return .orange
        case "opencode-antigravity-auth":
            return .green
        default:
            return .secondary
        }
    }

    private func colorFromName(_ name: String) -> Color? {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix("#") {
            return Color(hex: normalized)
        }

        switch normalized {
        case "accent":
            return .accentColor
        case "blue":
            return .blue
        case "green":
            return .green
        case "orange":
            return .orange
        case "pink":
            return .pink
        case "purple":
            return .purple
        case "red":
            return .red
        case "secondary":
            return .secondary
        case "teal":
            return .teal
        case "yellow":
            return .yellow
        case "indigo":
            return .indigo
        case "gray", "grey":
            return .gray
        default:
            return nil
        }
    }

    private func isPluginEnabled(_ plugin: OpenCodePluginInfo) -> Bool {
        pluginEnabledStates[plugin.name] ?? plugin.isRegistered
    }

    // MARK: - Install Sheet

    @ViewBuilder
    private var installProgressSheet: some View {
        if let plugin = installingPlugin {
            OpenCodePluginInstallSheet(
                plugin: plugin,
                iconName: pluginIconName(for: plugin),
                iconColor: pluginAccentColor(for: plugin),
                isInstalling: installError == nil,
                progressText: installProgress,
                logs: installLogs,
                showDetails: $showInstallDetails,
                errorMessage: installError,
                onClose: { closeInstallSheet() }
            )
            .interactiveDismissDisabled(installError == nil)
        }
    }
    
    private func loadPluginStatus(showLoading: Bool) async {
        if showLoading {
            isLoading = true
        }

        let configService = OpenCodeConfigService.shared
        configPath = await configService.currentConfigPath()
        omoConfigPath = await configService.currentOMOConfigPath()
        configExists = await configService.configExists()
        omoConfigExists = FileManager.default.fileExists(atPath: omoConfigPath)
        plugins = await OpenCodePluginInstaller.shared.getAllPluginInfo()

        var refreshedStates: [String: Bool] = [:]
        for plugin in plugins {
            refreshedStates[plugin.name] = plugin.isRegistered
        }
        pluginEnabledStates = refreshedStates
        
        isLoading = false
    }
    
    private func installPlugin(_ plugin: OpenCodePluginInfo) async {
        installTask?.cancel()

        installTask = Task {
            _ = await MainActor.run {
                busyPlugins.insert(plugin.name)
            }
            defer {
                Task { @MainActor in
                    busyPlugins.remove(plugin.name)
                }
            }

            installingPlugin = plugin
            installLogs = ""
            installProgress = "Preparing installation..."
            installError = nil
            showInstallDetails = false
            showingInstallSheet = true
            
            defer { installTask = nil }
            
            do {
                try await OpenCodePluginInstaller.shared.installAndRegister(plugin.name) { log in
                    Task { @MainActor in
                        appendInstallLog(log)
                    }
                }
                
                await MainActor.run {
                    closeInstallSheet()
                }
                
                await loadPluginStatus(showLoading: false)
            } catch {
                await MainActor.run {
                    installError = error.localizedDescription
                }
            }
        }
        
        await installTask?.value
    }
    
    private func togglePluginEnabled(_ plugin: OpenCodePluginInfo, enabled: Bool) async {
        _ = await MainActor.run {
            busyPlugins.insert(plugin.name)
        }
        defer {
            Task { @MainActor in
                busyPlugins.remove(plugin.name)
            }
        }

        do {
            try await OpenCodePluginInstaller.shared.setPluginEnabled(plugin.name, enabled: enabled)
            await loadPluginStatus(showLoading: false)
        } catch {
            pluginEnabledStates[plugin.name] = !enabled
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
    
    private func uninstallPlugin(_ plugin: OpenCodePluginInfo) async {
        _ = await MainActor.run {
            busyPlugins.insert(plugin.name)
        }
        defer {
            Task { @MainActor in
                busyPlugins.remove(plugin.name)
            }
        }

        do {
            try await OpenCodePluginInstaller.shared.uninstallAndUnregister(plugin.name)
            await loadPluginStatus(showLoading: false)
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private func appendInstallLog(_ log: String) {
        installLogs += log
        if installLogs.count > maxLogSize {
            let trimAmount = installLogs.count - maxLogSize + 1000
            installLogs = "... (trimmed \(trimAmount) bytes) ...\n" + installLogs.suffix(maxLogSize - 1000)
        }
        if let line = installLogs.split(whereSeparator: \.isNewline).last {
            installProgress = String(line)
        }
    }

    private func closeInstallSheet() {
        showingInstallSheet = false
        installingPlugin = nil
        installProgress = ""
        installLogs = ""
        installError = nil
    }
}

// MARK: - Liquid Glass Helpers

private struct GlassPanel<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat
    let tint: Color?
    let scrimOpacity: Double
    let fallbackColor: Color
    let interactive: Bool
    let strokeOpacity: Double
    @ViewBuilder var content: () -> Content

    init(
        cornerRadius: CGFloat,
        tint: Color? = nil,
        scrimOpacity: Double = 0.08,
        fallbackColor: Color = Color(nsColor: .controlBackgroundColor),
        interactive: Bool = false,
        strokeOpacity: Double = 0.12,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.tint = tint
        self.scrimOpacity = scrimOpacity
        self.fallbackColor = fallbackColor
        self.interactive = interactive
        self.strokeOpacity = strokeOpacity
        self.content = content
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content()
            .background { backgroundView(shape: shape) }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(strokeColor, lineWidth: 1)
            }
    }

    @ViewBuilder
    private func backgroundView(shape: RoundedRectangle) -> some View {
        ZStack {
            shape
                .fill(tint ?? fallbackColor)
                .allowsHitTesting(false)

            shape
                .fill(scrimColor)
                .allowsHitTesting(false)
        }
    }

    private var scrimColor: Color {
        colorScheme == .dark ? .black.opacity(scrimOpacity) : .white.opacity(scrimOpacity * 0.6)
    }

    private var strokeColor: Color {
        colorScheme == .dark ? .white.opacity(strokeOpacity) : .black.opacity(strokeOpacity * 0.7)
    }
}

private extension View {
    @ViewBuilder
    func opencodeButtonStyle(prominent: Bool) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else {
            if prominent {
                buttonStyle(.borderedProminent)
            } else {
                buttonStyle(.bordered)
            }
        }
    }
}

private struct OpenCodePluginInstallSheet: View {
    let plugin: OpenCodePluginInfo
    let iconName: String
    let iconColor: Color
    let isInstalling: Bool
    let progressText: String
    let logs: String
    @Binding var showDetails: Bool
    let errorMessage: String?
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 48))
                    .foregroundStyle(iconColor)

                Text(isInstalling ? "Installing Plugin" : "Install Failed")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Setting up \(plugin.displayName)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if plugin.installedVersion != nil || plugin.latestVersion != nil {
                GlassPanel(cornerRadius: 10, tint: iconColor.opacity(0.18), scrimOpacity: 0.06) {
                    VStack(spacing: 12) {
                        if let current = plugin.installedVersion {
                            versionRow(label: "Current version:", value: current)
                        }
                        if let latest = plugin.latestVersion {
                            versionRow(label: "Latest version:", value: latest, accent: true)
                        }
                    }
                    .padding(12)
                }
            }

            if isInstalling {
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(progressText.isEmpty ? "Installing..." : progressText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
            }

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }

            if !logs.isEmpty {
                DisclosureGroup(isExpanded: $showDetails) {
                    GlassPanel(cornerRadius: 10, tint: nil, scrimOpacity: 0.04, fallbackColor: Color(nsColor: .textBackgroundColor)) {
                        ScrollView {
                            Text(logs)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .frame(maxHeight: 160)
                    }
                } label: {
                    Text("Installation Log")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
            }

            HStack(spacing: 12) {
                Button("Close") {
                    onClose()
                }
                .opencodeButtonStyle(prominent: false)
                .disabled(isInstalling)
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 420)
    }

    private func versionRow(label: String, value: String, accent: Bool = false) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .foregroundColor(accent ? .blue : .primary)
        }
    }
}

#Preview {
    NavigationStack {
        OpenCodePluginsView()
    }
}
