//
//  ChatMessageList+Style.swift
//  aizen
//
//  Created by OpenAI Codex on 03.04.26.
//

import AppKit
import SwiftUI
import VVCode
import VVChatTimeline
import VVMarkdown
import VVMetalPrimitives

extension ChatMessageList {
    var timelineStyleSignature: Int {
        var hasher = Hasher()
        hasher.combine(colorScheme)
        hasher.combine(markdownFontSize)
        hasher.combine(markdownFontFamily)
        hasher.combine(markdownParagraphSpacing)
        hasher.combine(markdownHeadingSpacing)
        hasher.combine(markdownContentPadding)
        hasher.combine(effectiveTerminalThemeName)
        return hasher.finalize()
    }

    var timelineStyle: VVChatTimelineStyle {
        let horizontalInset: CGFloat = 10
        let basePointSize = CGFloat(markdownFontSize)
        let headerPointSize = max(basePointSize - 1.5, 11.5)
        let timestampPointSize = max(basePointSize - 0.25, 12.5)
        let theme = timelineMarkdownTheme
        let draftTheme = theme

        return VVChatTimelineStyle(
            theme: theme,
            draftTheme: draftTheme,
            baseFont: timelineFont(size: basePointSize),
            draftFont: timelineFont(size: basePointSize),
            headerFont: timelineFont(size: headerPointSize, weight: .regular),
            timestampFont: timelineFont(size: timestampPointSize, weight: .medium),
            headerTextColor: colorScheme == .dark ? .rgba(0.98, 0.98, 1.0, 1.0) : .rgba(0.14, 0.16, 0.20, 1.0),
            timestampTextColor: colorScheme == .dark ? .rgba(0.66, 0.69, 0.75, 1.0) : .rgba(0.45, 0.48, 0.54, 1.0),
            userBubbleColor: userBubbleFillColor,
            userBubbleBorderColor: userBubbleStrokeColor,
            userBubbleBorderWidth: 0.6,
            userBubbleCornerRadius: 16,
            userBubbleInsets: .init(top: 8, left: 14, bottom: 8, right: 14),
            userBubbleMaxWidth: 560,
            assistantBubbleEnabled: false,
            assistantBubbleMaxWidth: 700,
            assistantBubbleAlignment: .leading,
            systemBubbleEnabled: true,
            systemBubbleColor: .clear,
            systemBubbleBorderColor: .clear,
            systemBubbleBorderWidth: 0,
            systemBubbleInsets: .init(top: 0, left: 0, bottom: 0, right: 0),
            systemBubbleMaxWidth: 760,
            systemBubbleAlignment: .center,
            userHeaderEnabled: false,
            assistantHeaderEnabled: false,
            systemHeaderEnabled: false,
            assistantHeaderTitle: "",
            systemHeaderTitle: "",
            assistantHeaderIconURL: nil,
            headerIconSize: max(13, headerPointSize + 0.5),
            headerIconSpacing: 6,
            userTimestampEnabled: true,
            assistantTimestampEnabled: false,
            systemTimestampEnabled: false,
            userTimestampSuffix: "",
            bubbleMetadataMinWidth: 1,
            headerSpacing: 1,
            footerSpacing: 0,
            timelineInsets: .init(top: 10, left: horizontalInset, bottom: 10, right: horizontalInset + 4),
            messageSpacing: 6,
            userInsets: .init(top: 7, left: horizontalInset, bottom: 7, right: max(horizontalInset, 10)),
            assistantInsets: .init(top: 3, left: 0, bottom: 4, right: 10),
            systemInsets: .init(top: 15, left: 0, bottom: 15, right: 0),
            backgroundColor: .clear
        )
    }

    var agentLaneIconType: AgentIconType {
        AgentRegistry.shared.getMetadata(for: selectedAgent)?.iconType ?? .sfSymbol("brain.head.profile")
    }

    var agentLaneIconURL: String? {
        nil
    }

    var agentLaneIconSize: CGFloat {
        0
    }

    var agentLaneIconSpacing: CGFloat {
        0
    }

    var agentLaneWidth: CGFloat {
        0
    }

    var headerIconTintColor: NSColor {
        if colorScheme == .dark {
            return NSColor(calibratedWhite: 0.94, alpha: 1)
        }
        return NSColor(calibratedWhite: 0.18, alpha: 1)
    }

    var timelineBackingScale: CGFloat {
        NSScreen.main?.backingScaleFactor ?? NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
    }

    var effectiveTerminalThemeName: String {
        guard terminalUsePerAppearanceTheme else { return terminalThemeName }
        return AppearanceSettings.effectiveThemeName(colorScheme: colorScheme)
    }

    var activeTerminalVVTheme: VVTheme? {
        GhosttyThemeParser.loadVVTheme(named: effectiveTerminalThemeName)
    }

    var markdownInlineCodeColor: SIMD4<Float> {
        if let theme = activeTerminalVVTheme {
            return simdColor(from: theme.cursorColor)
        }
        return simdColor(from: NSColor.controlAccentColor)
    }

    var timelineMarkdownTheme: MarkdownTheme {
        _ = markdownParagraphSpacing
        _ = markdownHeadingSpacing
        _ = markdownContentPadding
        var theme = AppearanceSettings.resolvedMarkdownTheme(colorScheme: colorScheme)
        theme.codeColor = markdownInlineCodeColor
        return theme
    }

    var userBubbleFillColor: SIMD4<Float> {
        if let theme = activeTerminalVVTheme {
            return simdColor(from: theme.backgroundColor).withOpacity(colorScheme == .dark ? 0.78 : 0.92)
        }
        return colorScheme == .dark ? .rgba(0.20, 0.22, 0.25, 0.42) : .rgba(0.91, 0.93, 0.96, 0.62)
    }

    var userBubbleStrokeColor: SIMD4<Float> {
        let divider = GhosttyThemeParser.loadDividerColor(named: effectiveTerminalThemeName)
        return simdColor(from: divider).withOpacity(colorScheme == .dark ? 0.32 : 0.18)
    }

    func simdColor(from color: NSColor) -> SIMD4<Float> {
        let resolved = color.usingColorSpace(.sRGB) ?? color
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return .rgba(Float(r), Float(g), Float(b), 1)
    }

    func timelineFont(size: CGFloat, weight: NSFont.Weight = .regular) -> VVFont {
        if markdownFontFamily == AppearanceSettings.defaultMarkdownFontFamily || markdownFontFamily == AppearanceSettings.systemFontFamily {
            return .systemFont(ofSize: size, weight: weight)
        }
        guard let custom = NSFont(name: markdownFontFamily, size: size) else {
            return .systemFont(ofSize: size, weight: weight)
        }
        switch weight {
        case .bold, .heavy, .black, .semibold:
            return NSFontManager.shared.convert(custom, toHaveTrait: .boldFontMask)
        default:
            return custom
        }
    }
}
