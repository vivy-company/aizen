import AppKit
import SwiftUI

extension DiffLineType {
    var markerColor: Color {
        switch self {
        case .added: return .green
        case .deleted: return .red
        case .context: return .clear
        case .header: return .secondary
        }
    }

    var backgroundColor: Color {
        switch self {
        case .added: return Color.green.opacity(0.2)
        case .deleted: return Color.red.opacity(0.2)
        case .context: return .clear
        case .header: return Color(NSColor.controlBackgroundColor).opacity(0.3)
        }
    }

    var nsMarkerColor: NSColor {
        switch self {
        case .added: return .systemGreen
        case .deleted: return .systemRed
        case .context: return .tertiaryLabelColor
        case .header: return .systemBlue
        }
    }

    var nsBackgroundColor: NSColor {
        switch self {
        case .added: return NSColor.systemGreen.withAlphaComponent(0.15)
        case .deleted: return NSColor.systemRed.withAlphaComponent(0.15)
        case .context: return .clear
        case .header: return NSColor.systemBlue.withAlphaComponent(0.1)
        }
    }
}
