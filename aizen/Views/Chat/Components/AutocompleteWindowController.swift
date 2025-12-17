//
//  AutocompleteWindowController.swift
//  aizen
//
//  NSWindowController for cursor-positioned autocomplete popup
//

import AppKit
import SwiftUI

final class AutocompleteWindowController: NSWindowController {
    private var isWindowAboveCursor = false
    private weak var parentWindow: NSWindow?

    override init(window: NSWindow?) {
        super.init(window: window ?? Self.makeWindow())
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static let defaultWidth: CGFloat = 350

    static func makeWindow() -> NSWindow {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: defaultWidth, height: 100),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isExcludedFromWindowsMenu = true
        panel.isReleasedWhenClosed = false
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.animationBehavior = .utilityWindow
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        return panel
    }

    func setContent<Content: View>(_ view: Content, itemCount: Int) {
        let hostingView = NSHostingView(rootView: view)

        // Calculate height based on content
        let headerHeight: CGFloat = 35
        let emptyStateHeight: CGFloat = 50
        let rowHeight: CGFloat = 52
        let maxVisibleItems = 5

        let contentHeight: CGFloat
        if itemCount == 0 {
            contentHeight = headerHeight + emptyStateHeight
        } else {
            let visibleItems = min(itemCount, maxVisibleItems)
            contentHeight = headerHeight + CGFloat(visibleItems) * rowHeight
        }

        let size = NSSize(width: Self.defaultWidth, height: contentHeight)
        hostingView.frame = NSRect(origin: .zero, size: size)
        window?.setContentSize(size)
        window?.contentView = hostingView
    }

    func show(at cursorRect: NSRect, attachedTo parent: NSWindow) {
        guard let window = window else { return }

        parentWindow = parent

        // Add as child window if not already
        if window.parent != parent {
            parent.addChildWindow(window, ordered: .above)
        }

        // Position and show
        positionWindow(at: cursorRect)
        window.orderFront(nil)
    }

    func updatePosition(at cursorRect: NSRect) {
        positionWindow(at: cursorRect)
    }

    private func positionWindow(at cursorRect: NSRect) {
        guard let window = window else { return }

        // Get effective cursor rect - use parent window bottom-center if cursor rect is zero
        var effectiveCursorRect = cursorRect
        if cursorRect == .zero, let parentFrame = parentWindow?.frame {
            // Position above parent window's bottom center
            effectiveCursorRect = NSRect(
                x: parentFrame.midX,
                y: parentFrame.minY + 100,
                width: 1,
                height: 20
            )
        }

        // Use screen containing cursor, or main screen as fallback
        let screenFrame = NSScreen.screens.first(where: { $0.frame.contains(effectiveCursorRect.origin) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)

        // Use actual window size (set by setContent)
        let windowSize = window.frame.size

        var origin = NSPoint(x: effectiveCursorRect.minX, y: effectiveCursorRect.minY)

        // Always position above cursor
        origin.y = effectiveCursorRect.maxY + 4
        isWindowAboveCursor = true

        // Check if goes above screen - flip to below only if necessary
        if origin.y + windowSize.height > screenFrame.maxY {
            origin.y = effectiveCursorRect.minY - windowSize.height - 4
            isWindowAboveCursor = false
        }

        // Horizontal bounds
        origin.x = max(screenFrame.minX + 8, min(origin.x, screenFrame.maxX - windowSize.width - 8))

        window.setFrameOrigin(origin)
    }

    func dismiss() {
        guard let window = window else { return }

        if let parent = parentWindow {
            parent.removeChildWindow(window)
        }
        window.orderOut(nil)
        parentWindow = nil
    }

    var isVisible: Bool {
        window?.isVisible ?? false
    }
}
