//
//  AgentUsageStore.swift
//  aizen
//
//  Lightweight usage tracking for agent sessions
//

import ACP
import Foundation
import Combine

struct AgentUsageStats: Codable, Equatable {
    var sessionsStarted: Int
    var promptsSent: Int
    var agentMessages: Int
    var toolCalls: Int
    var attachmentsSent: Int
    var lastUsedAt: Date?
    var lastSessionStartedAt: Date?

    static let empty = AgentUsageStats(
        sessionsStarted: 0,
        promptsSent: 0,
        agentMessages: 0,
        toolCalls: 0,
        attachmentsSent: 0,
        lastUsedAt: nil,
        lastSessionStartedAt: nil
    )
}

@MainActor
final class AgentUsageStore: ObservableObject {
    static let shared = AgentUsageStore()

    @Published private(set) var statsByAgent: [String: AgentUsageStats] = [:]

    private let defaults: UserDefaults
    private let storeKey = "agentUsageStats"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var persistTask: Task<Void, Never>?
    private let persistDelay: TimeInterval = 0.5

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func stats(for agentId: String) -> AgentUsageStats {
        statsByAgent[agentId] ?? .empty
    }

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

    private func mutate(_ agentId: String, update: (inout AgentUsageStats) -> Void) {
        var stats = statsByAgent[agentId] ?? .empty
        update(&stats)
        statsByAgent[agentId] = stats
        schedulePersist()
    }

    private func load() {
        guard let data = defaults.data(forKey: storeKey) else { return }
        do {
            statsByAgent = try decoder.decode([String: AgentUsageStats].self, from: data)
        } catch {
            statsByAgent = [:]
        }
    }

    private func persist() {
        do {
            let data = try encoder.encode(statsByAgent)
            defaults.set(data, forKey: storeKey)
        } catch {
            // Best effort persistence; ignore write failures.
        }
    }

    private func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(persistDelay))
            persist()
        }
    }
}
