//
//  WorktreeListItemView+Summary.swift
//  aizen
//
//  Presentation helpers for worktree row summary content
//

import SwiftUI

extension WorktreeListItemView {
    var primaryTextColor: Color {
        isSelected ? selectedForegroundColor : .primary
    }

    var secondaryTextColor: Color {
        isSelected ? selectedForegroundColor.opacity(0.78) : .secondary
    }

    var selectedForegroundColor: Color {
        controlActiveState == .key ? .accentColor : .accentColor.opacity(0.78)
    }

    var selectionFillColor: Color {
        let base = NSColor.unemphasizedSelectedContentBackgroundColor
        let alpha: Double = controlActiveState == .key ? 0.26 : 0.18
        return Color(nsColor: base).opacity(alpha)
    }

    func sessionIconColor(for viewType: String) -> Color {
        let isActive = activeViewType == viewType
        if isSelected {
            return selectedForegroundColor.opacity(isActive ? 1.0 : 0.75)
        }
        return isActive ? .primary : .secondary
    }

    @ViewBuilder
    var sessionIcons: some View {
        HStack(spacing: 8) {
            if chatSessionCount > 0 {
                Image(systemName: "message")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(sessionIconColor(for: "chat"))
                    .help("Chat")
            }
            if terminalSessionCount > 0 {
                Image(systemName: "terminal")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(sessionIconColor(for: "terminal"))
                    .help("Terminal")
            }
            if browserSessionCount > 0 {
                Image(systemName: "globe")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(sessionIconColor(for: "browser"))
                    .help("Browser")
            }
            if fileSessionCount > 0 {
                Image(systemName: "folder")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(sessionIconColor(for: "files"))
                    .help("Files")
            }
        }
    }
}
