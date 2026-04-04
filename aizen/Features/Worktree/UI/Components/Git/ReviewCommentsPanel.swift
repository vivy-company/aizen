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

    private var footerButtons: some View {
        VStack(spacing: Layout.footerButtonSpacing) {
            footerButton(
                title: "Copy All",
                systemImage: "doc.on.doc",
                iconSize: 12,
                prominent: false,
                action: onCopyAll
            )

            footerButton(
                title: "Send to Agent",
                systemImage: "paperplane.fill",
                iconSize: 11,
                prominent: true,
                action: onSendToAgent
            )
        }
        .padding(.horizontal, Layout.contentPadding)
        .padding(.top, Layout.footerTopPadding)
        .padding(.bottom, Layout.footerBottomPadding)
    }

    private func footerButton(
        title: String,
        systemImage: String,
        iconSize: CGFloat,
        prominent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: iconSize))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: Layout.footerButtonHeight)
            .background(
                RoundedRectangle(cornerRadius: Layout.footerButtonCornerRadius, style: .continuous)
                    .fill(prominent ? Color.accentColor : Color.white.opacity(0.08))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(prominent ? Color.white : Color.primary)
    }

}
