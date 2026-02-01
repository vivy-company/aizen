//
//  HorizontalOnlyScrollView.swift
//  aizen
//
//  Horizontal-only scroll view that forwards vertical scroll to parent.
//

import AppKit
import SwiftUI

private final class HorizontalOnlyNSScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        let deltaX = abs(event.scrollingDeltaX)
        let deltaY = abs(event.scrollingDeltaY)
        // If mostly vertical scrolling, pass to next responder (parent scroll view)
        if deltaY > deltaX {
            nextResponder?.scrollWheel(with: event)
            return
        }
        super.scrollWheel(with: event)
    }

    override var intrinsicContentSize: NSSize {
        // Report the height of the document view (content) as our height
        // This allows the ScrollView to fit its content vertically
        guard let docView = documentView else { return super.intrinsicContentSize }
        let height = docView.fittingSize.height
        return NSSize(width: NSView.noIntrinsicMetric, height: height > 0 ? height : 20)
    }
}

struct HorizontalOnlyScrollView<Content: View>: NSViewRepresentable {
    let showsIndicators: Bool
    let content: Content

    init(showsIndicators: Bool = true, @ViewBuilder content: () -> Content) {
        self.showsIndicators = showsIndicators
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = HorizontalOnlyNSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = showsIndicators
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        
        let host = NSHostingView(rootView: content)
        host.translatesAutoresizingMaskIntoConstraints = false // We'll manage frame manually for documentView behavior
        
        scrollView.documentView = host
        context.coordinator.hostingView = host
        
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let host = context.coordinator.hostingView else { return }
        
        // Only update root view if content changed (SwiftUI handles this efficiently usually)
        host.rootView = content
        
        // Use intrinsicContentSize from host instead of forcing layout
        // NSHostingView calculates this automatically based on SwiftUI content
        let fittingSize = host.intrinsicContentSize
        
        // If intrinsic size is invalid (-1), try fittingSize
        let size = fittingSize.height >= 0 ? fittingSize : host.fittingSize
        
        let minWidth = scrollView.contentView.bounds.width
        let width = max(size.width, minWidth)
        let height = size.height
        
        // Add tolerance to avoid infinite layout loops due to floating point precision
        if abs(host.frame.size.width - width) > 0.5 || abs(host.frame.size.height - height) > 0.5 {
            host.frame = NSRect(x: 0, y: 0, width: width, height: height)
            scrollView.invalidateIntrinsicContentSize()
        }
    }

    final class Coordinator {
        var hostingView: NSHostingView<Content>?
    }
}
