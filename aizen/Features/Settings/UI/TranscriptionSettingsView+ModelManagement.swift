import SwiftUI
import AppKit

extension TranscriptionSettingsView {
    var activeConfiguration: ModelConfiguration? {
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

    var selectedPreset: MLXModelOption? {
        guard let configuration = activeConfiguration else { return nil }
        return configuration.presets.first(where: { $0.id == configuration.modelId.wrappedValue })
    }

    var engineDescription: String {
        switch provider {
        case .system:
            return "Uses macOS speech recognition for the fastest setup."
        case .mlxWhisper:
            return "Runs Whisper on-device with MLX acceleration."
        case .mlxParakeet:
            return "Runs Parakeet TDT on-device with MLX acceleration."
        }
    }

    func configurationFooter(_ configuration: ModelConfiguration) -> String {
        configuration.infoText
    }

    func modelPickerTitle(for preset: MLXModelOption) -> String {
        var suffixes: [String] = []
        if let language = preset.languageLabel {
            suffixes.append(language)
        }
        suffixes.append(preset.precisionLabel)
        return suffixes.isEmpty ? preset.title : "\(preset.title) (\(suffixes.joined(separator: ", ")))"
    }

    func modelActionTitle(for manager: MLXModelStore) -> String {
        switch manager.state {
        case .downloading:
            return "Downloading…"
        case .failed:
            return "Retry Download"
        default:
            return manager.isModelAvailable ? "Download Again" : "Download"
        }
    }

    func modelActionDisabled(for manager: MLXModelStore) -> Bool {
        if case .downloading = manager.state { return true }
        return false
    }

    func handleModelAction(_ configuration: ModelConfiguration) {
        configuration.manager.modelId = configuration.modelId.wrappedValue
        Task {
            await configuration.manager.downloadModel()
        }
    }

    func modelStatusText(for manager: MLXModelStore) -> String {
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

    func downloadSizeText(for manager: MLXModelStore) -> String? {
        guard let repoSizeBytes = manager.repoSizeBytes else { return nil }
        return formatBytes(repoSizeBytes)
    }

    func revealModelFolder(directory: URL) {
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }

    func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.includesUnit = true
        formatter.includesCount = true
        return formatter.string(fromByteCount: bytes)
    }

    func modelMetaLine(for preset: MLXModelOption) -> String {
        var parts = [preset.sizeLabel, preset.precisionLabel]
        if let language = preset.languageLabel {
            parts.append(language)
        }
        return parts.joined(separator: " • ")
    }
}

struct ModelConfiguration {
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
