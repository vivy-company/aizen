//
//  GitPanelChrome.swift
//  aizen
//
//  Shared chrome primitives for the git panel window
//

import AppKit
import SwiftUI

enum GitPanelTheme {
    static func effectiveThemeName(
        colorScheme: ColorScheme? = nil,
        defaults: UserDefaults = .standard
    ) -> String {
        AppearanceSettings.effectiveThemeName(colorScheme: colorScheme, defaults: defaults)
    }

    static func backgroundColor(
        colorScheme: ColorScheme? = nil,
        defaults: UserDefaults = .standard
    ) -> NSColor {
        GhosttyThemeParser.loadBackgroundColor(named: effectiveThemeName(colorScheme: colorScheme, defaults: defaults))
    }
}

enum GitWindowDividerStyle {
    static func color(opacity: CGFloat = 1.0) -> Color {
        let base = contrastedBackgroundColor(strength: 0.06)
        return Color(nsColor: base.withAlphaComponent(0.5 * opacity))
    }

    static func splitterColor(opacity: CGFloat = 1.0) -> Color {
        Color(nsColor: .separatorColor).opacity(0.85 * opacity)
    }

    private static func contrastedBackgroundColor(strength: CGFloat) -> NSColor {
        let themeBackground = GitPanelTheme.backgroundColor()
        let background = themeBackground.usingColorSpace(.extendedSRGB) ?? themeBackground

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        background.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        let luminance = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
        let delta = luminance < 0.5 ? strength : -strength

        let adjustedRed = min(max(red + delta, 0), 1)
        let adjustedGreen = min(max(green + delta, 0), 1)
        let adjustedBlue = min(max(blue + delta, 0), 1)

        return NSColor(
            red: adjustedRed,
            green: adjustedGreen,
            blue: adjustedBlue,
            alpha: 1
        )
    }
}

struct GitWindowDivider: View {
    var opacity: CGFloat = 1.0

    var body: some View {
        Rectangle()
            .fill(GitWindowDividerStyle.color(opacity: opacity))
            .frame(height: 0.5)
            .accessibilityHidden(true)
    }
}

struct GitResizableDivider: View {
    let onDragChanged: (DragGesture.Value) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppearanceSettings.themeNameKey) private var terminalThemeName = AppearanceSettings.defaultDarkTheme
    @AppStorage(AppearanceSettings.lightThemeNameKey) private var terminalThemeNameLight = AppearanceSettings.defaultLightTheme
    @AppStorage(AppearanceSettings.usePerAppearanceThemeKey) private var usePerAppearanceTheme = false

    @State private var didPushCursor = false
    private let lineWidth: CGFloat = 1
    private let hitWidth: CGFloat = 14

    private var effectiveThemeName: String {
        guard usePerAppearanceTheme else { return terminalThemeName }
        return AppearanceSettings.effectiveThemeName(colorScheme: colorScheme)
    }

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: GhosttyThemeParser.loadDividerColor(named: effectiveThemeName)))
            .frame(width: lineWidth)
            .frame(width: hitWidth)
            .contentShape(Rectangle())
            .padding(.horizontal, -(hitWidth - lineWidth) / 2)
            .gesture(
                DragGesture()
                    .onChanged(onDragChanged)
            )
            .onHover { hovering in
                if hovering && !didPushCursor {
                    NSCursor.resizeLeftRight.push()
                    didPushCursor = true
                } else if !hovering && didPushCursor {
                    NSCursor.pop()
                    didPushCursor = false
                }
            }
            .onDisappear {
                if didPushCursor {
                    NSCursor.pop()
                    didPushCursor = false
                }
            }
    }
}

enum GitPanelTab: String, CaseIterable {
    case git
    case history
    case comments
    case workflows
    case prs

    var displayName: String {
        switch self {
        case .git: return String(localized: "git.panel.git")
        case .history: return String(localized: "git.panel.history")
        case .comments: return String(localized: "git.panel.comments")
        case .workflows: return String(localized: "git.panel.workflows")
        case .prs: return String(localized: "git.panel.prs")
        }
    }

    var icon: String {
        switch self {
        case .git: return "tray.full"
        case .history: return "clock"
        case .comments: return "text.bubble"
        case .workflows: return "bolt.circle"
        case .prs: return "arrow.triangle.merge"
        }
    }
}
