import AizenCore
import Foundation

/// Ephemeral fan-out for Host runtime updates. It assigns ordering at the one runtime boundary
/// while Storage remains the canonical source after a client reconnects.
public actor RunEventPublisher {
    private var nextSequence: UInt64 = 1
    private var continuations: [UUID: AsyncStream<HostEvent>.Continuation] = [:]

    public init() {}

    public func events() -> AsyncStream<HostEvent> {
        let subscriberID = UUID()
        let stream = AsyncStream.makeStream(of: HostEvent.self, bufferingPolicy: .bufferingNewest(100))
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
        let event = HostEvent.run(RunEvent(
            sequence: nextSequence,
            spaceID: run.spaceID,
            sessionID: run.sessionID,
            runID: run.id,
            kind: kind
        ))
        nextSequence += 1
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    public func publishTerminalOutput(
        spaceID: SpaceID,
        terminalSessionID: SessionID,
        terminalSequence: UInt64,
        output: Data,
        truncated: Bool
    ) {
        guard !output.isEmpty, nextSequence < UInt64.max else {
            if nextSequence == UInt64.max { finishAll() }
            return
        }
        var offset = output.startIndex
        while offset < output.endIndex, nextSequence < UInt64.max {
            let end = output.index(offset, offsetBy: min(64 * 1_024, output.distance(from: offset, to: output.endIndex)))
            let event = HostEvent.terminalOutput(.init(
                sequence: nextSequence,
                spaceID: spaceID,
                terminalSessionID: terminalSessionID,
                terminalSequence: terminalSequence,
                output: Data(output[offset..<end]),
                truncated: truncated
            ))
            nextSequence += 1
            for continuation in continuations.values {
                continuation.yield(event)
            }
            offset = end
        }
        if nextSequence == UInt64.max { finishAll() }
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
