//
//  TerminalTitleRegistry.swift
//  aizen
//
//  Stores transient terminal titles in memory so animated shell/TUI titles do
//  not fan out through Core Data and broad SwiftUI invalidation.
//

import Combine
import CoreData
import Foundation

@MainActor
final class TerminalTitleRegistry: ObservableObject {
    static let shared = TerminalTitleRegistry()

    @Published private var liveTitles: [UUID: String] = [:]

    private init() {}

    func setLiveTitle(_ title: String, for sessionId: UUID) {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            clearLiveTitle(for: sessionId)
            return
        }

        if liveTitles[sessionId] != normalized {
            liveTitles[sessionId] = normalized
        }
    }

    func clearLiveTitle(for sessionId: UUID) {
        liveTitles.removeValue(forKey: sessionId)
    }

    func title(for session: TerminalSession) -> String? {
        if let sessionId = session.id,
           let liveTitle = liveTitles[sessionId],
           !liveTitle.isEmpty {
            return liveTitle
        }

        return session.title
    }
}
