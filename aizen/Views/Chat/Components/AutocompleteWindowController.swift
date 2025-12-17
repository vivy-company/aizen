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

    static func makeWindow() -> NSWindow {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 350, height: 280),
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

    func setContent<Content: View>(_ view: Content) {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = window?.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        window?.contentView = hostingView
    }

    func show(at cursorRect: NSRect, attachedTo parent: NSWindow) {
        guard let window = window else { return }

        parentWindow = parent

        // Add as child window if not already
        if window.parent != parent {
            parent.addChildWindow(window, ordered: .above)
        }

        positionWindow(at: cursorRect)
        window.orderFront(nil)
    }

    func updatePosition(at cursorRect: NSRect) {
        positionWindow(at: cursorRect)
    }

    private func positionWindow(at cursorRect: NSRect) {
        guard let window = window,
              let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else { return }

        // Size the window to fit content
        let contentSize = window.contentView?.fittingSize ?? NSSize(width: 350, height: 280)
        let windowSize = NSSize(
            width: max(350, min(contentSize.width, 500)),
            height: max(100, min(contentSize.height, 300))
        )

        var origin = NSPoint(x: cursorRect.minX, y: cursorRect.minY)

        // Position below cursor by default
        origin.y -= windowSize.height + 4

        // Check if goes below screen - flip to above
        if origin.y < screenFrame.minY {
            origin.y = cursorRect.maxY + 4
            isWindowAboveCursor = true
        } else {
            isWindowAboveCursor = false
        }

        // Horizontal bounds
        origin.x = max(screenFrame.minX + 8, min(origin.x, screenFrame.maxX - windowSize.width - 8))

        window.setFrame(NSRect(origin: origin, size: windowSize), display: true, animate: false)
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
