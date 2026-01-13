//
//  AutocompleteWindowController.swift
//  aizen
//
//  NSWindowController for cursor-positioned autocomplete popup
//

import AppKit
import SwiftUI
import Combine

@MainActor
final class AutocompletePopupModel: ObservableObject {
    @Published var items: [AutocompleteItem] = []
    @Published var selectedIndex: Int = 0
    @Published var trigger: AutocompleteTrigger?
    @Published var itemsVersion: Int = 0  // Increments when items list changes for scroll reset

    var onTap: ((AutocompleteItem) -> Void)?
    var onSelect: (() -> Void)?
}

final class AutocompleteWindowController: NSWindowController {
    private var isWindowAboveCursor = false
    private weak var parentWindow: NSWindow?
    private let model = AutocompletePopupModel()
    private var lastItemCount: Int = -1
    private var lastItemIds: Set<String> = []
    private var appearanceObserver: NSObjectProtocol?

    override init(window: NSWindow?) {
        super.init(window: window ?? Self.makeWindow())
        if let window = self.window {
            // Apply initial appearance from app settings
            updateWindowAppearance()

            let hostingView = NSHostingView(rootView: InlineAutocompletePopupView(model: model))

            hostingView.wantsLayer = true
            hostingView.layer?.isOpaque = false
            hostingView.layer?.backgroundColor = NSColor.clear.cgColor

            window.contentView = hostingView
            currentHostingView = hostingView

            // Observe appearance mode changes
            appearanceObserver = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.updateWindowAppearance()
            }
        }
    }

    deinit {
        if let observer = appearanceObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func updateWindowAppearance() {
        let appearanceMode = UserDefaults.standard.string(forKey: "appearanceMode") ?? "system"
        let appearance: NSAppearance?

        switch appearanceMode {
        case "dark":
            appearance = NSAppearance(named: .darkAqua)
        case "light":
            appearance = NSAppearance(named: .aqua)
        default:
            appearance = nil  // System default
        }

        window?.appearance = appearance
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static let defaultWidth: CGFloat = 360

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

    private var currentHostingView: NSView?

    func configureActions(
        onTap: @escaping (AutocompleteItem) -> Void,
        onSelect: @escaping () -> Void
    ) {
        model.onTap = onTap
        model.onSelect = onSelect
    }

    func update(state: AutocompleteState) {
        model.trigger = state.trigger
        model.selectedIndex = state.selectedIndex

        // Check if items actually changed (not just count, but content)
        let newItemIds = Set(state.items.map { $0.id })
        if newItemIds != lastItemIds {
            lastItemIds = newItemIds
            model.items = state.items
            model.itemsVersion += 1  // Signal scroll reset
        }

        if state.items.count != lastItemCount {
            lastItemCount = state.items.count
            updateWindowSize(itemCount: state.items.count)
        }
    }

    func updateWindowSize(itemCount: Int) {
        // Calculate height based on content
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

    var hasContent: Bool {
        currentHostingView != nil
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
        model.items = []
        model.selectedIndex = 0
        model.trigger = nil
        lastItemCount = -1
        lastItemIds = []
    }

    var isVisible: Bool {
        window?.isVisible ?? false
    }
}
