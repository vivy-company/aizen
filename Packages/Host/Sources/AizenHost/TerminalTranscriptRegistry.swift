import AizenCore
import Foundation

/// Host-owned, bounded terminal history derived from runtime snapshots. It never persists
/// terminal bytes and only advances a cursor when the observed terminal content changes.
public actor TerminalTranscriptRegistry {
    public struct Snapshot: Sendable, Equatable {
        public let sequence: UInt64
        public let bytes: Data
        public let truncated: Bool

        public init(sequence: UInt64, bytes: Data, truncated: Bool) {
            self.sequence = sequence
            self.bytes = bytes
            self.truncated = truncated
        }
    }

    private struct Transcript: Sendable {
        var sequence: UInt64 = 0
        var captured: Data = .init()
        var retained: Data = .init()
        var didTruncate = false
    }

    private let maximumBytes: Int
    private var transcripts: [SessionID: Transcript] = [:]

    public init(maximumBytes: Int = 1_000_000) {
        precondition(maximumBytes > 0, "Terminal transcript capacity must be positive")
        self.maximumBytes = maximumBytes
    }

    /// Records a complete runtime capture. Tmux normally grows a capture by suffix; a pane
    /// reset is represented as a new cursor rather than incorrectly replaying stale bytes.
    public func record(terminalID: SessionID, capture: Data) -> Snapshot {
        var transcript = transcripts[terminalID] ?? .init()
        guard capture != transcript.captured else {
            return Snapshot(sequence: transcript.sequence, bytes: transcript.retained, truncated: transcript.didTruncate)
        }

        let next: Data
        if capture.starts(with: transcript.captured) {
            next = Data(capture.dropFirst(transcript.captured.count))
        } else {
            transcript.retained = .init()
            transcript.didTruncate = false
            next = capture
        }
        transcript.captured = capture
        if !next.isEmpty {
            transcript.retained.append(next)
            if transcript.retained.count > maximumBytes {
                transcript.retained.removeFirst(transcript.retained.count - maximumBytes)
                transcript.didTruncate = true
            }
        }
        guard transcript.sequence < UInt64.max else {
            transcripts.removeValue(forKey: terminalID)
            return Snapshot(sequence: 0, bytes: .init(), truncated: true)
        }
        transcript.sequence += 1
        transcripts[terminalID] = transcript
        return Snapshot(sequence: transcript.sequence, bytes: transcript.retained, truncated: transcript.didTruncate)
    }

    public func snapshot(terminalID: SessionID, after sequence: UInt64) -> Snapshot {
        guard let transcript = transcripts[terminalID] else { return .init(sequence: 0, bytes: .init(), truncated: false) }
        guard sequence < transcript.sequence else { return .init(sequence: transcript.sequence, bytes: .init(), truncated: transcript.didTruncate) }
        return .init(sequence: transcript.sequence, bytes: transcript.retained, truncated: transcript.didTruncate)
    }
}
