import AizenHost
import LocalAuthentication

/// Uses macOS device-owner authentication for remote actions that can modify local state or execute code.
public struct MacOwnerConfirmationAuthority: OwnerConfirmationAuthority {
    public init() {}

    public func confirm(_ request: OwnerConfirmationRequest) async -> OwnerConfirmationDecision {
        await confirmOnMainActor(request)
    }

    @MainActor
    private func confirmOnMainActor(_ request: OwnerConfirmationRequest) async -> OwnerConfirmationDecision {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return .unavailable
        }
        let reason = "Approve remote \(request.action.rawValue) requested by a paired Aizen device."
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { approved, _ in
                continuation.resume(returning: approved ? .approved : .denied)
            }
        }
    }
}
