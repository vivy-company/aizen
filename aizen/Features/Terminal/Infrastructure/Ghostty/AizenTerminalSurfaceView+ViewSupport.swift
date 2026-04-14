import AppKit
import GhosttyKit

extension Ghostty.SurfaceView {
    func sizeDidChange(_ size: CGSize) {
        let scaledSize = self.convertToBacking(size)
        setSurfaceSize(width: UInt32(scaledSize.width), height: UInt32(scaledSize.height))
        contentSize = size
    }

    func setSurfaceSize(width: UInt32, height: UInt32) {
        guard let surface = self.surface else { return }

        ghostty_surface_set_size(surface, width, height)

        let size = ghostty_surface_size(surface)
        DispatchQueue.main.async {
            if let currentSize = self.surfaceSize,
               currentSize.columns == size.columns,
               currentSize.rows == size.rows,
               currentSize.width_px == size.width_px,
               currentSize.height_px == size.height_px,
               currentSize.cell_width_px == size.cell_width_px,
               currentSize.cell_height_px == size.cell_height_px {
                return
            }

            self.surfaceSize = size
        }
    }

    func setCursorShape(_ shape: ghostty_action_mouse_shape_e) {
        switch shape {
        case GHOSTTY_MOUSE_SHAPE_DEFAULT:
            pointerStyle = .default
        case GHOSTTY_MOUSE_SHAPE_TEXT:
            pointerStyle = .horizontalText
        case GHOSTTY_MOUSE_SHAPE_GRAB:
            pointerStyle = .grabIdle
        case GHOSTTY_MOUSE_SHAPE_GRABBING:
            pointerStyle = .grabActive
        case GHOSTTY_MOUSE_SHAPE_POINTER:
            pointerStyle = .link
        case GHOSTTY_MOUSE_SHAPE_W_RESIZE:
            pointerStyle = .resizeLeft
        case GHOSTTY_MOUSE_SHAPE_E_RESIZE:
            pointerStyle = .resizeRight
        case GHOSTTY_MOUSE_SHAPE_N_RESIZE:
            pointerStyle = .resizeUp
        case GHOSTTY_MOUSE_SHAPE_S_RESIZE:
            pointerStyle = .resizeDown
        case GHOSTTY_MOUSE_SHAPE_NS_RESIZE:
            pointerStyle = .resizeUpDown
        case GHOSTTY_MOUSE_SHAPE_EW_RESIZE:
            pointerStyle = .resizeLeftRight
        case GHOSTTY_MOUSE_SHAPE_VERTICAL_TEXT:
            pointerStyle = .verticalText
        case GHOSTTY_MOUSE_SHAPE_CONTEXT_MENU:
            pointerStyle = .contextMenu
        case GHOSTTY_MOUSE_SHAPE_CROSSHAIR:
            pointerStyle = .crosshair
        case GHOSTTY_MOUSE_SHAPE_NOT_ALLOWED:
            pointerStyle = .operationNotAllowed
        default:
            return
        }
    }

    func setCursorVisibility(_ visible: Bool) {
        cursorVisible = visible
        NSCursor.setHiddenUntilMouseMoves(!visible)
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            Self.focusChangeCounter &+= 1
            focusDidChange(true)
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { focusDidChange(false) }
        return result
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach { removeTrackingArea($0) }

        addTrackingArea(NSTrackingArea(
            rect: frame,
            options: [
                .mouseEnteredAndExited,
                .mouseMoved,
                .inVisibleRect,
                .activeAlways,
            ],
            owner: self,
            userInfo: nil))
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()

        if let window {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.contentsScale = window.backingScaleFactor
            CATransaction.commit()
        }

        guard let surface = self.surface else { return }

        let fbFrame = self.convertToBacking(self.frame)
        let xScale = fbFrame.size.width / self.frame.size.width
        let yScale = fbFrame.size.height / self.frame.size.height
        ghostty_surface_set_content_scale(surface, xScale, yScale)

        let scaledSize = self.convertToBacking(contentSize)
        setSurfaceSize(width: UInt32(scaledSize.width), height: UInt32(scaledSize.height))
    }
}
