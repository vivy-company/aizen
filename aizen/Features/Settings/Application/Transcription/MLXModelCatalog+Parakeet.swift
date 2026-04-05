import Foundation

extension MLXModelCatalog {
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
}
