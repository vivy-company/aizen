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
        struct Chunk: Sendable {
            let sequence: UInt64
            var bytes: Data
        }

        var sequence: UInt64 = 0
        var captured: Data = .init()
        var chunks: [Chunk] = []
        var retainedByteCount = 0
        var didTruncate = false

        var retained: Data {
            chunks.reduce(into: Data()) { $0.append($1.bytes) }
        }

        mutating func trim(to maximumBytes: Int) {
            while retainedByteCount > maximumBytes, !chunks.isEmpty {
                let excess = retainedByteCount - maximumBytes
                if chunks[0].bytes.count <= excess {
                    retainedByteCount -= chunks.removeFirst().bytes.count
                } else {
                    chunks[0].bytes.removeFirst(excess)
                    retainedByteCount -= excess
                }
                didTruncate = true
            }
        }

        func overlap(with newer: Data) -> Int? {
            let maximum = min(captured.count, newer.count)
            guard maximum > 0 else { return nil }
            for length in stride(from: maximum, through: 1, by: -1) {
                if captured.suffix(length) == newer.prefix(length) {
                    return length
                }
            }
            return nil
        }

        func ends(with suffix: Data) -> Bool {
            captured.count >= suffix.count && captured.suffix(suffix.count).elementsEqual(suffix)
        }
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
        } else if transcript.ends(with: capture) {
            next = .init()
        } else if let overlap = transcript.overlap(with: capture) {
            next = Data(capture.dropFirst(overlap))
        } else {
            transcript.chunks = []
            transcript.retainedByteCount = 0
            transcript.didTruncate = false
            next = capture
        }
        transcript.captured = capture
        guard transcript.sequence < UInt64.max else {
            transcripts.removeValue(forKey: terminalID)
            return Snapshot(sequence: 0, bytes: .init(), truncated: true)
        }
        transcript.sequence += 1
        if !next.isEmpty {
            transcript.chunks.append(.init(sequence: transcript.sequence, bytes: next))
            transcript.retainedByteCount += next.count
            transcript.trim(to: maximumBytes)
        }
        transcripts[terminalID] = transcript
        return Snapshot(sequence: transcript.sequence, bytes: transcript.retained, truncated: transcript.didTruncate)
    }

    public func snapshot(terminalID: SessionID, after sequence: UInt64) -> Snapshot {
        guard let transcript = transcripts[terminalID] else { return .init(sequence: 0, bytes: .init(), truncated: false) }
        guard sequence < transcript.sequence else { return .init(sequence: transcript.sequence, bytes: .init(), truncated: transcript.didTruncate) }
        let bytes = transcript.chunks
            .filter { $0.sequence > sequence }
            .reduce(into: Data()) { $0.append($1.bytes) }
        return .init(sequence: transcript.sequence, bytes: bytes, truncated: transcript.didTruncate)
    }
}
