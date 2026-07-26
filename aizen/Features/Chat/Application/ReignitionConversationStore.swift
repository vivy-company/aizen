import AizenCore
import Combine
import Foundation

/// Mac Client state for the Reignition conversation path. It owns projections only;
/// Host remains the sole owner of durable data and ACP runtime lifetime.
@MainActor
final class ReignitionConversationStore: ObservableObject {
    @Published private(set) var spaces: [Space] = []
    @Published private(set) var conversations: [Session] = []
    @Published private(set) var selectedConversationID: SessionID?
    @Published private(set) var messages: [ConversationMessage] = []
    @Published private(set) var activeRunLifecycles: [RunID: RunLifecycle] = [:]
    @Published private(set) var assistantTextByRun: [RunID: String] = [:]
    @Published private(set) var isSynchronizing = false
    @Published private(set) var lastError: String?

    private let host: ReignitionHostComposition
    private var sessionIDByRun: [RunID: SessionID] = [:]
    private var eventTask: Task<Void, Never>?

    init(host: ReignitionHostComposition) {
        self.host = host
        eventTask = Task { [weak self, host] in
            for await event in await host.events() {
                guard !Task.isCancelled else { return }
                await self?.consume(event)
            }
        }
    }

    deinit { eventTask?.cancel() }

    func refreshSpaces() async {
        await perform {
            self.spaces = try await self.host.spaces()
        }
    }

    func refresh(spaceID: SpaceID? = nil) async {
        await perform {
            let conversations = try await self.host.conversations(spaceID: spaceID)
            self.conversations = conversations
            if let selectedConversationID = self.selectedConversationID,
                !conversations.contains(where: { $0.id == selectedConversationID }) {
                self.selectedConversationID = nil
                self.messages = []
            }
        }
    }

    func select(_ sessionID: SessionID?) async {
        selectedConversationID = sessionID
        messages = []
        guard let sessionID else { return }
        await refreshTimeline(sessionID: sessionID)
    }

    func createConversation(spaceID: SpaceID, title: String) async {
        await perform {
            let sessionID = try await self.host.createConversation(spaceID: spaceID, title: title)
            self.conversations = try await self.host.conversations(spaceID: spaceID)
            await self.select(sessionID)
        }
    }

    func send(content: String) async {
        guard let sessionID = selectedConversationID,
            let session = conversations.first(where: { $0.id == sessionID }),
            !content.isEmpty else { return }
        await perform {
            _ = try await self.host.sendConversation(spaceID: session.spaceID, sessionID: sessionID, content: content)
            self.messages = try await self.host.conversationTimeline(sessionID: sessionID)
        }
    }

    func dismissError() {
        lastError = nil
    }

    var liveAssistantText: String? {
        guard let selectedConversationID else { return nil }
        let activeRunIDs = activeRunLifecycles.compactMap { runID, lifecycle in
            (lifecycle == .running || lifecycle == .waitingForPermission) && sessionIDByRun[runID] == selectedConversationID
                ? runID
                : nil
        }
        return activeRunIDs.compactMap { assistantTextByRun[$0] }.joined().nonEmpty
    }

    private func refreshTimeline(sessionID: SessionID) async {
        await perform {
            self.messages = try await self.host.conversationTimeline(sessionID: sessionID)
        }
    }

    private func consume(_ event: RunEvent) async {
        sessionIDByRun[event.runID] = event.sessionID
        switch event.kind {
        case .lifecycle(let lifecycle):
            activeRunLifecycles[event.runID] = lifecycle
            guard lifecycle == .succeeded || lifecycle == .failed || lifecycle == .cancelled else { return }
            assistantTextByRun.removeValue(forKey: event.runID)
            sessionIDByRun.removeValue(forKey: event.runID)
            if event.sessionID == selectedConversationID {
                await refreshTimeline(sessionID: event.sessionID)
            }
        case .assistantTextDelta(let text):
            assistantTextByRun[event.runID, default: ""] += text
        }
    }

    private func perform(_ operation: () async throws -> Void) async {
        isSynchronizing = true
        lastError = nil
        defer { isSynchronizing = false }
        do {
            try await operation()
        } catch {
            lastError = error.localizedDescription
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
