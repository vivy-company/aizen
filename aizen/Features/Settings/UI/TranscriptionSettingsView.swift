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

            modelSections

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

}
