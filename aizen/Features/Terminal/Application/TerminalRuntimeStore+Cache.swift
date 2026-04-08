import Foundation

extension TerminalRuntimeStore {
    func getTerminal(for sessionId: UUID, paneId: String) -> AizenTerminalSurfaceView? {
        let cacheKey = key(for: sessionId, paneId: paneId)
        if let terminal = terminals[cacheKey] {
            touch(cacheKey)
            return terminal
        }
        return nil
    }

    func setTerminal(_ terminal: AizenTerminalSurfaceView, for sessionId: UUID, paneId: String) {
        let cacheKey = key(for: sessionId, paneId: paneId)
        terminals[cacheKey] = terminal
        touch(cacheKey)
        evictIfNeeded()
    }

    func removeTerminal(for sessionId: UUID, paneId: String) {
        let cacheKey = key(for: sessionId, paneId: paneId)
        if let terminal = terminals.removeValue(forKey: cacheKey) {
            cleanupTerminal(terminal)
        }
        accessOrder.removeAll { $0 == cacheKey }
    }

    func removeAllTerminals(for sessionId: UUID) {
        let prefix = keyPrefix(for: sessionId)
        for (cacheKey, terminal) in terminals where cacheKey.hasPrefix(prefix) {
            cleanupTerminal(terminal)
            terminals.removeValue(forKey: cacheKey)
        }
        accessOrder.removeAll { $0.hasPrefix(prefix) }
    }

    func getTerminalCount(for sessionId: UUID) -> Int {
        let prefix = keyPrefix(for: sessionId)
        return terminals.keys.filter { $0.hasPrefix(prefix) }.count
    }

    func key(for sessionId: UUID, paneId: String) -> String {
        "\(sessionId.uuidString)-\(paneId)"
    }

    func keyPrefix(for sessionId: UUID) -> String {
        "\(sessionId.uuidString)-"
    }

    func touch(_ key: String) {
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }

    func evictIfNeeded() {
        while terminals.count > maxTerminals, let oldest = accessOrder.first {
            accessOrder.removeFirst()
            if let terminal = terminals.removeValue(forKey: oldest) {
                cleanupTerminal(terminal)
            }
        }
    }

    func cleanupTerminal(_ terminal: AizenTerminalSurfaceView) {
        terminal.onProcessExit = nil
        terminal.onFocus = nil
        terminal.onTitleChange = nil
        terminal.onProgressReport = nil
        terminal.onReady = nil
    }
}
