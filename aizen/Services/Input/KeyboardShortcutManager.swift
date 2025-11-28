//
//  KeyboardShortcutManager.swift
//  aizen
//
//  Manages global keyboard shortcuts and event monitoring
//

import AppKit
import Foundation

// MARK: - Key Codes

enum KeyCode {
    static let tab: UInt16 = 48
    static let escape: UInt16 = 53
    static let p: UInt16 = 35
    static let k: UInt16 = 40
}

// MARK: - Keyboard Shortcut Manager

@MainActor
class KeyboardShortcutManager {
    private var isChatViewActive = false
    private var observers: [NSObjectProtocol] = []
    private var eventMonitor: Any?

    init() {
        setupNotifications()
        setupEventMonitor()
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func setupNotifications() {
        let appearObserver = NotificationCenter.default.addObserver(
            forName: .chatViewDidAppear,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isChatViewActive = true
        }

        let disappearObserver = NotificationCenter.default.addObserver(
            forName: .chatViewDidDisappear,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isChatViewActive = false
        }

        observers.append(appearObserver)
        observers.append(disappearObserver)
    }

    private func setupEventMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else {
                return event
            }

            // Command+P: File search (global shortcut)
            if event.keyCode == KeyCode.p && event.modifierFlags.contains(.command) {
                NotificationCenter.default.post(name: .fileSearchShortcut, object: nil)
                return nil
            }

            // Command+K: Command palette (global shortcut)
            if event.keyCode == KeyCode.k && event.modifierFlags.contains(.command) {
                NotificationCenter.default.post(name: .commandPaletteShortcut, object: nil)
                return nil
            }

            // Chat view specific shortcuts
            guard self.isChatViewActive else {
                return event
            }

            if event.keyCode == KeyCode.tab && event.modifierFlags.contains(.shift) {
                // Shift+Tab: Cycle modes
                NotificationCenter.default.post(name: .cycleModeShortcut, object: nil)
                return nil
            }

            return event
        }
    }

    func cleanup() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()

        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
