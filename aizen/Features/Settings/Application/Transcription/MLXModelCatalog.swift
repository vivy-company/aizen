import Foundation

struct MLXModelOption: Identifiable, Hashable {
    let id: String
    let title: String
    let summary: String
    let sizeLabel: String
    let precisionLabel: String
    let languageLabel: String?
    let isPrimary: Bool
    let kind: MLXModelKind
}

enum MLXModelCatalog {
    static let whisperPresets: [MLXModelOption] = [
        MLXModelOption(
            id: "mlx-community/whisper-tiny-mlx",
            title: "Tiny",
            summary: "Fastest, smallest",
            sizeLabel: "Tiny",
            precisionLabel: "Full precision",
            languageLabel: nil,
            isPrimary: true,
            kind: .whisper
        ),
        MLXModelOption(
            id: "mlx-community/whisper-tiny.en-mlx",
            title: "Tiny (EN)",
            summary: "English-only, smaller",
            sizeLabel: "Tiny",
            precisionLabel: "Full precision",
            languageLabel: "English-only",
            isPrimary: false,
            kind: .whisper
        ),
        MLXModelOption(
            id: "mlx-community/whisper-base-mlx",
            title: "Base",
            summary: "Balanced speed/quality",
            sizeLabel: "Base",
            precisionLabel: "Full precision",
            languageLabel: nil,
            isPrimary: true,
            kind: .whisper
        ),
        MLXModelOption(
            id: "mlx-community/whisper-base.en-mlx",
            title: "Base (EN)",
            summary: "English-only base",
            sizeLabel: "Base",
            precisionLabel: "Full precision",
            languageLabel: "English-only",
            isPrimary: false,
            kind: .whisper
        ),
        MLXModelOption(
            id: "mlx-community/whisper-small-mlx",
            title: "Small",
            summary: "Better accuracy",
            sizeLabel: "Small",
            precisionLabel: "Full precision",
            languageLabel: nil,
            isPrimary: true,
            kind: .whisper
        ),
        MLXModelOption(
            id: "mlx-community/whisper-small.en-mlx",
            title: "Small (EN)",
            summary: "English-only small",
            sizeLabel: "Small",
            precisionLabel: "Full precision",
            languageLabel: "English-only",
            isPrimary: false,
            kind: .whisper
        ),
        MLXModelOption(
            id: "mlx-community/whisper-medium-mlx",
            title: "Medium",
            summary: "Higher accuracy, heavier",
            sizeLabel: "Medium",
            precisionLabel: "Full precision",
            languageLabel: nil,
            isPrimary: true,
            kind: .whisper
        ),
        MLXModelOption(
            id: "mlx-community/whisper-medium.en-mlx",
            title: "Medium (EN)",
            summary: "English-only medium",
            sizeLabel: "Medium",
            precisionLabel: "Full precision",
            languageLabel: "English-only",
            isPrimary: false,
            kind: .whisper
        ),
        MLXModelOption(
            id: "mlx-community/whisper-large-mlx",
            title: "Large",
            summary: "High quality, heavier",
            sizeLabel: "Large",
            precisionLabel: "Full precision",
            languageLabel: nil,
            isPrimary: false,
            kind: .whisper
        ),
        MLXModelOption(
            id: "mlx-community/whisper-large-v2-mlx",
            title: "Large v2",
            summary: "Previous large release",
            sizeLabel: "Large",
            precisionLabel: "Full precision",
            languageLabel: nil,
            isPrimary: false,
            kind: .whisper
        ),
        MLXModelOption(
            id: "mlx-community/whisper-large-v3-mlx",
            title: "Large v3",
            summary: "Latest large model",
            sizeLabel: "Large",
            precisionLabel: "Full precision",
            languageLabel: nil,
            isPrimary: true,
            kind: .whisper
        ),
        MLXModelOption(
            id: "mlx-community/whisper-large-v3-turbo",
            title: "Large v3 Turbo",
            summary: "Faster large model",
            sizeLabel: "Large",
            precisionLabel: "Turbo",
            languageLabel: nil,
            isPrimary: false,
            kind: .whisper
        ),
        MLXModelOption(
            id: "mlx-community/whisper-large-v3-mlx-4bit",
            title: "Large v3 4-bit",
            summary: "Smaller download",
            sizeLabel: "Large",
            precisionLabel: "4-bit quantized",
            languageLabel: nil,
            isPrimary: true,
            kind: .whisper
        ),
        MLXModelOption(
            id: "mlx-community/whisper-tiny-mlx-q4",
            title: "Tiny 4-bit",
            summary: "Tiny, quantized",
            sizeLabel: "Tiny",
            precisionLabel: "4-bit quantized",
            languageLabel: nil,
            isPrimary: false,
            kind: .whisper
        ),
        MLXModelOption(
            id: "mlx-community/whisper-base-mlx-q4",
            title: "Base 4-bit",
            summary: "Base, quantized",
            sizeLabel: "Base",
            precisionLabel: "4-bit quantized",
            languageLabel: nil,
            isPrimary: false,
            kind: .whisper
        ),
        MLXModelOption(
            id: "mlx-community/whisper-small-mlx-q4",
            title: "Small 4-bit",
            summary: "Small, quantized",
            sizeLabel: "Small",
            precisionLabel: "4-bit quantized",
            languageLabel: nil,
            isPrimary: false,
            kind: .whisper
        ),
        MLXModelOption(
            id: "mlx-community/whisper-medium-mlx-q4",
            title: "Medium 4-bit",
            summary: "Medium, quantized",
            sizeLabel: "Medium",
            precisionLabel: "4-bit quantized",
            languageLabel: nil,
            isPrimary: false,
            kind: .whisper
        ),
        MLXModelOption(
            id: "mlx-community/whisper-medium-mlx-8bit",
            title: "Medium 8-bit",
            summary: "Medium, 8-bit",
            sizeLabel: "Medium",
            precisionLabel: "8-bit quantized",
            languageLabel: nil,
            isPrimary: false,
            kind: .whisper
        ),
        MLXModelOption(
            id: "mlx-community/whisper-base.en-mlx-8bit",
            title: "Base (EN) 8-bit",
            summary: "English-only, 8-bit",
            sizeLabel: "Base",
            precisionLabel: "8-bit quantized",
            languageLabel: "English-only",
            isPrimary: false,
            kind: .whisper
        ),
        MLXModelOption(
            id: "mlx-community/whisper-tiny.en-mlx-8bit",
            title: "Tiny (EN) 8-bit",
            summary: "English-only, 8-bit",
            sizeLabel: "Tiny",
            precisionLabel: "8-bit quantized",
            languageLabel: "English-only",
            isPrimary: false,
            kind: .whisper
        )
    ]

    static let parakeetPresets: [MLXModelOption] = [
        MLXModelOption(
            id: "mlx-community/parakeet-tdt-0.6b-v2",
            title: "Parakeet TDT 0.6B v2",
            summary: "Large, high-accuracy model",
            sizeLabel: "Large",
            precisionLabel: "Full precision",
            languageLabel: nil,
            isPrimary: true,
            kind: .parakeetTDT
        )
    ]

    static func option(for modelId: String, kind: MLXModelKind) -> MLXModelOption? {
        let normalized = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        return allOptions.first { $0.kind == kind && $0.id == normalized }
    }

    static var allOptions: [MLXModelOption] {
        whisperPresets + parakeetPresets
    }
}
