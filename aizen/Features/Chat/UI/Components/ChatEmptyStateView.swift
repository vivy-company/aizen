import ACP
import CoreData
import SwiftUI

struct ChatEmptyStateView: View {
    let enabledAgents: [AgentMetadata]
    let recentSessions: [ChatSession]
    let recentSessionsLimit: Int
    let onAgentSelect: (String) -> Void
    let onShowMore: () -> Void
    let onResumeRecentSession: (ChatSession) -> Void

    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func emptyStateItemBackground(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            shape
                .fill(.white.opacity(0.001))
                .glassEffect(.regular.interactive(), in: shape)
        } else {
            shape.fill(.thinMaterial)
        }
    }

    var emptyStateItemStrokeColor: Color {
        colorScheme == .dark ? .white.opacity(0.10) : .black.opacity(0.08)
    }

}
