import AizenCore
import AizenStorage
import AizenTransport
import AizenWire
import Foundation

/// Host command/query composition. Mac-only runtime adapters stay outside this package.
public enum AizenHostModule {
    public static let protocolGeneration = AizenWireModule.protocolGeneration
}

/// Explicit local Host composition. It owns Storage but exposes only Wire envelopes and Core snapshots.
public actor LocalHost: WireEndpoint {
    private let storage: StorageRepository

    public init(storage: StorageRepository) {
        self.storage = storage
    }

    public func receive(_ envelope: ProtocolEnvelope) async throws -> ProtocolEnvelope {
        let snapshot = try await storage.load()
        let payload = try JSONEncoder().encode(snapshot)
        return ProtocolEnvelope(
            messageID: envelope.messageID,
            connectionID: envelope.connectionID,
            connectionSequence: envelope.connectionSequence,
            kind: envelope.kind == .hello ? .capabilities : .snapshot,
            channel: .state,
            correlationID: envelope.correlationID,
            payload: .init(identifier: .init(rawValue: "aizen.snapshot.host@1"), schemaVersion: 1, protobufBytes: payload, stateAffecting: true)
        )
    }
}

/// Host-facing runtime contract. ACP, Process, and UI concerns remain in a macOS adapter.
public protocol RunRuntime: Sendable {
    func start(run: Run) async throws
    func cancel(runID: RunID) async throws
}

public actor RunCoordinator {
    public enum Error: Swift.Error, Sendable, Equatable {
        case duplicateRun(RunID)
        case unknownRun(RunID)
        case invalidTransition(from: RunLifecycle, to: RunLifecycle)
    }

    private let storage: StorageRepository
    private let runtime: any RunRuntime

    public init(storage: StorageRepository, runtime: any RunRuntime) {
        self.storage = storage
        self.runtime = runtime
    }

    public func start(_ run: Run) async throws {
        guard run.lifecycle == .queued else { throw Error.invalidTransition(from: run.lifecycle, to: .running) }
        _ = try await storage.transact { snapshot in
            guard !snapshot.runs.contains(where: { $0.id == run.id }) else { throw Error.duplicateRun(run.id) }
            snapshot.runs.append(run)
        }
        do {
            try await runtime.start(run: run)
            try await updateLifecycle(.running, for: run.id)
        } catch {
            try? await updateLifecycle(.failed, for: run.id)
            throw error
        }
    }

    public func cancel(_ runID: RunID) async throws {
        guard let run = try await run(for: runID) else { throw Error.unknownRun(runID) }
        guard run.lifecycle.canTransition(to: .cancelled) else {
            throw Error.invalidTransition(from: run.lifecycle, to: .cancelled)
        }
        try await runtime.cancel(runID: runID)
        try await updateLifecycle(.cancelled, for: runID)
    }

    public func run(for id: RunID) async throws -> Run? {
        try await storage.load().runs.first(where: { $0.id == id })
    }

    private func updateLifecycle(_ lifecycle: RunLifecycle, for id: RunID) async throws {
        _ = try await storage.transact { snapshot in
            guard let index = snapshot.runs.firstIndex(where: { $0.id == id }) else { throw Error.unknownRun(id) }
            let current = snapshot.runs[index].lifecycle
            guard current.canTransition(to: lifecycle) else {
                throw Error.invalidTransition(from: current, to: lifecycle)
            }
            snapshot.runs[index].lifecycle = lifecycle
        }
    }
}
