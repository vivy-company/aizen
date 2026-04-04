//
//  FileSearchPanel.swift
//  aizen
//
//  Created by OpenAI Codex on 05.04.26.
//

import AppKit
import SwiftUI

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

        self.isOpaque = false
        self.backgroundColor = NSColor.clear
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

        hostingView.wantsLayer = true
        hostingView.layer?.isOpaque = false
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        self.contentView = hostingView
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
