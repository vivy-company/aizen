//
//  ChatSessionView+LayoutSupport.swift
//  aizen
//
//  Layout-resize support for chat timeline and composer width.
//

import SwiftUI

extension ChatSessionView {
    func updateInputBarWidth(_ width: CGFloat) {
        let normalized = max((width * 2).rounded() / 2, 0)
        guard abs(normalized - inputBarWidth) > 0.5 else { return }

        // Geometry changes can arrive during layout; defer state mutation to next run loop.
        DispatchQueue.main.async {
            guard abs(normalized - inputBarWidth) > 0.5 else { return }
            inputBarWidth = normalized
        }
    }

    func handleLayoutResizingChange(_ resizing: Bool) {
        if resizing {
            wasNearBottomBeforeResize = viewModel.isNearBottom
            viewModel.cancelPendingAutoScroll()
            viewModel.suppressNextAutoScroll = true
            viewModel.scrollRequest = nil
            viewModel.isNearBottom = false
        } else {
            viewModel.isNearBottom = wasNearBottomBeforeResize
        }
    }
}
