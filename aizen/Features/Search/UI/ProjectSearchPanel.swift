import AppKit
import SwiftUI

final class ProjectSearchPanel: NSPanel {
    let interaction = PaletteInteractionState()
    var requestClose: (() -> Void)?

    init(
        store: ProjectSearchStore,
        onSelection: @escaping (SearchOpenRequest) -> Void
    ) {
        let initialSize = Self.panelSize(for: store.mode)
        super.init(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = NSColor.black.withAlphaComponent(0.001)
        self.hasShadow = true
        self.level = .floating
        self.isMovableByWindowBackground = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.acceptsMouseMovedEvents = true
        self.becomesKeyOnlyIfNeeded = true
        self.isFloatingPanel = true

        let hostingView = NSHostingView(
            rootView: ProjectSearchWindowContent(
                viewModel: store,
                onOpen: onSelection,
                onClose: { [weak self] in
                    if let close = self?.requestClose {
                        close()
                    } else {
                        self?.close()
                    }
                },
                onResizeRequest: { [weak self] mode in
                    self?.resizeForMode(mode)
                }
            )
            .environmentObject(interaction)
        )

        hostingView.wantsLayer = true
        hostingView.layer?.isOpaque = false
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        self.contentView = hostingView
    }

    static func panelSize(for mode: ProjectSearchMode) -> NSSize {
        switch mode {
        case .files:
            return NSSize(
                width: ProjectSearchWindowContent.filesWidth,
                height: ProjectSearchWindowContent.filesHeight
            )
        case .content:
            return NSSize(
                width: ProjectSearchWindowContent.contentWidth,
                height: ProjectSearchWindowContent.contentHeight
            )
        }
    }

    func resizeForMode(_ mode: ProjectSearchMode) {
        let newSize = Self.panelSize(for: mode)
        let currentFrame = frame

        // Keep top-center anchor
        let newX = currentFrame.midX - newSize.width / 2
        let newY = currentFrame.maxY - newSize.height

        let newFrame = NSRect(
            x: newX,
            y: newY,
            width: newSize.width,
            height: newSize.height
        )

        setFrame(newFrame, display: true, animate: true)
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            requestClose?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        requestClose?()
    }
}
