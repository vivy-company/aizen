import AppKit
import SwiftUI

extension ChatTabView {
    func resolvedToolbarInset(from geometry: GeometryProxy) -> CGFloat {
        let safeInset = geometry.safeAreaInsets.top
        if safeInset > 0 {
            return safeInset
        }

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            let estimatedInset = max(window.frame.height - window.contentLayoutRect.height, 0)
            if estimatedInset > 0 {
                return estimatedInset
            }
        }

        return 0
    }

    var chatSessionsStack: some View {
        ZStack {
            ForEach(cachedSessions) { session in
                let isSelected = selectedSessionId == session.id
                ChatSessionView(
                    worktree: worktree,
                    session: session,
                    sessionManager: sessionManager,
                    viewModel: chatStoreProvider(session),
                    isSelected: isSelected,
                    isCompanionResizing: isResizingCompanion
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(isSelected ? 1 : 0)
                .allowsHitTesting(isSelected)
                .zIndex(isSelected ? 1 : 0)
            }
        }
    }

    var cachedSessions: [ChatSession] {
        if cachedSessionIds.isEmpty {
            let fallbackId = selectedSessionId ?? chatSessions.last?.id
            if let fallbackId,
               let fallback = chatSessions.first(where: { $0.id == fallbackId }) {
                return [fallback]
            }
            if let last = chatSessions.last {
                return [last]
            }
        }
        return cachedSessionIds.compactMap { id in
            chatSessions.first(where: { $0.id == id })
        }
    }

    func maxLeftWidth(containerWidth: CGFloat, rightWidth: CGFloat) -> CGFloat {
        let rightTotal = rightPanel == nil ? 0 : rightWidth + dividerWidth
        let available = containerWidth - minCenterWidth - rightTotal - dividerWidth
        let ratioMax = containerWidth * maxPanelWidthRatio
        return max(minPanelWidth, min(available, ratioMax))
    }

    func maxRightWidth(containerWidth: CGFloat, leftWidth: CGFloat) -> CGFloat {
        let leftTotal = leftPanel == nil ? 0 : leftWidth + dividerWidth
        let available = containerWidth - minCenterWidth - leftTotal - dividerWidth
        let ratioMax = containerWidth * maxPanelWidthRatio
        return max(minPanelWidth, min(available, ratioMax))
    }

    func clampPanelWidths(containerWidth: CGFloat) {
        guard containerWidth > 0 else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if leftPanel != nil {
                let maxWidth = maxLeftWidth(containerWidth: containerWidth, rightWidth: CGFloat(rightPanelWidth))
                let clamped = min(max(CGFloat(leftPanelWidth), minPanelWidth), maxWidth)
                if abs(clamped - CGFloat(leftPanelWidth)) > 0.5 {
                    leftPanelWidth = Double(clamped)
                }
            }
            if rightPanel != nil {
                let maxWidth = maxRightWidth(containerWidth: containerWidth, leftWidth: CGFloat(leftPanelWidth))
                let clamped = min(max(CGFloat(rightPanelWidth), minPanelWidth), maxWidth)
                if abs(clamped - CGFloat(rightPanelWidth)) > 0.5 {
                    rightPanelWidth = Double(clamped)
                }
            }
            if leftPanel != nil {
                let maxWidth = maxLeftWidth(containerWidth: containerWidth, rightWidth: CGFloat(rightPanelWidth))
                let clamped = min(max(CGFloat(leftPanelWidth), minPanelWidth), maxWidth)
                if abs(clamped - CGFloat(leftPanelWidth)) > 0.5 {
                    leftPanelWidth = Double(clamped)
                }
            }
        }
    }
}
