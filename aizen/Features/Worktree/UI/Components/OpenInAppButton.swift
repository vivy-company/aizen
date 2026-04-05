import SwiftUI

struct OpenInAppButton: View {
    let lastOpenedApp: DetectedApp?
    @ObservedObject var appDetector: AppDetector
    let onOpenInLastApp: () -> Void
    let onOpenInDetectedApp: (DetectedApp) -> Void
}
