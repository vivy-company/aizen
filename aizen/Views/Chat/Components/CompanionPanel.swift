//
//  CompanionPanel.swift
//  aizen
//
//  Companion panel types for chat view
//

import SwiftUI

enum CompanionPanel: String, CaseIterable, Identifiable {
    case terminal
    case files
    case browser
    case gitDiff

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .terminal: return "terminal"
        case .files: return "folder"
        case .browser: return "globe"
        case .gitDiff: return "arrow.triangle.branch"
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .terminal: return "Terminal"
        case .files: return "Files"
        case .browser: return "Browser"
        case .gitDiff: return "Git Diff"
        }
    }
}
