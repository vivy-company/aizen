import SwiftUI
import AppKit

struct TranscriptionSettingsView: View {
    @AppStorage(TranscriptionSettingsKeys.provider) var providerRaw = TranscriptionSettingsDefaults.provider.rawValue
    @AppStorage(TranscriptionSettingsKeys.mlxWhisperModelId) var whisperModelId = TranscriptionSettingsDefaults.mlxWhisperModelId
    @AppStorage(TranscriptionSettingsKeys.mlxParakeetModelId) var parakeetModelId = TranscriptionSettingsDefaults.mlxParakeetModelId

    @StateObject var whisperManager: MLXModelStore
    @StateObject var parakeetManager: MLXModelStore

    init() {
        let whisperId = TranscriptionSettingsStore.currentWhisperModelId()
        let parakeetId = TranscriptionSettingsStore.currentParakeetModelId()
        _whisperManager = StateObject(wrappedValue: MLXModelStore(kind: .whisper, modelId: whisperId))
        _parakeetManager = StateObject(wrappedValue: MLXModelStore(kind: .parakeetTDT, modelId: parakeetId))
    }

    var provider: TranscriptionProvider {
        TranscriptionProvider(rawValue: providerRaw) ?? .system
    }

    var settingsSyncKey: String {
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

}
