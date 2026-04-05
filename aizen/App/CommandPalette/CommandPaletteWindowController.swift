//
//  CommandPaletteWindowController.swift
//  aizen
//
//  Command palette for fast navigation between worktrees, tabs, and sessions.
//

import AppKit

class CommandPaletteWindowController: NSWindowController {
    private var appDeactivationObserver: NSObjectProtocol?
    private var windowResignKeyObserver: NSObjectProtocol?
    private var eventMonitor: Any?

    convenience init(
        managedObjectContext: NSManagedObjectContext,
        currentRepositoryId: String?,
        currentWorkspaceId: String?,
        onNavigate: @escaping (CommandPaletteNavigationAction) -> Void
    ) {
        let viewModel = WorktreeSearchViewModel(
            currentRepositoryId: currentRepositoryId,
            currentWorkspaceId: currentWorkspaceId
        )
        let panel = CommandPalettePanel(
            managedObjectContext: managedObjectContext,
            viewModel: viewModel,
            onNavigate: onNavigate
        )
        self.init(window: panel)
        panel.requestClose = { [weak self] in
            self?.closeWindow()
        }
        panel.requestScopeCycle = {
            viewModel.cycleScopeForward()
        }
        setupAppObservers()
    }

    deinit {
        cleanup()
    }

    private func setupAppObservers() {
        appDeactivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.closeWindow()
        }

        windowResignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.closeWindow()
        }
    }

    private func cleanup() {
        if let observer = appDeactivationObserver {
            NotificationCenter.default.removeObserver(observer)
            appDeactivationObserver = nil
        }
        if let observer = windowResignKeyObserver {
            NotificationCenter.default.removeObserver(observer)
            windowResignKeyObserver = nil
        }
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    override func showWindow(_ sender: Any?) {
        guard let panel = window as? CommandPalettePanel else { return }
        positionPanel(panel)
        panel.makeKeyAndOrderFront(nil)
        setupEventMonitor(for: panel)
        DispatchQueue.main.async {
            panel.makeKey()
        }
    }

    private func setupEventMonitor(for panel: CommandPalettePanel) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }

        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .mouseMoved, .keyDown]
        ) { [weak self, weak panel] event in
            guard let self, let panel else { return event }
            guard panel.isVisible else { return event }

            if event.type == .keyDown {
                if event.keyCode == 48 { // Tab
                    panel.requestScopeCycle?()
                    return nil
                }
                return event
            }

            if event.type == .mouseMoved {
                panel.interaction.didMoveMouse()
                return event
            }

            let mouseLocation = NSEvent.mouseLocation
            if !panel.frame.contains(mouseLocation) {
                self.closeWindow()
            }
            return event
        }
    }

    private func positionPanel(_ panel: CommandPalettePanel) {
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        } ?? NSScreen.main

        guard let screen = targetScreen else { return }

        let screenFrame = screen.visibleFrame
        let panelFrame = panel.frame

        let x = screenFrame.midX - panelFrame.width / 2
        let y = screenFrame.maxY - panelFrame.height - 100

        let adjustedX = max(screenFrame.minX, min(x, screenFrame.maxX - panelFrame.width))
        let adjustedY = max(screenFrame.minY, min(y, screenFrame.maxY - panelFrame.height))

        panel.setFrameOrigin(NSPoint(x: adjustedX, y: adjustedY))
    }

    func closeWindow() {
        cleanup()
        window?.close()
    }
}
