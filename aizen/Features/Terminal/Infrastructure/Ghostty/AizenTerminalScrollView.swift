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
    private var observers: [NSObjectProtocol] = []
    private var cancellables: Set<AnyCancellable> = []
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

        // We listen for scroll events through bounds notifications on our NSClipView.
        // This is based on: https://christiantietze.de/posts/2018/07/synchronize-nsscrollview/
        scrollView.contentView.postsBoundsChangedNotifications = true
        observers.append(NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] notification in
            self?.handleScrollChange(notification)
        })

        // Listen for scrollbar updates from Ghostty
        observers.append(NotificationCenter.default.addObserver(
            forName: .ghosttyDidUpdateScrollbar,
            object: surfaceView,
            queue: .main
        ) { [weak self] notification in
            self?.handleScrollbarUpdate(notification)
        })

        // Listen for live scroll events
        observers.append(NotificationCenter.default.addObserver(
            forName: NSScrollView.willStartLiveScrollNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] _ in
            self?.isLiveScrolling = true
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: NSScrollView.didEndLiveScrollNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] _ in
            self?.isLiveScrolling = false
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: NSScrollView.didLiveScrollNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] _ in
            self?.handleLiveScroll()
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: NSScroller.preferredScrollerStyleDidChangeNotification,
            object: nil,
            // Since this observer is used to immediately override the event
            // that produced the notification, we let it run synchronously on
            // the posting thread.
            queue: nil
        ) { [weak self] _ in
            self?.handleScrollerStyleChange()
        })

        // Listen for frame change events on macOS 26.0. See the docstring for
        // handleFrameChangeForNSScrollPocket for why this is necessary.
        if #unavailable(macOS 26.1) { if #available(macOS 26.0, *) {
            observers.append(NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: nil,
                // Since this observer is used to immediately override the event
                // that produced the notification, we let it run synchronously on
                // the posting thread.
                queue: nil
            ) { [weak self] notification in
                self?.handleFrameChangeForNSScrollPocket(notification)
            })
        }}

        surfaceView.$derivedConfig
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    self?.handleConfigChange()
                }
            }
            .store(in: &cancellables)

        surfaceView.$pointerStyle
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newStyle in
                self?.scrollView.documentCursor = newStyle.cursor
            }
            .store(in: &cancellables)

    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // The entire bounds is a safe area, so we override any default
    // insets. This is necessary for the content view to match the
    // surface view if we have the "hidden" titlebar style.
    override var safeAreaInsets: NSEdgeInsets { return NSEdgeInsetsZero }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard window != nil else { return }

        // SwiftUI can attach us to the window before it has driven a stable layout pass.
        // Re-run layout on the next turn so the surface gets a real size/content-scale.
        DispatchQueue.main.async { [weak self] in
            self?.synchronizeForHostUpdate()
        }
    }

    override func layout() {
        super.layout()

        // Fill entire bounds with scroll view
        scrollView.frame = bounds
        surfaceView.frame.size = scrollView.bounds.size

        // We only set the width of the documentView here, as the height depends
        // on the scrollbar state and is updated in synchronizeScrollView
        documentView.frame.size.width = scrollView.bounds.width

        // When our scrollview changes make sure our scroller and surface views are synchronized
        synchronizeScrollView()
        synchronizeSurfaceView()
        synchronizeCoreSurface()
    }

    func updateContentSize(_ size: CGSize) {
        let currentSize = frame.size
        if abs(currentSize.width - size.width) > 0.5 || abs(currentSize.height - size.height) > 0.5 {
            var newFrame = frame
            newFrame.size = size
            frame = newFrame
        }

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

    private func synchronizeForHostUpdate() {
        needsLayout = true
        layoutSubtreeIfNeeded()

        guard bounds.width > 0, bounds.height > 0 else { return }
        surfaceView.needsDisplay = true
        surfaceView.layer?.setNeedsDisplay()
    }

    // MARK: Mouse events

    override func mouseMoved(with: NSEvent) {
        // When the OS preferred style is .legacy, the user should be able to
        // click and drag the scroller without using scroll wheels or gestures,
        // so we flash it when the mouse is moved over the scrollbar area.
        guard NSScroller.preferredScrollerStyle == .legacy else { return }
        scrollView.flashScrollers()
    }

    override func updateTrackingAreas() {
        // To update our tracking area we just recreate it all.
        trackingAreas.forEach { removeTrackingArea($0) }

        super.updateTrackingAreas()

        // Our tracking area is the scroller frame
        guard let scroller = scrollView.verticalScroller else { return }
        addTrackingArea(NSTrackingArea(
            rect: convert(scroller.bounds, from: scroller),
            options: [
                .mouseMoved,
                .activeInKeyWindow,
            ],
            owner: self,
            userInfo: nil))
    }
}
