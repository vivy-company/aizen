import AizenCore
import Foundation

/// Host-owned authority for remote terminal control. Terminal bytes stay in the runtime;
/// this actor only decides which paired device may submit ordered input.
public actor TerminalControlLeaseRegistry {
    public struct Lease: Sendable, Hashable {
        public let terminalID: SessionID
        public let deviceID: DeviceID
        public let expiresAt: Date

        public init(terminalID: SessionID, deviceID: DeviceID, expiresAt: Date) {
            self.terminalID = terminalID
            self.deviceID = deviceID
            self.expiresAt = expiresAt
        }
    }

    public enum Error: Swift.Error, Sendable, Equatable {
        case invalidDuration
        case controlledByAnotherDevice(DeviceID)
        case notController
        case invalidInputSequence
        case replayedInputSequence
        case inputSequenceExhausted
    }

    private struct InputStream: Hashable {
        let terminalID: SessionID
        let deviceID: DeviceID
    }

    private let now: @Sendable () -> Date
    private var leases: [SessionID: Lease] = [:]
    private var highestInputSequences: [InputStream: UInt64] = [:]

    public init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    /// Acquires or renews a bounded control lease. A disconnected device naturally loses
    /// control after expiry; no client-side cleanup is required for safety.
    public func acquire(terminalID: SessionID, deviceID: DeviceID, duration: TimeInterval = 60) throws -> Lease {
        guard (1...300).contains(duration) else { throw Error.invalidDuration }
        if let lease = activeLease(for: terminalID), lease.deviceID != deviceID {
            throw Error.controlledByAnotherDevice(lease.deviceID)
        }
        let lease = Lease(terminalID: terminalID, deviceID: deviceID, expiresAt: now().addingTimeInterval(duration))
        leases[terminalID] = lease
        return lease
    }

    public func release(terminalID: SessionID, deviceID: DeviceID) throws {
        guard let lease = activeLease(for: terminalID), lease.deviceID == deviceID else {
            throw Error.notController
        }
        leases.removeValue(forKey: terminalID)
    }

    public func currentLease(for terminalID: SessionID) -> Lease? {
        activeLease(for: terminalID)
    }

    /// Validates ownership and monotonically increasing terminal traffic before the runtime receives it.
    public func acceptOperation(terminalID: SessionID, deviceID: DeviceID, sequence: UInt64) throws {
        guard sequence > 0 else { throw Error.invalidInputSequence }
        guard let lease = activeLease(for: terminalID), lease.deviceID == deviceID else {
            throw Error.notController
        }
        let stream = InputStream(terminalID: terminalID, deviceID: deviceID)
        if let highest = highestInputSequences[stream] {
            guard highest != .max else { throw Error.inputSequenceExhausted }
            guard sequence > highest else { throw Error.replayedInputSequence }
        }
        highestInputSequences[stream] = sequence
    }

    private func activeLease(for terminalID: SessionID) -> Lease? {
        guard let lease = leases[terminalID] else { return nil }
        guard lease.expiresAt > now() else {
            leases.removeValue(forKey: terminalID)
            return nil
        }
        return lease
    }
}
