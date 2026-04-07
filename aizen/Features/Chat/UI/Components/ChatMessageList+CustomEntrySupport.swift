import AppKit
import SwiftUI
import VVCode
import VVChatTimeline
import VVMetalPrimitives

extension ChatMessageList {
    func toolHeaderIconURL(for kindRawValue: String?) -> String? {
        symbolIconURL(
            toolHeaderSymbol(for: kindRawValue),
            fallbackID: "tool-\(kindRawValue ?? "unknown")",
            tintColor: headerIconTintColor
        )
    }

    func toolHeaderIconURL(for kindRawValue: String?, tintColor: NSColor) -> String? {
        let symbol = toolHeaderSymbol(for: kindRawValue)
        return symbolIconURL(
            symbol,
            fallbackID: "tool-\(kindRawValue ?? "unknown")-\(tintColor.hashValue)",
            tintColor: tintColor
        )
    }

    func symbolIconURL(
        _ symbolName: String,
        fallbackID: String? = nil,
        tintColor: NSColor? = nil,
        pointSize: CGFloat? = nil
    ) -> String? {
        let resolvedTintColor = tintColor ?? headerIconTintColor
        return ChatTimelineHeaderIconStore.urlString(
            for: .sfSymbol(symbolName),
            fallbackAgentId: fallbackID ?? "symbol-\(symbolName)",
            tintColor: resolvedTintColor,
            targetPointSize: pointSize ?? 14
        )
    }

    func toolHeaderSymbol(for kindRawValue: String?) -> String {
        switch kindRawValue {
        case "read":
            return "doc.text.magnifyingglass"
        case "edit":
            return "pencil"
        case "delete":
            return "trash"
        case "move":
            return "arrow.left.and.right.square"
        case "task":
            return "checklist"
        case "execute":
            return "terminal"
        case "search":
            return "magnifyingglass"
        case "think":
            return "brain.head.profile"
        case "fetch":
            return "globe"
        case "plan":
            return "list.bullet.clipboard"
        case "switchMode":
            return "arrow.triangle.swap"
        default:
            return "wrench.and.screwdriver"
        }
    }

    var turnSummaryBubbleStyle: VVChatBubbleStyle {
        let theme = activeTerminalVVTheme
        let background = theme?.backgroundColor ?? GhosttyThemeParser.loadBackgroundColor(named: effectiveTerminalThemeName)
        let divider = GhosttyThemeParser.loadDividerColor(named: effectiveTerminalThemeName)
        return VVChatBubbleStyle(
            isEnabled: true,
            color: simdColor(from: background).withOpacity(colorScheme == .dark ? 0.92 : 0.98),
            borderColor: simdColor(from: divider).withOpacity(colorScheme == .dark ? 0.34 : 0.18),
            borderWidth: 0.8,
            cornerRadius: 14,
            insets: .init(top: 10, left: 14, bottom: 10, right: 14),
            maxWidth: 920,
            alignment: .leading
        )
    }

    var turnSummaryFileBubbleStyle: VVChatBubbleStyle {
        VVChatBubbleStyle(
            isEnabled: true,
            color: colorScheme == .dark ? .rgba(0.12, 0.14, 0.17, 0.52) : .rgba(0.98, 0.985, 0.992, 0.95),
            borderColor: colorScheme == .dark ? .rgba(0.52, 0.56, 0.62, 0.14) : .rgba(0.56, 0.60, 0.68, 0.12),
            borderWidth: 0.7,
            cornerRadius: 12,
            insets: .init(top: 8, left: 12, bottom: 8, right: 12),
            maxWidth: 740,
            alignment: .leading
        )
    }

    func encodeCustomPayload(_ payload: TimelineCustomPayload, fallback: String) -> Data {
        if let encoded = try? JSONEncoder().encode(payload) {
            return encoded
        }
        return Data(fallback.utf8)
    }
}
