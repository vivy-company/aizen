import AizenCore
import Foundation

/// Ephemeral fan-out for Host runtime updates. It assigns ordering at the one runtime boundary
/// while Storage remains the canonical source after a client reconnects.
public actor RunEventPublisher {
    private var nextSequence: UInt64 = 1
    private var continuations: [UUID: AsyncStream<RunEvent>.Continuation] = [:]

    public init() {}

    public func events() -> AsyncStream<RunEvent> {
        let subscriberID = UUID()
        let stream = AsyncStream.makeStream(of: RunEvent.self)
        continuations[subscriberID] = stream.continuation
        stream.continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(subscriberID) }
        }
        return stream.stream
    }

    public func publish(for run: Run, kind: RunEventKind) {
        guard nextSequence < UInt64.max else {
            finishAll()
            return
        }
        let event = RunEvent(
            sequence: nextSequence,
            spaceID: run.spaceID,
            sessionID: run.sessionID,
            runID: run.id,
            kind: kind
        )
        nextSequence += 1
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    private func removeSubscriber(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func finishAll() {
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }
}
