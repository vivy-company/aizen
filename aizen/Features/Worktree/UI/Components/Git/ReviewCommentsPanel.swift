//
//  ReviewCommentsPanel.swift
//  aizen
//
//  Left sidebar panel showing all review comments
//

import SwiftUI

struct ReviewCommentsPanel: View {
    enum Layout {
        static let panelPadding: CGFloat = 8
        static let sectionSpacing: CGFloat = 8
        static let cardCornerRadius: CGFloat = 10
        static let footerButtonCornerRadius: CGFloat = 12
        static let contentPadding: CGFloat = 10
        static let rowSpacing: CGFloat = 6
        static let footerButtonHeight: CGFloat = 30
        static let footerButtonSpacing: CGFloat = 10
        static let footerTopPadding: CGFloat = 6
        static let footerBottomPadding: CGFloat = 12
    }

    @ObservedObject var reviewManager: ReviewSessionStore
    let onScrollToLine: ((String, Int) -> Void)?
    let onCopyAll: () -> Void
    let onSendToAgent: () -> Void

    var body: some View {
        VStack(spacing: Layout.sectionSpacing) {
            if reviewManager.comments.isEmpty {
                emptyState
            } else {
                commentsList
                footerButtons
            }
        }
        .padding(.horizontal, Layout.panelPadding)
        .padding(.vertical, Layout.panelPadding)
    }
}
