import AppKit
import GhosttyKit

extension AizenTerminalScrollView {
    /// Positions the surface view to fill the currently visible rectangle.
    func synchronizeSurfaceView() {
        let visibleRect = scrollView.contentView.documentVisibleRect
        surfaceView.frame.origin = visibleRect.origin
    }

    /// Inform the actual pty of our size change.
    func synchronizeCoreSurface() {
        let width = scrollView.contentSize.width
        let height = surfaceView.frame.height
        if width > 0 && height > 0 {
            surfaceView.sizeDidChange(CGSize(width: width, height: height))
            if !surfaceView.didSignalReady {
                surfaceView.didSignalReady = true
                surfaceView.onReady?()
            }
        }
    }

    /// Sizes the document view and scrolls the content view according to the scrollbar state.
    func synchronizeScrollView() {
        documentView.frame.size.height = documentHeight()

        if !isLiveScrolling {
            let cellHeight = surfaceView.cellSize.height
            if cellHeight > 0, let scrollbar = surfaceView.scrollbar {
                let offsetY = CGFloat(scrollbar.total - scrollbar.offset - scrollbar.len) * cellHeight
                scrollView.contentView.scroll(to: CGPoint(x: 0, y: offsetY))
                lastSentRow = Int(scrollbar.offset)
            }
        }

        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func handleScrollChange(_ notification: Notification) {
        synchronizeSurfaceView()
    }

    func handleScrollerStyleChange() {
        scrollView.scrollerStyle = .overlay
        synchronizeCoreSurface()
    }

    func handleConfigChange() {
        synchronizeAppearance()
        synchronizeCoreSurface()
    }

    /// Converts the current scroll position to a row number and sends a `scroll_to_row` action.
    func handleLiveScroll() {
        let cellHeight = surfaceView.cellSize.height
        guard cellHeight > 0 else { return }

        let visibleRect = scrollView.contentView.documentVisibleRect
        let documentHeight = documentView.frame.height
        let scrollOffset = documentHeight - visibleRect.origin.y - visibleRect.height
        let row = Int(scrollOffset / cellHeight)

        guard row != lastSentRow else { return }
        lastSentRow = row

        _ = surfaceView.surfaceModel?.perform(action: "scroll_to_row:\(row)")
    }

    /// Updates the document view size to reflect total scrollback and adjusts scroll position.
    func handleScrollbarUpdate(_ notification: Notification) {
        guard let scrollbar = notification.userInfo?[Notification.Name.ScrollbarKey] as? Ghostty.Action.Scrollbar else {
            return
        }
        surfaceView.scrollbar = scrollbar
        synchronizeScrollView()
    }

    /// This bug is only present in macOS 26.0.
    @available(macOS, introduced: 26.0, obsoleted: 26.1)
    func handleFrameChangeForNSScrollPocket(_ notification: Notification) {
        guard let window else { return }
        guard !window.styleMask.contains(.fullScreen) else { return }
        guard let view = notification.object as? NSView else { return }
        guard view.className.contains("NSScrollPocket") else { return }
        guard scrollView.subviews.contains(view) else { return }
        view.postsFrameChangedNotifications = false
        view.frame = NSRect(x: 0, y: 0, width: 0, height: 0)
        view.postsFrameChangedNotifications = true
    }

    /// Calculate the appropriate document view height given a scrollbar state.
    func documentHeight() -> CGFloat {
        let contentHeight = scrollView.contentSize.height
        let cellHeight = surfaceView.cellSize.height
        if cellHeight > 0, let scrollbar = surfaceView.scrollbar {
            let documentGridHeight = CGFloat(scrollbar.total) * cellHeight
            let padding = contentHeight - (CGFloat(scrollbar.len) * cellHeight)
            return documentGridHeight + padding
        }
        return contentHeight
    }
}
