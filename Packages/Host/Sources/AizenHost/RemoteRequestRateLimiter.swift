import AizenCore
import Foundation

public enum RemoteRequestKind: String, Sendable, Hashable, CaseIterable {
    case pairing
    case authentication
    case snapshot
    case unauthorizedCommand
}

public struct RemoteRequestSource: Sendable, Hashable {
    public let value: String

    public init(_ value: String) {
        precondition(!value.isEmpty && value.utf8.count <= 256, "Remote sources must be non-empty and bounded")
        self.value = value
    }
}

public struct RemoteRequestRateLimit: Sendable, Hashable {
    public let burst: Int
    public let refillWindow: TimeInterval

    public init(burst: Int, refillWindow: TimeInterval) {
        precondition(burst > 0 && refillWindow > 0, "Rate limits require positive capacity and refill window")
        self.burst = burst
        self.refillWindow = refillWindow
    }
}

public enum RemoteRequestRateLimitError: Swift.Error, Sendable, Equatable {
    case limited(RemoteRequestKind)
}

/// Actor-isolated, bounded token buckets keyed by request kind, network source, and known device.
public actor RemoteRequestRateLimiter {
    private struct Key: Hashable, Sendable {
        let kind: RemoteRequestKind
        let source: RemoteRequestSource
        let deviceID: DeviceID?
    }

    private struct Bucket: Sendable {
        var tokens: Double
        var lastUpdated: Date
    }

    public static let defaultLimits: [RemoteRequestKind: RemoteRequestRateLimit] = [
        .pairing: .init(burst: 5, refillWindow: 60),
        .authentication: .init(burst: 10, refillWindow: 60),
        .snapshot: .init(burst: 20, refillWindow: 60),
        .unauthorizedCommand: .init(burst: 10, refillWindow: 60)
    ]

    private let limits: [RemoteRequestKind: RemoteRequestRateLimit]
    private let maximumTrackedBuckets: Int
    private var buckets: [Key: Bucket] = [:]

    public init(limits: [RemoteRequestKind: RemoteRequestRateLimit] = RemoteRequestRateLimiter.defaultLimits, maximumTrackedBuckets: Int = 4_096) {
        precondition(maximumTrackedBuckets > 0, "Rate limiter needs at least one bucket")
        precondition(Set(limits.keys) == Set(RemoteRequestKind.allCases), "Every remote request kind needs a rate limit")
        self.limits = limits
        self.maximumTrackedBuckets = maximumTrackedBuckets
    }

    public func require(kind: RemoteRequestKind, source: RemoteRequestSource, deviceID: DeviceID? = nil, now: Date = Date()) throws {
        pruneExpiredBuckets(now: now)
        let key = Key(kind: kind, source: source, deviceID: deviceID)
        let limit = limits[kind]!
        guard var bucket = buckets[key] else {
            guard buckets.count < maximumTrackedBuckets else { throw RemoteRequestRateLimitError.limited(kind) }
            buckets[key] = Bucket(tokens: Double(limit.burst - 1), lastUpdated: now)
            return
        }
        let elapsed = max(0, now.timeIntervalSince(bucket.lastUpdated))
        bucket.tokens = min(Double(limit.burst), bucket.tokens + elapsed * Double(limit.burst) / limit.refillWindow)
        bucket.lastUpdated = now
        guard bucket.tokens >= 1 else {
            buckets[key] = bucket
            throw RemoteRequestRateLimitError.limited(kind)
        }
        bucket.tokens -= 1
        buckets[key] = bucket
    }

    private func pruneExpiredBuckets(now: Date) {
        buckets = buckets.filter { key, bucket in
            guard let limit = limits[key.kind] else { return false }
            return now.timeIntervalSince(bucket.lastUpdated) <= limit.refillWindow * 2
        }
    }
}
