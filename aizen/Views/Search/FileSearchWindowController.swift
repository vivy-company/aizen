//
//  FileSearchWindowController.swift
//  aizen
//
//  Created on 2025-11-19.
//

import AppKit
import SwiftUI

class FileSearchWindowController: NSWindowController {
    private var eventMonitor: Any?
    private var appDeactivationObserver: NSObjectProtocol?

    convenience init(worktreePath: String, onFileSelected: @escaping (String) -> Void) {
        let panel = FileSearchPanel(worktreePath: worktreePath, onFileSelected: onFileSelected)
        self.init(window: panel)
        panel.requestClose = { [weak self] in
            self?.closeWindow()
        }
        setupAppObservers()
    }

    deinit {
        cleanup()
    }

    private func setupAppObservers() {
        // Close window when app is deactivated
        appDeactivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
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
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    override func showWindow(_ sender: Any?) {
        guard let panel = window as? FileSearchPanel else { return }

        // Position on active screen
        positionPanel(panel)

        // Show panel and make it key to enable proper focus handling
        panel.makeKeyAndOrderFront(nil)
        setupEventMonitor(for: panel)

        // Ensure focus is possible by making panel the key window
        DispatchQueue.main.async {
            panel.makeKey()
        }
    }

    private func setupEventMonitor(for panel: FileSearchPanel) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }

        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .mouseMoved]
        ) { [weak self, weak panel] event in
            guard let self, let panel else { return event }
            guard panel.isVisible else { return event }

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

    private func positionPanel(_ panel: FileSearchPanel) {
        // Use screen with mouse cursor for better UX
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        } ?? NSScreen.main

        guard let screen = targetScreen else { return }

        let screenFrame = screen.visibleFrame
        let panelFrame = panel.frame

        // Center horizontally, position near top
        let x = screenFrame.midX - panelFrame.width / 2
        let y = screenFrame.maxY - panelFrame.height - 100

        // Ensure panel stays on screen
        let adjustedX = max(screenFrame.minX, min(x, screenFrame.maxX - panelFrame.width))
        let adjustedY = max(screenFrame.minY, min(y, screenFrame.maxY - panelFrame.height))

        panel.setFrameOrigin(NSPoint(x: adjustedX, y: adjustedY))
    }

    func closeWindow() {
        cleanup()
        window?.close()
    }
}

class FileSearchPanel: NSPanel {
    let interaction = PaletteInteractionState()
    var requestClose: (() -> Void)?

    init(worktreePath: String, onFileSelected: @escaping (String) -> Void) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Make panel fully transparent - no window background at all
        self.isOpaque = false
        self.backgroundColor = NSColor.clear
        self.hasShadow = false
        self.level = .floating
        self.isMovableByWindowBackground = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.acceptsMouseMovedEvents = true

        // Critical for NSPanel - proper keyboard focus handling
        self.becomesKeyOnlyIfNeeded = true
        self.isFloatingPanel = true

        let hostingView = NSHostingView(
            rootView: FileSearchWindowContent(
                worktreePath: worktreePath,
                onFileSelected: onFileSelected,
                onClose: { [weak self] in
                    if let close = self?.requestClose {
                        close()
                    } else {
                        self?.close()
                    }
                }
            )
            .environmentObject(interaction)
        )

        // Ensure hosting view doesn't add any background
        hostingView.wantsLayer = true
        hostingView.layer?.isOpaque = false
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        self.contentView = hostingView
    }

    override var canBecomeKey: Bool {
        return true
    }

    override var canBecomeMain: Bool {
        return false
    }
}

struct FileSearchWindowContent: View {
    let worktreePath: String
    let onFileSelected: (String) -> Void
    let onClose: () -> Void

    @StateObject private var viewModel: FileSearchViewModel
    @FocusState private var isSearchFocused: Bool
    @EnvironmentObject private var interaction: PaletteInteractionState

    init(worktreePath: String, onFileSelected: @escaping (String) -> Void, onClose: @escaping () -> Void) {
        self.worktreePath = worktreePath
        self.onFileSelected = onFileSelected
        self.onClose = onClose
        self._viewModel = StateObject(wrappedValue: FileSearchViewModel(worktreePath: worktreePath))
    }

    var body: some View {
        LiquidGlassCard(tint: .black.opacity(0.30), sheenOpacity: 0.28, scrimOpacity: 0.14) {
            VStack(spacing: 0) {
                SpotlightSearchField(
                    placeholder: "Search files…",
                    text: $viewModel.searchQuery,
                    isFocused: $isSearchFocused,
                    onSubmit: {
                        if let result = viewModel.getSelectedResult() {
                            selectFile(result)
                        }
                    },
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
                .padding(.bottom, 14)

                Divider().opacity(0.25)

                resultsCard

                footer
            }
        }
        .frame(width: 760, height: 520)
        .onAppear {
            viewModel.indexFiles()
            // Small delay to ensure view hierarchy and panel are fully ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFocused = true
            }
        }
        // Keyboard shortcuts for file search - use hidden buttons for compatibility
        .background {
            Group {
                Button("") {
                    interaction.didUseKeyboard()
                    viewModel.moveSelectionDown()
                }
                    .keyboardShortcut(.downArrow, modifiers: [])

                Button("") {
                    interaction.didUseKeyboard()
                    viewModel.moveSelectionUp()
                }
                    .keyboardShortcut(.upArrow, modifiers: [])

                Button("") {
                    interaction.didUseKeyboard()
                    if let result = viewModel.getSelectedResult() {
                        selectFile(result)
                    }
                }
                .keyboardShortcut(.return, modifiers: [])

                Button("") { onClose() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .hidden()
        }
    }

    private var resultsCard: some View {
        VStack(spacing: 0) {
            if viewModel.isIndexing {
                indexingView
            } else if viewModel.results.isEmpty {
                emptyResultsView
            } else {
                resultsListView
            }
        }
    }

    private var indexingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("Indexing...")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }

    private var emptyResultsView: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.4))
            Text("No files found")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }

    private var resultsListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.results.indices, id: \.self) { index in
                        let result = viewModel.results[index]
                        resultRow(result: result, index: index, isSelected: index == viewModel.selectedIndex)
                            .id(index)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 10)
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .scrollIndicators(.hidden)
            .frame(maxHeight: 380)
            .onChange(of: viewModel.selectedIndex) { newIndex in
                // No animation for smoother single-item navigation
                proxy.scrollTo(newIndex, anchor: .center)
            }
        }
    }

    private func resultRow(result: FileSearchResult, index: Int, isSelected: Bool) -> some View {
        HStack(spacing: 14) {
            FileIconView(path: result.path, size: 20)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(result.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(result.relativePath)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isSelected {
                HStack(spacing: 6) {
                    KeyCap(text: "↩")
                    Text("Open")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.12) : Color.clear)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    }
                }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectFile(result)
        }
        .onHover { hovering in
            if hovering {
                guard interaction.allowHoverSelection else { return }
                viewModel.selectedIndex = index
            }
        }
    }


    private func selectFile(_ result: FileSearchResult) {
        viewModel.trackFileOpen(result.path)
        onFileSelected(result.path)
        onClose()
    }

    private var footer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                KeyCap(text: "↑")
                KeyCap(text: "↓")
                Text("Navigate")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                KeyCap(text: "↩")
                Text("Open")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.clear)
    }
}
