//
//  DiffTypes.swift
//  aizen
//
//  Shared diff line types and models
//

import SwiftUI
import AppKit

// MARK: - Diff Line Type

nonisolated enum DiffLineType: String, Hashable, Codable, Sendable {
    case added
    case deleted
    case context
    case header

    var marker: String {
        switch self {
        case .added: return "+"
        case .deleted: return "-"
        case .context: return " "
        case .header: return ""
        }
    }

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

// MARK: - Diff Line

nonisolated struct DiffLine: Identifiable, Hashable, Sendable {
    let lineNumber: Int
    let oldLineNumber: String?
    let newLineNumber: String?
    let content: String
    let type: DiffLineType

    var id: Int { lineNumber }

    func hash(into hasher: inout Hasher) {
        hasher.combine(lineNumber)
        hasher.combine(content)
        hasher.combine(type)
    }

    static func == (lhs: DiffLine, rhs: DiffLine) -> Bool {
        lhs.lineNumber == rhs.lineNumber &&
        lhs.content == rhs.content &&
        lhs.type == rhs.type
    }
}
