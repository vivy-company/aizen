import AizenCore

/// Owns the one-shot continuations that bridge Host-visible permission requests to the ACP runtime.
public actor PendingPermissionRegistry {
    public enum Error: Swift.Error, Sendable, Equatable { case unknownRequest, invalidOption }

    private var requests: [PermissionRequestID: PendingPermissionRequest] = [:]
    private var continuations: [PermissionRequestID: CheckedContinuation<String, Never>] = [:]

    public init() {}

    public func request(_ request: PendingPermissionRequest) async -> String {
        await withCheckedContinuation { continuation in
            requests[request.id] = request
            continuations[request.id] = continuation
        }
    }

    public func pending(spaceID: SpaceID? = nil) -> [PendingPermissionRequest] {
        requests.values.filter { spaceID == nil || $0.spaceID == spaceID }.sorted { $0.id.description < $1.id.description }
    }

    public func respond(id: PermissionRequestID, optionID: String) throws {
        guard let request = requests[id] else { throw Error.unknownRequest }
        guard request.options.contains(where: { $0.id == optionID }) else { throw Error.invalidOption }
        requests.removeValue(forKey: id)
        guard let continuation = continuations.removeValue(forKey: id) else { throw Error.unknownRequest }
        continuation.resume(returning: optionID)
    }
}
