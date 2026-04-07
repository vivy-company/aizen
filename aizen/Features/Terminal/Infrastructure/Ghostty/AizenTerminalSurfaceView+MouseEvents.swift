import AppKit
import GhosttyKit

extension Ghostty.SurfaceView {
    override func mouseDown(with event: NSEvent) {
        guard let surface = self.surface else { return }
        let mods = Ghostty.ghosttyMods(event.modifierFlags)
        ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, mods)
    }

    override func mouseUp(with event: NSEvent) {
        if suppressNextLeftMouseUp {
            suppressNextLeftMouseUp = false
            return
        }

        prevPressureStage = 0

        guard let surface = self.surface else { return }
        let mods = Ghostty.ghosttyMods(event.modifierFlags)
        ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, mods)
        ghostty_surface_mouse_pressure(surface, 0, 0)
    }

    override func otherMouseDown(with event: NSEvent) {
        guard let surface = self.surface else { return }
        let mods = Ghostty.ghosttyMods(event.modifierFlags)
        let button = Ghostty.Input.MouseButton(fromNSEventButtonNumber: event.buttonNumber)
        ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, button.cMouseButton, mods)
    }

    override func otherMouseUp(with event: NSEvent) {
        guard let surface = self.surface else { return }
        let mods = Ghostty.ghosttyMods(event.modifierFlags)
        let button = Ghostty.Input.MouseButton(fromNSEventButtonNumber: event.buttonNumber)
        ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, button.cMouseButton, mods)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let surface = self.surface else { return super.rightMouseDown(with: event) }

        let mods = Ghostty.ghosttyMods(event.modifierFlags)
        if ghostty_surface_mouse_button(
            surface,
            GHOSTTY_MOUSE_PRESS,
            GHOSTTY_MOUSE_RIGHT,
            mods
        ) {
            return
        }

        super.rightMouseDown(with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        guard let surface = self.surface else { return super.rightMouseUp(with: event) }

        let mods = Ghostty.ghosttyMods(event.modifierFlags)
        if ghostty_surface_mouse_button(
            surface,
            GHOSTTY_MOUSE_RELEASE,
            GHOSTTY_MOUSE_RIGHT,
            mods
        ) {
            return
        }

        super.rightMouseUp(with: event)
    }

    override func mouseEntered(with event: NSEvent) {
        mouseOverSurface = true
        super.mouseEntered(with: event)

        let pos = self.convert(event.locationInWindow, from: nil)
        mouseLocationInSurface = pos

        guard let surfaceModel else { return }
        let mouseEvent = Ghostty.Input.MousePosEvent(
            x: pos.x,
            y: frame.height - pos.y,
            mods: .init(nsFlags: event.modifierFlags)
        )
        surfaceModel.sendMousePos(mouseEvent)
    }

    override func mouseExited(with event: NSEvent) {
        mouseOverSurface = false
        mouseLocationInSurface = nil
        guard let surfaceModel else { return }

        if NSEvent.pressedMouseButtons != 0 {
            return
        }

        let mouseEvent = Ghostty.Input.MousePosEvent(
            x: -1,
            y: -1,
            mods: .init(nsFlags: event.modifierFlags)
        )
        surfaceModel.sendMousePos(mouseEvent)
    }

    override func mouseMoved(with event: NSEvent) {
        let pos = self.convert(event.locationInWindow, from: nil)
        mouseLocationInSurface = pos

        guard let surfaceModel else { return }
        let mouseEvent = Ghostty.Input.MousePosEvent(
            x: pos.x,
            y: frame.height - pos.y,
            mods: .init(nsFlags: event.modifierFlags)
        )
        surfaceModel.sendMousePos(mouseEvent)
    }

    override func mouseDragged(with event: NSEvent) {
        self.mouseMoved(with: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        self.mouseMoved(with: event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        self.mouseMoved(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surfaceModel else { return }

        var x = event.scrollingDeltaX
        var y = event.scrollingDeltaY
        let precision = event.hasPreciseScrollingDeltas

        if precision {
            x *= 2
            y *= 2
        }

        let scrollEvent = Ghostty.Input.MouseScrollEvent(
            x: x,
            y: y,
            mods: .init(precision: precision, momentum: .init(event.momentumPhase))
        )
        surfaceModel.sendMouseScroll(scrollEvent)
    }

    override func pressureChange(with event: NSEvent) {
        guard let surface = self.surface else { return }

        ghostty_surface_mouse_pressure(surface, UInt32(event.stage), Double(event.pressure))

        guard self.prevPressureStage < 2 else { return }
        prevPressureStage = event.stage
        guard event.stage == 2 else { return }

        guard UserDefaults.standard.bool(forKey: "com.apple.trackpad.forceClick") else { return }
        quickLook(with: event)
    }
}
