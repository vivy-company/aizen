import Foundation

extension AgentUsageStore {
    func recordSessionStart(agentId: String) {
        mutate(agentId) { stats in
            stats.sessionsStarted += 1
            let now = Date()
            stats.lastUsedAt = now
            stats.lastSessionStartedAt = now
        }
    }

    func recordPrompt(agentId: String, attachmentsCount: Int) {
        mutate(agentId) { stats in
            stats.promptsSent += 1
            if attachmentsCount > 0 {
                stats.attachmentsSent += attachmentsCount
            }
            stats.lastUsedAt = Date()
        }
    }

    func recordAgentMessage(agentId: String) {
        mutate(agentId) { stats in
            stats.agentMessages += 1
            stats.lastUsedAt = Date()
        }
    }

    func recordToolCall(agentId: String) {
        mutate(agentId) { stats in
            stats.toolCalls += 1
            stats.lastUsedAt = Date()
        }
    }

    func mutate(_ agentId: String, update: (inout AgentUsageStats) -> Void) {
        var stats = statsByAgent[agentId] ?? .empty
        update(&stats)
        statsByAgent[agentId] = stats
        schedulePersist()
    }
}
