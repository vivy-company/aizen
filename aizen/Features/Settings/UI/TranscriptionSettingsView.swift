import SwiftUI
import AppKit

struct TranscriptionSettingsView: View {
    @AppStorage(TranscriptionSettingsKeys.provider) private var providerRaw = TranscriptionSettingsDefaults.provider.rawValue
    @AppStorage(TranscriptionSettingsKeys.mlxWhisperModelId) private var whisperModelId = TranscriptionSettingsDefaults.mlxWhisperModelId
    @AppStorage(TranscriptionSettingsKeys.mlxParakeetModelId) private var parakeetModelId = TranscriptionSettingsDefaults.mlxParakeetModelId

    @StateObject private var whisperManager: MLXModelStore
    @StateObject private var parakeetManager: MLXModelStore

    init() {
        let whisperId = TranscriptionSettingsStore.currentWhisperModelId()
        let parakeetId = TranscriptionSettingsStore.currentParakeetModelId()
        _whisperManager = StateObject(wrappedValue: MLXModelStore(kind: .whisper, modelId: whisperId))
        _parakeetManager = StateObject(wrappedValue: MLXModelStore(kind: .parakeetTDT, modelId: parakeetId))
    }

    private var provider: TranscriptionProvider {
        TranscriptionProvider(rawValue: providerRaw) ?? .system
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

    private var selectedPreset: MLXModelOption? {
        guard let configuration = activeConfiguration else { return nil }
        return configuration.presets.first(where: { $0.id == configuration.modelId.wrappedValue })
    }

    private var settingsSyncKey: String {
        "\(providerRaw)|\(whisperModelId)|\(parakeetModelId)"
    }

    var body: some View {
        Form {
            Section {
                Picker("Provider", selection: $providerRaw) {
                    Text("System (Apple Speech)").tag(TranscriptionProvider.system.rawValue)
                    Text("MLX Whisper").tag(TranscriptionProvider.mlxWhisper.rawValue)
                    Text("MLX Parakeet").tag(TranscriptionProvider.mlxParakeet.rawValue)
                }
            } header: {
                Text("Engine")
            } footer: {
                Text(engineDescription)
            }

            if let configuration = activeConfiguration {
                Section {
                    Picker("Model", selection: configuration.modelId) {
                        ForEach(configuration.presets) { preset in
                            Text(modelPickerTitle(for: preset)).tag(preset.id)
                        }
                    }

                    if let selectedPreset {
                        infoRow("Model", selectedPreset.title)
                        infoRow("Details", modelMetaLine(for: selectedPreset))
                        if let sizeText = downloadSizeText(for: configuration.manager) {
                            infoRow("Estimated Download", sizeText)
                        }
                        infoRow("Status", modelStatusText(for: configuration.manager))
                    }

                    if case .downloading(let progress) = configuration.manager.state {
                        ProgressView(value: progress)
                        Text(String(format: "%.0f%% downloaded", progress * 100))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {
                        Button(modelActionTitle(for: configuration.manager)) {
                            handleModelAction(configuration)
                        }
                        .disabled(modelActionDisabled(for: configuration.manager))

                        Button(configuration.resetTitle) {
                            configuration.modelId.wrappedValue = configuration.resetModelId
                        }

                        Spacer()
                    }

                    if let url = URL(string: "https://huggingface.co/\(configuration.modelId.wrappedValue)") {
                        Link("Open Selected Model on Hugging Face", destination: url)
                    }

                    if let collectionURL = configuration.collectionURL {
                        Link("Browse the Model Collection", destination: collectionURL)
                    }
                } header: {
                    Text(configuration.title)
                } footer: {
                    Text(configurationFooter(configuration))
                }

                Section {
                    HStack {
                        Text("Location")
                        Spacer()
                        Button("Reveal in Finder") {
                            revealModelFolder(directory: MLXModelStore.modelsRoot)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Path")
                            .foregroundStyle(.secondary)
                        Text(MLXModelStore.modelsRoot.path)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }

                    infoRow(
                        "Selected Model Size",
                        configuration.manager.isModelAvailable ? formatBytes(configuration.manager.localStorageBytes) : "Not downloaded"
                    )
                    infoRow(
                        "All MLX Models",
                        configuration.manager.totalStorageBytes > 0 ? formatBytes(configuration.manager.totalStorageBytes) : "Empty"
                    )
                } header: {
                    Text("Storage")
                }
            } else {
                Section {
                    Text("Switch to an MLX engine to pick a model, download it, and manage storage.")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Models")
                }
            }

            Section {
                Text("If MLX models can't run or are missing, transcription keeps working via Apple Speech.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Fallback")
            }
        }
        .formStyle(.grouped)
        .settingsSurface()
        .task(id: settingsSyncKey) {
            whisperManager.modelId = whisperModelId
            parakeetManager.modelId = parakeetModelId
        }
    }

    private var engineDescription: String {
        switch provider {
        case .system:
            return "Uses macOS speech recognition for the fastest setup."
        case .mlxWhisper:
            return "Runs Whisper on-device with MLX acceleration."
        case .mlxParakeet:
            return "Runs Parakeet TDT on-device with MLX acceleration."
        }
    }

    @ViewBuilder
    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func configurationFooter(_ configuration: ModelConfiguration) -> String {
        configuration.infoText
    }

    private func modelPickerTitle(for preset: MLXModelOption) -> String {
        var suffixes: [String] = []
        if let language = preset.languageLabel {
            suffixes.append(language)
        }
        suffixes.append(preset.precisionLabel)
        return suffixes.isEmpty ? preset.title : "\(preset.title) (\(suffixes.joined(separator: ", ")))"
    }

    private func modelActionTitle(for manager: MLXModelStore) -> String {
        switch manager.state {
        case .downloading:
            return "Downloading…"
        case .failed:
            return "Retry Download"
        default:
            return manager.isModelAvailable ? "Download Again" : "Download"
        }
    }

    private func modelActionDisabled(for manager: MLXModelStore) -> Bool {
        if case .downloading = manager.state { return true }
        return false
    }

    private func handleModelAction(_ configuration: ModelConfiguration) {
        configuration.manager.modelId = configuration.modelId.wrappedValue
        Task {
            await configuration.manager.downloadModel()
        }
    }

    private func modelStatusText(for manager: MLXModelStore) -> String {
        switch manager.state {
        case .idle:
            return manager.isModelAvailable ? "Ready" : "Not downloaded"
        case .downloading:
            return "Downloading"
        case .ready:
            return "Ready"
        case .failed(let message):
            return "Failed: \(message)"
        }
    }

    private func downloadSizeText(for manager: MLXModelStore) -> String? {
        guard let repoSizeBytes = manager.repoSizeBytes else { return nil }
        return formatBytes(repoSizeBytes)
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
}

private struct ModelConfiguration {
    let title: String
    let subtitle: String
    let modelId: Binding<String>
    let manager: MLXModelStore
    let presets: [MLXModelOption]
    let resetTitle: String
    let resetModelId: String
    let infoText: String
    let collectionURL: URL?
}
