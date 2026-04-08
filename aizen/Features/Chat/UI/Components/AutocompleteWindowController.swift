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
    var isWindowAboveCursor = false
    weak var parentWindow: NSWindow?
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

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
