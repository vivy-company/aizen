import Foundation

extension TerminalTabView {
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
