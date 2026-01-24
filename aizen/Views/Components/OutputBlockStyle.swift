//
//  OutputBlockStyle.swift
//  aizen
//
//  Design system for rich agent output blocks
//

import SwiftUI

// MARK: - Block Type

enum OutputBlockType {
    case neutral
    case info
    case success
    case warning
    case error
    
    var accentColor: Color {
        switch self {
        case .neutral: return .secondary
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
    
    var iconName: String {
        switch self {
        case .neutral: return "circle"
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        }
    }
    
    var backgroundColor: Color {
        accentColor.opacity(0.08)
    }
    
    var borderColor: Color {
        accentColor.opacity(0.3)
    }
}

// MARK: - Tool Kind Styling

extension ToolKind {
    var accentColor: Color {
        switch self {
        case .read: return .cyan
        case .edit: return .green
        case .delete: return .red
        case .move: return .purple
        case .search: return .indigo
        case .execute: return .orange
        case .think: return .pink
        case .fetch: return .teal
        case .switchMode: return .mint
        case .plan: return .blue
        case .exitPlanMode: return .green
        case .other: return .secondary
        }
    }
    
    var displayName: String {
        switch self {
        case .read: return "Read"
        case .edit: return "Edit"
        case .delete: return "Delete"
        case .move: return "Move"
        case .search: return "Search"
        case .execute: return "Execute"
        case .think: return "Thinking"
        case .fetch: return "Fetch"
        case .switchMode: return "Mode"
        case .plan: return "Plan"
        case .exitPlanMode: return "Done"
        case .other: return "Tool"
        }
    }
}

// MARK: - Status Styling (Extended)

extension ToolStatus {
    var accentColor: Color {
        switch self {
        case .pending: return .yellow
        case .inProgress: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }
    
    var backgroundColor: Color {
        accentColor.opacity(0.15)
    }
    
    var iconName: String {
        switch self {
        case .pending: return "clock"
        case .inProgress: return "arrow.trianglehead.2.clockwise"
        case .completed: return "checkmark"
        case .failed: return "xmark"
        }
    }
    
    var displayLabel: String {
        switch self {
        case .pending: return "Pending"
        case .inProgress: return "Running"
        case .completed: return "Done"
        case .failed: return "Failed"
        }
    }
}

// MARK: - Design Tokens

enum OutputBlockTokens {
    static let cornerRadius: CGFloat = 8
    static let borderWidth: CGFloat = 1
    static let accentStripeWidth: CGFloat = 3
    
    static let headerPaddingH: CGFloat = 12
    static let headerPaddingV: CGFloat = 8
    static let contentPadding: CGFloat = 12
    
    static let iconSize: CGFloat = 14
    static let titleFontSize: CGFloat = 12
    static let subtitleFontSize: CGFloat = 10
    
    static let shadowRadius: CGFloat = 4
    static let shadowOpacity: Double = 0.1
    
    static func backgroundColor(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.12) : Color(white: 0.98)
    }
    
    static func headerBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.14) : Color(white: 0.95)
    }
    
    static func borderColor(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1)
    }
}

// MARK: - Block Configuration

struct OutputBlockConfiguration {
    let type: OutputBlockType
    let accentColor: Color?
    let icon: String?
    let showAccentStripe: Bool
    let isCollapsible: Bool
    
    init(
        type: OutputBlockType = .neutral,
        accentColor: Color? = nil,
        icon: String? = nil,
        showAccentStripe: Bool = true,
        isCollapsible: Bool = true
    ) {
        self.type = type
        self.accentColor = accentColor
        self.icon = icon
        self.showAccentStripe = showAccentStripe
        self.isCollapsible = isCollapsible
    }
    
    var effectiveAccentColor: Color {
        accentColor ?? type.accentColor
    }
    
    var effectiveIcon: String {
        icon ?? type.iconName
    }
    
    static func forToolKind(_ kind: ToolKind) -> OutputBlockConfiguration {
        OutputBlockConfiguration(
            type: .neutral,
            accentColor: kind.accentColor,
            icon: kind.symbolName,
            showAccentStripe: true,
            isCollapsible: true
        )
    }
    
    static func forStatus(_ status: ToolStatus) -> OutputBlockType {
        switch status {
        case .pending: return .neutral
        case .inProgress: return .info
        case .completed: return .success
        case .failed: return .error
        }
    }
}
