import SwiftUI
import AppKit
import os.log

struct TranscriptionSettingsView: View {
    private let logger = Logger.settings
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage(TranscriptionSettingsKeys.provider) private var providerRaw = TranscriptionSettingsDefaults.provider.rawValue
    @AppStorage(TranscriptionSettingsKeys.mlxWhisperModelId) private var whisperModelId = TranscriptionSettingsDefaults.mlxWhisperModelId
    @AppStorage(TranscriptionSettingsKeys.mlxParakeetModelId) private var parakeetModelId = TranscriptionSettingsDefaults.mlxParakeetModelId

    @StateObject private var whisperManager: MLXModelManager
    @StateObject private var parakeetManager: MLXModelManager
    @State private var showMoreModels = false

    init() {
        let whisperId = TranscriptionSettingsStore.currentWhisperModelId()
        let parakeetId = TranscriptionSettingsStore.currentParakeetModelId()
        _whisperManager = StateObject(wrappedValue: MLXModelManager(kind: .whisper, modelId: whisperId))
        _parakeetManager = StateObject(wrappedValue: MLXModelManager(kind: .parakeetTDT, modelId: parakeetId))
    }

    private var provider: TranscriptionProvider {
        TranscriptionProvider(rawValue: providerRaw) ?? .system
    }

    private var mlxSupported: Bool {
        MLXAudioSupport.isSupported
    }

    private var activeConfiguration: ModelConfiguration? {
        switch provider {
        case .mlxWhisper:
            return ModelConfiguration(
                title: "MLX Whisper Model",
                subtitle: "Download and manage Whisper model files.",
                modelId: $whisperModelId,
                manager: whisperManager,
                presets: MLXModelCatalog.whisperPresets,
                resetTitle: "Reset to Tiny",
                resetModelId: TranscriptionSettingsDefaults.mlxWhisperModelId,
                infoText: "Paste any Hugging Face model ID to use a custom Whisper model.",
                collectionURL: URL(string: "https://huggingface.co/collections/mlx-community/openai-whisper-speech-recognition-models-in-mlx-format-6501b6e1a6f8818e6f2a9bb2")
            )
        case .mlxParakeet:
            return ModelConfiguration(
                title: "MLX Parakeet Model",
                subtitle: "Download and manage Parakeet TDT model files.",
                modelId: $parakeetModelId,
                manager: parakeetManager,
                presets: MLXModelCatalog.parakeetPresets,
                resetTitle: "Reset to Default",
                resetModelId: TranscriptionSettingsDefaults.mlxParakeetModelId,
                infoText: "Parakeet models are large; downloads can take a while.",
                collectionURL: nil
            )
        default:
            return nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                engineCard

                if let configuration = activeConfiguration {
                    modelCard(configuration)
                    storageCard(manager: configuration.manager)
                } else {
                    modelPlaceholderCard
                }

                fallbackCard
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            whisperManager.modelId = whisperModelId
            parakeetManager.modelId = parakeetModelId
            whisperManager.refreshStatus()
            parakeetManager.refreshStatus()

            if (provider == .mlxWhisper || provider == .mlxParakeet) && !mlxSupported {
                providerRaw = TranscriptionProvider.system.rawValue
            }
        }
        .onChange(of: providerRaw) { _, newValue in
            if (newValue == TranscriptionProvider.mlxWhisper.rawValue || newValue == TranscriptionProvider.mlxParakeet.rawValue) && !mlxSupported {
                logger.warning("MLX not supported on this Mac; reverting to system provider")
                providerRaw = TranscriptionProvider.system.rawValue
                return
            }
            showMoreModels = false
            if newValue == TranscriptionProvider.mlxWhisper.rawValue {
                whisperManager.refreshStatus()
            } else if newValue == TranscriptionProvider.mlxParakeet.rawValue {
                parakeetManager.refreshStatus()
            }
        }
        .onChange(of: whisperModelId) { _, newValue in
            whisperManager.modelId = newValue
            whisperManager.refreshStatus()
        }
        .onChange(of: parakeetModelId) { _, newValue in
            parakeetManager.modelId = newValue
            parakeetManager.refreshStatus()
        }
    }

