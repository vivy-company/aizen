import AppKit
import Combine
import SwiftUI
import GhosttyKit

@MainActor
final class SearchState: ObservableObject {
    @Published var needle: String
    @Published var total: UInt?
    @Published var selected: UInt?

    init(needle: String = "", total: UInt? = nil, selected: UInt? = nil) {
        self.needle = needle
        self.total = total
        self.selected = selected
    }
}

extension Ghostty.SurfaceView {
    struct DerivedConfig {
        enum Scrollbar {
            case system
            case never
        }

        let backgroundColor: Color
        let backgroundOpacity: Double
        let macosWindowShadow: Bool
        let windowTitleFontFamily: String?
        let windowAppearance: NSAppearance?
        let scrollbar: Scrollbar

        init() {
            self.backgroundColor = Color(NSColor.windowBackgroundColor)
            self.backgroundOpacity = 1
            self.macosWindowShadow = true
            self.windowTitleFontFamily = nil
            self.windowAppearance = nil
            self.scrollbar = .system
        }
    }
}
