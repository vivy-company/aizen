import AppKit
import GhosttyKit
import SwiftUI

extension Ghostty.SurfaceView {
    func localEventHandler(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .keyUp:
            localEventKeyUp(event)
        case .leftMouseDown:
            localEventLeftMouseDown(event)
        default:
            event
        }
    }

    private func localEventLeftMouseDown(_ event: NSEvent) -> NSEvent? {
        guard let window,
              event.window != nil,
              window == event.window else { return event }

        guard isTopmostSurfaceHit(for: event) else { return event }

        suppressNextLeftMouseUp = false

        guard window.firstResponder !== self else {
            return event
        }

        if NSApp.isActive && window.isKeyWindow {
            window.makeFirstResponder(self)
            suppressNextLeftMouseUp = true
            return nil
        }

        window.makeFirstResponder(self)
        return event
    }

    private func isTopmostSurfaceHit(for event: NSEvent) -> Bool {
        guard let window else { return false }

        let localPoint = convert(event.locationInWindow, from: nil)
        guard bounds.contains(localPoint) else { return false }

        if let contentView = window.contentView,
           let hitView = contentView.hitTest(event.locationInWindow),
           hitView !== self,
           !hitView.isDescendant(of: self) {
            return false
        }

        return true
    }

    var isCurrentFirstResponder: Bool {
        window?.firstResponder === self
    }

    private func localEventKeyUp(_ event: NSEvent) -> NSEvent? {
        if !event.modifierFlags.contains(.command) { return event }
        guard isCurrentFirstResponder || focused else { return event }
        self.keyUp(with: event)
        return nil
    }

    @objc func onUpdateRendererHealth(notification: Foundation.Notification) {
        guard let healthAny = notification.userInfo?["health"] else { return }
        guard let health = healthAny as? ghostty_action_renderer_health_e else { return }
        DispatchQueue.main.async { [weak self] in
            self?.healthy = health == GHOSTTY_RENDERER_HEALTH_HEALTHY
        }
    }

    @objc func ghosttyDidContinueKeySequence(notification: Foundation.Notification) {
        guard let keyAny = notification.userInfo?[Ghostty.Notification.KeySequenceKey] else { return }
        guard let key = keyAny as? KeyboardShortcut else { return }
        DispatchQueue.main.async { [weak self] in
            self?.keySequence.append(key)
        }
    }

    @objc func ghosttyDidEndKeySequence(notification: Foundation.Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.keySequence = []
        }
    }

    @objc func ghosttyDidChangeKeyTable(notification: Foundation.Notification) {
        guard let action = notification.userInfo?[Ghostty.Notification.KeyTableKey] as? Ghostty.Action.KeyTable else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch action {
            case .activate(let name):
                self.keyTables.append(name)
            case .deactivate:
                _ = self.keyTables.popLast()
            case .deactivateAll:
                self.keyTables.removeAll()
            }
        }
    }

    @objc func ghosttyConfigDidChange(_ notification: Foundation.Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.derivedConfig = DerivedConfig()
        }
    }

    @objc func ghosttyColorDidChange(_ notification: Foundation.Notification) {
        guard let change = notification.userInfo?[
            Foundation.Notification.Name.GhosttyColorChangeKey
        ] as? Ghostty.Action.ColorChange else { return }

        switch change.kind {
        case .background:
            DispatchQueue.main.async { [weak self] in
                self?.backgroundColor = change.color
            }
        default:
            break
        }
    }

    @objc func ghosttyBellDidRing(_ notification: Foundation.Notification) {
        bell = true
    }

    @objc func ghosttyDidChangeReadonly(_ notification: Foundation.Notification) {
        guard let value = notification.userInfo?[Foundation.Notification.Name.ReadonlyKey] as? Bool else { return }
        readonly = value
    }

    @objc func windowDidChangeScreen(notification: Foundation.Notification) {
        guard let window = self.window else { return }
        guard let object = notification.object as? NSWindow, window == object else { return }
        guard let screen = window.screen else { return }
        guard let surface = self.surface else { return }

        ghostty_surface_set_display_id(surface, screen.displayID ?? 0)

        DispatchQueue.main.async { [weak self] in
            self?.viewDidChangeBackingProperties()
        }
    }
}
