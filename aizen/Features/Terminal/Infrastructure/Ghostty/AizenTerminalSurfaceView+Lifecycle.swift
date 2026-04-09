import AppKit
import Foundation
import GhosttyKit

extension Ghostty.SurfaceView {
    // We need to support being a first responder so that we can get input events
    override var acceptsFirstResponder: Bool { true }

    init(_ app: ghostty_app_t, baseConfig: SurfaceConfiguration? = nil, uuid: UUID? = nil) {
        self.markedText = NSMutableAttributedString()
        self.id = uuid ?? .init()

        // Our initial config always is our application wide config.
        self.derivedConfig = DerivedConfig()

        // We need to initialize this so it does something but we want to set
        // it back up later so we can reference `self`. This is a hack we should
        // fix at some point.
        self.cachedScreenContents = .init(duration: .milliseconds(500)) { "" }
        self.cachedVisibleContents = self.cachedScreenContents

        // Initialize with some default frame size. The important thing is that this
        // is non-zero so that our layer bounds are non-zero so that our renderer
        // can do SOMETHING.
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

        configureCaches()
        scheduleFallbackTitle()
        installNotifications()
        installEventMonitor()

        // Setup our surface. This will also initialize all the terminal IO.
        let surface_cfg = baseConfig ?? SurfaceConfiguration()
        let surface = surface_cfg.withCValue(view: self) { surface_cfg_c in
            ghostty_surface_new(app, &surface_cfg_c)
        }
        guard let surface = surface else {
            self.error = NSError(domain: "Ghostty", code: 1)
            return
        }
        self.surfaceModel = Ghostty.Surface(cSurface: surface)

        // Setup our tracking area so we get mouse moved events
        updateTrackingAreas()

        // The UTTypes that can be dragged onto this view.
        registerForDraggedTypes(Array(Self.dropTypes))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported for this view")
    }

    deinit {
        // Remove all of our notificationcenter subscriptions
        let center = NotificationCenter.default
        center.removeObserver(self)

        // Remove our event monitor
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }

        trackingAreas.forEach { removeTrackingArea($0) }

        // Remove ourselves from secure input if we have to
        SecureInput.shared.removeScoped(ObjectIdentifier(self))

        // Cancel progress report timer
        progressReportTimer?.invalidate()
    }

    func focusDidChange(_ focused: Bool) {
        guard let surface = self.surface else { return }
        guard self.focused != focused else { return }
        self.focused = focused

        if !focused {
            suppressNextLeftMouseUp = false
        }

        ghostty_surface_set_focus(surface, focused)

        if passwordInput {
            SecureInput.shared.setScoped(ObjectIdentifier(self), focused: focused)
        }

        if focused {
            focusInstant = ContinuousClock.now
            bell = false
        }
    }
}
