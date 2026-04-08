import CoreData
import Foundation

extension TerminalTabView {
    var sessions: [TerminalSession] {
        let sessions = (worktree.terminalSessions as? Set<TerminalSession>) ?? []
        return sessions
            .filter { !$0.isDeleted }
            .sorted { ($0.createdAt ?? Date()) < ($1.createdAt ?? Date()) }
    }

    var validatedSelectedSessionId: UUID? {
        if let currentId = selectedSessionId,
           sessions.contains(where: { $0.id == currentId }) {
            return currentId
        }

        return sessions.last?.id ?? sessions.first?.id
    }

    var selectedSessions: [TerminalSession] {
        guard let selectedId = validatedSelectedSessionId else { return [] }
        return sessions.filter { $0.id == selectedId }
    }
}
