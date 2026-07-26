import SwiftUI
import VisionKit

struct PairingQRScanner: UIViewControllerRepresentable {
    let didScan: (String) -> Void
    let didFail: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(didScan: didScan, didFail: didFail) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true
        )
        scanner.delegate = context.coordinator
        do {
            try scanner.startScanning()
        } catch {
            context.coordinator.didFail(error.localizedDescription)
        }
        return scanner
    }

    func updateUIViewController(_: DataScannerViewController, context _: Context) {}

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator _: Coordinator) {
        scanner.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let didScan: (String) -> Void
        let didFail: (String) -> Void
        private var hasScanned = false

        init(didScan: @escaping (String) -> Void, didFail: @escaping (String) -> Void) {
            self.didScan = didScan
            self.didFail = didFail
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems _: [RecognizedItem]) {
            guard !hasScanned,
                  let value = addedItems.compactMap({ item -> String? in
                      guard case let .barcode(barcode) = item else { return nil }
                      return barcode.payloadStringValue
                  }).first else {
                return
            }
            hasScanned = true
            dataScanner.stopScanning()
            didScan(value)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            didFail(error.localizedDescription)
        }
    }
}
