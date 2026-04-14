import AppKit
import Combine
import GhosttyKit
import SwiftUI

/// Wraps a Ghostty surface view in an NSScrollView to provide native macOS scrollbar support.
///
/// ## Coordinate System
/// AppKit uses a +Y-up coordinate system (origin at bottom-left), while terminals conceptually
/// use +Y-down (row 0 at top). This class handles the inversion when converting between row
/// offsets and pixel positions.
///
/// ## Architecture
/// - `scrollView`: The outermost NSScrollView that manages scrollbar rendering and behavior
/// - `documentView`: A blank NSView whose height represents total scrollback (in pixels)
/// - `surfaceView`: The actual Ghostty renderer, positioned to fill the visible rect
class AizenTerminalScrollView: NSView {
    let scrollView: NSScrollView
    let documentView: NSView
    let surfaceView: AizenTerminalSurfaceView
    var observers: [NSObjectProtocol] = []
    var cancellables: Set<AnyCancellable> = []
    var isLiveScrolling = false

    /// The last row position sent via scroll_to_row action. Used to avoid
    /// sending redundant actions when the user drags the scrollbar but stays
    /// on the same row.
    var lastSentRow: Int?

    init(contentSize: CGSize, surfaceView: AizenTerminalSurfaceView) {
        self.surfaceView = surfaceView
        // The scroll view is our outermost view that controls all our scrollbar
        // rendering and behavior.
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.usesPredominantAxisScrolling = true
        // Always use the overlay style. See mouseMoved for how we make
        // it usable without a scroll wheel or gestures.
        scrollView.scrollerStyle = .overlay
        // hide default background to show blur effect properly
        scrollView.drawsBackground = false
        // In Ghostty's whole-window setup this can be false to let the surface
        // draw behind scrollers. In Aizen's embedded split layout that lets the
        // AppKit surface steal mouse hits outside its pane, so keep it clipped.
        scrollView.contentView.clipsToBounds = true

        // The document view is what the scrollview is actually going
        // to be directly scrolling. We set it up to a "blank" NSView
        // with the desired content size.
        documentView = NSView(frame: NSRect(origin: .zero, size: contentSize))
        scrollView.documentView = documentView

        // The document view contains our actual surface as a child.
        // We synchronize the scrolling of the document with this surface
        // so that our primary Ghostty renderer only needs to render the viewport.
        documentView.addSubview(surfaceView)

        super.init(frame: .zero)

        // Our scroll view is our only view
        addSubview(scrollView)

        // Apply initial scrollbar settings
        synchronizeAppearance()
        installObservers()
        installSubscriptions()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func updateContentSize(_ size: CGSize) {
        let currentSize = frame.size
        let sizeChanged = abs(currentSize.width - size.width) > 0.5 || abs(currentSize.height - size.height) > 0.5
        guard sizeChanged else { return }

        var newFrame = frame
        newFrame.size = size
        frame = newFrame

        synchronizeForHostUpdate()
    }

    // MARK: Scrolling

    func synchronizeAppearance() {
        let scrollbarConfig = surfaceView.derivedConfig.scrollbar
        scrollView.hasVerticalScroller = scrollbarConfig != .never
        let background = NSColor(surfaceView.derivedConfig.backgroundColor)
        let hasLightBackground = background.luminance > 0.5
        scrollView.appearance = NSAppearance(named: hasLightBackground ? .aqua : .darkAqua)
        updateTrackingAreas()
    }

    func synchronizeForHostUpdate() {
        needsLayout = true
        layoutSubtreeIfNeeded()

        guard bounds.width > 0, bounds.height > 0 else { return }
        surfaceView.needsDisplay = true
        surfaceView.layer?.setNeedsDisplay()
    }

}