    private var engineCard: some View {
        SettingsCard(
            title: "Engine",
            subtitle: "Pick how Aizen transcribes your audio."
        ) {
            VStack(spacing: 12) {
                engineOption(
                    title: "System (Apple Speech)",
                    subtitle: "Fast setup, uses macOS speech recognition.",
                    systemImage: "mic.fill",
                    tag: TranscriptionProvider.system.rawValue,
                    isDisabled: false
                )
                engineOption(
                    title: "MLX Whisper",
                    subtitle: "On-device Whisper with MLX acceleration.",
                    systemImage: "waveform.circle.fill",
                    tag: TranscriptionProvider.mlxWhisper.rawValue,
                    isDisabled: !mlxSupported
                )
                engineOption(
                    title: "MLX Parakeet",
                    subtitle: "On-device Parakeet TDT (larger model, high accuracy).",
                    systemImage: "waveform.badge.mic",
                    tag: TranscriptionProvider.mlxParakeet.rawValue,
                    isDisabled: !mlxSupported
                )
            }
        }
    }

    private func modelCard(_ configuration: ModelConfiguration) -> some View {
        let option = MLXModelCatalog.option(for: configuration.modelId.wrappedValue, kind: configuration.manager.kind)
        let customInfo = option?.summary ?? configuration.infoText

        return SettingsCard(title: configuration.title, subtitle: configuration.subtitle) {
            VStack(alignment: .leading, spacing: 16) {
                modelSelectionSection(
                    presets: configuration.presets,
                    selection: configuration.modelId
                )

                HStack(spacing: 12) {
                    Button(configuration.resetTitle) {
                        configuration.modelId.wrappedValue = configuration.resetModelId
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    if let url = URL(string: "https://huggingface.co/\(configuration.modelId.wrappedValue)") {
                        Link("Open on Hugging Face", destination: url)
                            .font(.caption)
                    }
                    if let collectionURL = configuration.collectionURL {
                        Link("Browse the collection", destination: collectionURL)
                            .font(.caption)
                    }
                    Spacer()
                }

                Text(customInfo)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !mlxSupported {
                    Text("MLX models require Apple Silicon. Apple Speech will be used on Intel Macs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!mlxSupported)
        }
    }

    private var modelPlaceholderCard: some View {
        SettingsCard(
            title: "Models",
            subtitle: "Pick MLX Whisper or Parakeet to manage downloadable models."
        ) {
            HStack(spacing: 10) {
                Image(systemName: "square.stack.3d.down.forward.fill")
                    .foregroundStyle(.secondary)
                Text("Switch to an MLX engine to pick a model, download it, and manage storage.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var fallbackCard: some View {
        SettingsCard(
            title: "Fallback",
            subtitle: ""
        ) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .foregroundStyle(.secondary)
                Text("If MLX models can't run or are missing, transcription keeps working via Apple Speech.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func modelSelectionSection(presets: [MLXModelOption], selection: Binding<String>) -> some View {
        let primary = presets.filter { $0.isPrimary }
        let secondary = presets.filter { !$0.isPrimary }

        return VStack(alignment: .leading, spacing: 12) {
            modelList(presets: primary.isEmpty ? presets : primary, selection: selection)

            if !secondary.isEmpty {
                DisclosureGroup(isExpanded: $showMoreModels) {
                    modelList(presets: secondary, selection: selection)
                        .padding(.top, 8)
                } label: {
                    HStack {
                        Text("More models")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("EN-only + quantized")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func modelList(presets: [MLXModelOption], selection: Binding<String>) -> some View {
        LazyVStack(spacing: 8) {
            ForEach(presets) { preset in
                modelOptionRow(preset, selection: selection)
            }
        }
    }

    private func modelOptionRow(_ preset: MLXModelOption, selection: Binding<String>) -> some View {
        let isSelected = selection.wrappedValue == preset.id
        let isAvailable = MLXModelManager.isModelAvailable(kind: preset.kind, modelId: preset.id)
        let canSelect = isAvailable || isSelected
        let isDownloading: Bool = {
            guard isSelected else { return false }
            if case .downloading = activeManagerState(for: preset.kind) { return true }
            return false
        }()
        let isFailed: Bool = {
            guard isSelected else { return false }
            if case .failed = activeManagerState(for: preset.kind) { return true }
            return false
        }()

        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary.opacity(0.5))
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text(preset.title)
                    .font(.headline)
                Text(preset.summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(modelMetaLine(for: preset))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ModelSizeBadge(modelId: preset.id)
            }

            Spacer()

            if isDownloading, let progress = activeProgress(for: preset.kind) {
                VStack(alignment: .trailing, spacing: 4) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(width: 90)
                    Text(String(format: "%.0f%%", progress * 100))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if isAvailable {
                PillBadge(text: "Ready", color: .green, fontWeight: .semibold, backgroundOpacity: 0.18)
            } else if isFailed {
                Button {
                    let manager = activeManager(for: preset.kind)
                    manager.modelId = preset.id
                    selection.wrappedValue = preset.id
                    Task { await manager.downloadModel() }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button {
                    let manager = activeManager(for: preset.kind)
                    manager.modelId = preset.id
                    selection.wrappedValue = preset.id
                    Task { await manager.downloadModel() }
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : cardFillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            if canSelect {
                selection.wrappedValue = preset.id
            }
        }
        .opacity(canSelect ? 1 : 0.65)
    }

    private func engineOption(
        title: String,
        subtitle: String,
        systemImage: String,
        tag: String,
        isDisabled: Bool
    ) -> some View {
        Button {
            providerRaw = tag
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 20))
                    .foregroundStyle(isDisabled ? .secondary : .primary)
                    .frame(width: 28, height: 28, alignment: .center)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: providerRaw == tag ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(providerRaw == tag ? Color.accentColor : .secondary.opacity(0.5))
                    .frame(width: 24, height: 24, alignment: .center)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(providerRaw == tag ? Color.accentColor.opacity(0.12) : cardFillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(providerRaw == tag ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
    }

    private func storageCard(manager: MLXModelManager) -> some View {
        SettingsCard(
            title: "Storage",
            subtitle: ""
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Location", systemImage: "internaldrive")
                        .font(.subheadline)
                    Spacer()
                    Button("Reveal in Finder") {
                        revealModelFolder(directory: MLXModelManager.modelsRoot)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Text(MLXModelManager.modelsRoot.path)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)

                HStack {
                    Label("Selected model", systemImage: "externaldrive")
                        .font(.subheadline)
                    Spacer()
                    Text(manager.isModelAvailable ? formatBytes(manager.localStorageBytes) : "Not downloaded")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Label("All MLX models", systemImage: "internaldrive.fill")
                        .font(.subheadline)
                    Spacer()
                    Text(manager.totalStorageBytes > 0 ? formatBytes(manager.totalStorageBytes) : "Empty")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var cardFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)
    }

    private func revealModelFolder(directory: URL) {
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.includesUnit = true
        formatter.includesCount = true
        return formatter.string(fromByteCount: bytes)
    }

    private func modelMetaLine(for preset: MLXModelOption) -> String {
        var parts = [preset.sizeLabel, preset.precisionLabel]
        if let language = preset.languageLabel {
            parts.append(language)
        }
        return parts.joined(separator: " • ")
    }

    private func activeManager(for kind: MLXModelKind) -> MLXModelManager {
        switch kind {
        case .whisper:
            return whisperManager
        case .parakeetTDT:
            return parakeetManager
        }
    }

    private func activeManagerState(for kind: MLXModelKind) -> MLXModelManager.DownloadState {
        activeManager(for: kind).state
    }

    private func activeProgress(for kind: MLXModelKind) -> Double? {
        switch activeManagerState(for: kind) {
        case .downloading(let progress):
            return progress
        default:
            return nil
        }
    }
}

private struct ModelConfiguration {
    let title: String
    let subtitle: String
    let modelId: Binding<String>
    let manager: MLXModelManager
    let presets: [MLXModelOption]
    let resetTitle: String
    let resetModelId: String
    let infoText: String
    let collectionURL: URL?
}

private struct ModelSizeBadge: View {
    let modelId: String
    @State private var sizeBytes: Int64?
    @State private var isLoading = true

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task(id: modelId) {
            isLoading = true
            sizeBytes = await MLXModelSizeCache.shared.size(for: modelId)
            isLoading = false
        }
    }

    private var label: String {
        if isLoading {
            return "Estimated download size: calculating..."
        }
        guard let sizeBytes else { return "Estimated download size: unavailable" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB, .useGB]
        let pretty = formatter.string(fromByteCount: sizeBytes)
        return "Estimated download size: \(pretty)"
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct GlassButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(0.15))
        )
    }
}
