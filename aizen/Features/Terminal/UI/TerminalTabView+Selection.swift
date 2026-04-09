import Foundation

extension TerminalTabView {
    var sessionIdentitySnapshot: [UUID] {
        sessions.compactMap(\.id)
    }

    var validatedSelectedSessionId: UUID? {
        if let currentId = selectedSessionId,
           sessions.contains(where: { $0.id == currentId }) {
            return currentId
        }

        return sessions.last?.id ?? sessions.first?.id
    }

    var cachedSessions: [TerminalSession] {
        let validIds = Set(sessions.compactMap(\.id))
        let effectiveCachedIds = cachedSessionIds.filter(validIds.contains)

        if effectiveCachedIds.isEmpty,
           let selectedId = validatedSelectedSessionId,
           let selectedSession = sessions.first(where: { $0.id == selectedId }) {
            return [selectedSession]
        }

        return effectiveCachedIds.compactMap { id in
            sessions.first(where: { $0.id == id })
        }
    }

    func syncSelectionAndCache() {
        if selectedSessionId != validatedSelectedSessionId {
            selectedSessionId = validatedSelectedSessionId
        }

        let validIds = Set(sessions.compactMap(\.id))
        cachedSessionIds.removeAll { !validIds.contains($0) }

        guard let selectedId = validatedSelectedSessionId else { return }
        cachedSessionIds.removeAll { $0 == selectedId }
        cachedSessionIds.append(selectedId)

        if cachedSessionIds.count > maxCachedSessions {
            cachedSessionIds.removeFirst(cachedSessionIds.count - maxCachedSessions)
        }
    }
}
