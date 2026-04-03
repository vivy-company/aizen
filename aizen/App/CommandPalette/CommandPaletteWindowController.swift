//
//  CommandPaletteWindowController.swift
//  aizen
//
//  Command palette for fast navigation between worktrees, tabs, and sessions.
//

import AppKit
import CoreData
import SwiftUI

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

class CommandPalettePanel: NSPanel {
    let interaction = PaletteInteractionState()
    var requestClose: (() -> Void)?
    var requestScopeCycle: (() -> Void)?

    init(
        managedObjectContext: NSManagedObjectContext,
        viewModel: WorktreeSearchViewModel,
        onNavigate: @escaping (CommandPaletteNavigationAction) -> Void
    ) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = NSColor.clear
        self.hasShadow = true
        self.level = .floating
        self.isMovableByWindowBackground = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.becomesKeyOnlyIfNeeded = true
        self.isFloatingPanel = true
        self.acceptsMouseMovedEvents = true

        let hostingView = NSHostingView(
            rootView: CommandPaletteContent(
                onNavigate: onNavigate,
                onClose: { [weak self] in
                    if let close = self?.requestClose {
                        close()
                    } else {
                        self?.close()
                    }
                },
                viewModel: viewModel
            )
            .environment(\.managedObjectContext, managedObjectContext)
            .environmentObject(interaction)
        )

        hostingView.wantsLayer = true
        hostingView.layer?.isOpaque = false
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        self.contentView = hostingView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC key
            requestClose?()
        } else if event.keyCode == 48 { // Tab
            requestScopeCycle?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        requestClose?()
    }
}

struct CommandPaletteContent: View {
    let onNavigate: (CommandPaletteNavigationAction) -> Void
    let onClose: () -> Void
    @ObservedObject var viewModel: WorktreeSearchViewModel

    @Environment(\.managedObjectContext) var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Worktree.lastAccessed, ascending: false)],
        animation: .default
    )
    var allWorktrees: FetchedResults<Worktree>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Workspace.order, ascending: true)],
        animation: .default
    )
    var allWorkspaces: FetchedResults<Workspace>

    @FocusState var isSearchFocused: Bool
    @EnvironmentObject var interaction: PaletteInteractionState
    @State var hoveredIndex: Int?
    @AppStorage("selectedWorktreeId") var currentWorktreeId: String?

    var body: some View {
        LiquidGlassCard(
            shadowOpacity: 0,
            sheenOpacity: 0.28,
            scrimOpacity: 0.14
        ) {
            VStack(spacing: 0) {
                SpotlightSearchField(
                    placeholder: placeholderText(for: viewModel.scope),
                    text: $viewModel.searchQuery,
                    isFocused: $isSearchFocused,
                    onSubmit: {
                        if let action = viewModel.selectedNavigationAction() {
                            handleSelection(action)
                        }
                    },
                    onEscape: onClose,
                    trailing: {
                        Button(action: onClose) {
                            KeyCap(text: "esc")
                        }
                        .buttonStyle(.plain)
                        .help("Close")
                    }
                )
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 10)

                scopeChips
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)

                Divider().opacity(0.25)

                if activeResultsEmpty {
                    emptyResultsView
                } else {
                    resultsList
                }

                footer
            }
        }
        .frame(width: 760, height: 520)
        .modifier(CommandPaletteLifecycleModifier(content: self))
        .modifier(CommandPaletteKeyboardShortcutModifier(content: self))
    }

}
