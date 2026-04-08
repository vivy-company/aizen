//
//  AutocompleteWindowController+Support.swift
//  aizen
//

import AppKit
import SwiftUI
import Combine

extension AutocompleteWindowController {
    static let defaultWidth: CGFloat = 360

    static func makeWindow() -> NSWindow {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: defaultWidth, height: 120),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isExcludedFromWindowsMenu = true
        panel.isReleasedWhenClosed = false
        panel.level = .popUpMenu
        panel.hasShadow = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.animationBehavior = .utilityWindow
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = false
        return panel
    }

    func updateWindowAppearance() {
        let appearanceMode = UserDefaults.standard.string(forKey: "appearanceMode") ?? "system"
        let appearance: NSAppearance?

        switch appearanceMode {
        case "dark":
            appearance = NSAppearance(named: .darkAqua)
        case "light":
            appearance = NSAppearance(named: .aqua)
        default:
            appearance = nil
        }

        window?.appearance = appearance
    }

    func updateWindowSize(itemCount: Int) {
        let headerHeight: CGFloat = 38
        let emptyStateHeight: CGFloat = 54
        let rowHeight: CGFloat = 44
        let maxVisibleItems = 5

        let contentHeight: CGFloat
        if itemCount == 0 {
            contentHeight = headerHeight + emptyStateHeight
        } else {
            let visibleItems = min(itemCount, maxVisibleItems)
            contentHeight = headerHeight + CGFloat(visibleItems) * rowHeight
        }

        let size = NSSize(width: Self.defaultWidth, height: contentHeight)
        window?.setContentSize(size)
    }

    func positionWindow(at cursorRect: NSRect) {
        guard let window = window else { return }

        var effectiveCursorRect = cursorRect
        if cursorRect == .zero, let parentFrame = parentWindow?.frame {
            effectiveCursorRect = NSRect(
                x: parentFrame.midX,
                y: parentFrame.minY + 100,
                width: 1,
                height: 20
            )
        }

        let screenFrame = NSScreen.screens.first(where: { $0.frame.contains(effectiveCursorRect.origin) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)

        let windowSize = window.frame.size

        var origin = NSPoint(x: effectiveCursorRect.minX, y: effectiveCursorRect.minY)

        origin.y = effectiveCursorRect.maxY + 4
        isWindowAboveCursor = true

        if origin.y + windowSize.height > screenFrame.maxY {
            origin.y = effectiveCursorRect.minY - windowSize.height - 4
            isWindowAboveCursor = false
        }

        origin.x = max(screenFrame.minX + 8, min(origin.x, screenFrame.maxX - windowSize.width - 8))

        window.setFrameOrigin(origin)
    }
}
