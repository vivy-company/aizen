import AizenCore
import AizenStorage

/// Commits a user turn and its Run as one durable Host operation before touching the runtime.
public actor ConversationRunCoordinator {
    public enum Error: Swift.Error, Sendable, Equatable {
        case messageMustBeUserAuthored
        case mismatchedRun
        case duplicateMessage(ConversationMessageID)
        case duplicateRun(RunID)
        case unknownSession(SessionID)
    }

    private let storage: StorageRepository
    private let runtime: any PromptRunRuntime
    private let runs: RunCoordinator

    public init(storage: StorageRepository, runtime: any PromptRunRuntime) {
        self.storage = storage
        self.runtime = runtime
        runs = RunCoordinator(storage: storage, runtime: runtime)
    }

    public func submit(message: ConversationMessage, run: Run) async throws {
        guard message.role == .user else { throw Error.messageMustBeUserAuthored }
        guard message.spaceID == run.spaceID, message.sessionID == run.sessionID else { throw Error.mismatchedRun }
        _ = try await storage.transact { snapshot in
            guard snapshot.sessions.contains(where: { $0.id == message.sessionID && $0.spaceID == message.spaceID }) else {
                throw Error.unknownSession(message.sessionID)
            }
            guard !snapshot.conversationMessages.contains(where: { $0.id == message.id }) else { throw Error.duplicateMessage(message.id) }
            guard !snapshot.runs.contains(where: { $0.id == run.id }) else { throw Error.duplicateRun(run.id) }
            snapshot.conversationMessages.append(message)
            snapshot.runs.append(run)
        }
        do {
            try await runs.startPersisted(run)
            try await runtime.send(message: message.content, to: run.id)
            try await runs.complete(run.id)
        } catch {
            try? await runs.cancel(run.id)
            throw error
        }
    }
}
