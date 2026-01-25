//
//  SemanticBlockView.swift
//  aizen
//
//  Semantic block views for structured agent output (info, warning, error, success, note)
//

import SwiftUI

// MARK: - Semantic Block Type

enum SemanticBlockType {
    case info
    case warning
    case error
    case success
    case note
    
    var icon: String {
        switch self {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .note: return "doc.text.fill"
        }
    }
    
    var title: String {
        switch self {
        case .info: return "Info"
        case .warning: return "Warning"
        case .error: return "Error"
        case .success: return "Success"
        case .note: return "Note"
        }
    }
    
    var accentColor: Color {
        switch self {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        case .success: return .green
        case .note: return .secondary
        }
    }
    
    func backgroundColor(for scheme: ColorScheme) -> Color {
        let opacity: Double = scheme == .dark ? 0.15 : 0.1
        return accentColor.opacity(opacity)
    }
    
    func borderColor(for scheme: ColorScheme) -> Color {
        let opacity: Double = scheme == .dark ? 0.4 : 0.3
        return accentColor.opacity(opacity)
    }
}

// MARK: - Semantic Block View

struct SemanticBlockView: View {
    let type: SemanticBlockType
    let content: String
    var title: String?
    var isCollapsible: Bool = false
    
    @State private var isExpanded = true
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            
            if isExpanded {
                contentView
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    .padding(.top, 4)
            }
        }
        .background(type.backgroundColor(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(type.borderColor(for: colorScheme), lineWidth: 1)
        )
    }
    
    private var headerView: some View {
        HStack(spacing: 8) {
            Image(systemName: type.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(type.accentColor)
            
            Text(title ?? type.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(type.accentColor)
            
            Spacer()
            
            if isCollapsible {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(type.accentColor.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    private var contentView: some View {
        Text(content)
            .font(.system(size: 12))
            .foregroundStyle(.primary.opacity(0.9))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Convenience Initializers

extension SemanticBlockView {
    static func info(_ content: String, title: String? = nil) -> SemanticBlockView {
        SemanticBlockView(type: .info, content: content, title: title)
    }
    
    static func warning(_ content: String, title: String? = nil) -> SemanticBlockView {
        SemanticBlockView(type: .warning, content: content, title: title)
    }
    
    static func error(_ content: String, title: String? = nil) -> SemanticBlockView {
        SemanticBlockView(type: .error, content: content, title: title)
    }
    
    static func success(_ content: String, title: String? = nil) -> SemanticBlockView {
        SemanticBlockView(type: .success, content: content, title: title)
    }
    
    static func note(_ content: String, title: String? = nil) -> SemanticBlockView {
        SemanticBlockView(type: .note, content: content, title: title)
    }
}

// MARK: - Inline Semantic Badge

struct SemanticBadge: View {
    let type: SemanticBlockType
    var text: String?
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: type.icon)
                .font(.system(size: 10, weight: .semibold))
            
            if let text = text {
                Text(text)
                    .font(.system(size: 10, weight: .medium))
            }
        }
        .foregroundStyle(type.accentColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(type.accentColor.opacity(0.15))
        .clipShape(Capsule())
    }
}

// MARK: - Previews

#Preview("All Semantic Blocks") {
    ScrollView {
        VStack(spacing: 16) {
            SemanticBlockView.info(
                "This provides helpful context about the current operation. You can use this information to understand what's happening.",
                title: "Getting Started"
            )
            
            SemanticBlockView.warning(
                "This action will modify 15 files. Make sure you have committed your current changes before proceeding."
            )
            
            SemanticBlockView.error(
                "Failed to compile: unexpected token at line 42. Check the syntax and try again."
            )
            
            SemanticBlockView.success(
                "All 23 tests passed successfully. Build completed in 4.2 seconds."
            )
            
            SemanticBlockView.note(
                "This is a side note that provides additional context but isn't critical to the main flow."
            )
        }
        .padding()
    }
    .frame(width: 500, height: 600)
}

#Preview("Semantic Badges") {
    HStack(spacing: 12) {
        SemanticBadge(type: .info, text: "Info")
        SemanticBadge(type: .warning, text: "Warning")
        SemanticBadge(type: .error, text: "Failed")
        SemanticBadge(type: .success, text: "Passed")
        SemanticBadge(type: .note)
    }
    .padding()
}

#Preview("Collapsible Block") {
    VStack(spacing: 16) {
        SemanticBlockView(
            type: .info,
            content: "This is a collapsible block that can be expanded or collapsed by clicking the chevron.",
            title: "Collapsible Info",
            isCollapsible: true
        )
        
        SemanticBlockView(
            type: .warning,
            content: "Important warning that can be collapsed to save space.",
            isCollapsible: true
        )
    }
    .padding()
    .frame(width: 400)
}
