import AppKit
import Foundation
import GhosttyKit

extension Ghostty.SurfaceView {
    func configureCaches() {
        cachedScreenContents = .init(duration: .milliseconds(500)) { [weak self] in
            guard let self else { return "" }
            guard let surface = self.surface else { return "" }
            var text = ghostty_text_s()
            let sel = ghostty_selection_s(
                top_left: ghostty_point_s(
                    tag: GHOSTTY_POINT_SCREEN,
                    coord: GHOSTTY_POINT_COORD_TOP_LEFT,
                    x: 0,
                    y: 0),
                bottom_right: ghostty_point_s(
                    tag: GHOSTTY_POINT_SCREEN,
                    coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT,
                    x: 0,
                    y: 0),
                rectangle: false)
            guard ghostty_surface_read_text(surface, sel, &text) else { return "" }
            defer { ghostty_surface_free_text(surface, &text) }
            return String(cString: text.text)
        }

        cachedVisibleContents = .init(duration: .milliseconds(500)) { [weak self] in
            guard let self else { return "" }
            guard let surface = self.surface else { return "" }
            var text = ghostty_text_s()
            let sel = ghostty_selection_s(
                top_left: ghostty_point_s(
                    tag: GHOSTTY_POINT_VIEWPORT,
                    coord: GHOSTTY_POINT_COORD_TOP_LEFT,
                    x: 0,
                    y: 0),
                bottom_right: ghostty_point_s(
                    tag: GHOSTTY_POINT_VIEWPORT,
                    coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT,
                    x: 0,
                    y: 0),
                rectangle: false)
            guard ghostty_surface_read_text(surface, sel, &text) else { return "" }
            defer { ghostty_surface_free_text(surface, &text) }
            return String(cString: text.text)
        }
    }

    func scheduleFallbackTitle() {
        titleFallbackTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            if let self = self, self.title.isEmpty {
                self.title = "👻"
            }
        }
    }

    func installNotifications() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(onUpdateRendererHealth),
            name: Ghostty.Notification.didUpdateRendererHealth,
            object: self)
        center.addObserver(
            self,
            selector: #selector(ghosttyDidContinueKeySequence),
            name: Ghostty.Notification.didContinueKeySequence,
            object: self)
        center.addObserver(
            self,
            selector: #selector(ghosttyDidEndKeySequence),
            name: Ghostty.Notification.didEndKeySequence,
            object: self)
        center.addObserver(
            self,
            selector: #selector(ghosttyDidChangeKeyTable),
            name: Ghostty.Notification.didChangeKeyTable,
            object: self)
        center.addObserver(
            self,
            selector: #selector(ghosttyConfigDidChange(_:)),
            name: .ghosttyConfigDidChange,
            object: self)
        center.addObserver(
            self,
            selector: #selector(ghosttyColorDidChange(_:)),
            name: .ghosttyColorDidChange,
            object: self)
        center.addObserver(
            self,
            selector: #selector(ghosttyBellDidRing(_:)),
            name: .ghosttyBellDidRing,
            object: self)
        center.addObserver(
            self,
            selector: #selector(ghosttyDidChangeReadonly(_:)),
            name: .ghosttyDidChangeReadonly,
            object: self)
        center.addObserver(
            self,
            selector: #selector(windowDidChangeScreen),
            name: NSWindow.didChangeScreenNotification,
            object: nil)
    }

    func installEventMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [
                .keyUp,
                .leftMouseDown,
            ]
        ) { [weak self] event in
            self?.localEventHandler(event)
        }
    }
}
