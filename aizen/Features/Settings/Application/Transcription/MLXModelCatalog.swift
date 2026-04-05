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
    static func option(for modelId: String, kind: MLXModelKind) -> MLXModelOption? {
        let normalized = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        return allOptions.first { $0.kind == kind && $0.id == normalized }
    }

    static var allOptions: [MLXModelOption] {
        whisperPresets + parakeetPresets
    }
}
