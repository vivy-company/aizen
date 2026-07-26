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
    @Published private(set) var isSynchronizing = false
    @Published private(set) var lastError: String?

    private let host: ReignitionHostComposition

    init(host: ReignitionHostComposition) {
        self.host = host
    }

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

    private func refreshTimeline(sessionID: SessionID) async {
        await perform {
            self.messages = try await self.host.conversationTimeline(sessionID: sessionID)
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
