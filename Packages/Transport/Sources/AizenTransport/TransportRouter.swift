import Foundation
import AizenWire

/// Reachability is interchangeable; Host identity and authorisation are not.
public enum TransportRouteKind: String, Codable, Sendable, Hashable, CaseIterable {
    case lan
    case tailscale
    case cloudflare
    case custom

    public var defaultPriority: Int {
        switch self {
        case .lan: 0
        case .tailscale: 100
        case .cloudflare: 200
        case .custom: 300
        }
    }
}

public enum TransportRouteConfigurationError: Swift.Error, Sendable, Equatable {
    case insecureEndpoint
    case missingHostIdentity
}

/// A user-managed secure endpoint. Route-specific account concepts never enter Core or Wire.
public struct TransportRouteConfiguration: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let kind: TransportRouteKind
    public let endpoint: URL
    public let priority: Int
    public let isEnabled: Bool
    public let isDirect: Bool
    public let isConstrained: Bool
    /// An opaque, canonical Host fingerprint supplied by the pairing layer.
    public let expectedHostIdentity: String

    public init(
        id: UUID = UUID(),
        kind: TransportRouteKind,
        endpoint: URL,
        priority: Int? = nil,
        isEnabled: Bool = true,
        isDirect: Bool? = nil,
        isConstrained: Bool = false,
        expectedHostIdentity: String
    ) throws {
        guard endpoint.scheme?.lowercased() == "wss" else {
            throw TransportRouteConfigurationError.insecureEndpoint
        }
        guard !expectedHostIdentity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TransportRouteConfigurationError.missingHostIdentity
        }
        self.id = id
        self.kind = kind
        self.endpoint = endpoint
        self.priority = priority ?? kind.defaultPriority
        self.isEnabled = isEnabled
        self.isDirect = isDirect ?? (kind == .lan)
        self.isConstrained = isConstrained
        self.expectedHostIdentity = expectedHostIdentity
    }
}

public struct TransportRouteHealth: Sendable, Hashable {
    public var lastSuccessAt: Date?
    public var lastFailureAt: Date?
    public var lastFailureDescription: String?
    public var latency: Duration?
    public var consecutiveFailures: Int
    public var backoffUntil: Date?

    public init(
        lastSuccessAt: Date? = nil,
        lastFailureAt: Date? = nil,
        lastFailureDescription: String? = nil,
        latency: Duration? = nil,
        consecutiveFailures: Int = 0,
        backoffUntil: Date? = nil
    ) {
        self.lastSuccessAt = lastSuccessAt
        self.lastFailureAt = lastFailureAt
        self.lastFailureDescription = lastFailureDescription
        self.latency = latency
        self.consecutiveFailures = consecutiveFailures
        self.backoffUntil = backoffUntil
    }
}

public struct TransportRouteConnection: Sendable {
    public let transport: any WireTransport
    /// The identity authenticated by the secure-channel implementation, never a TLS hostname.
    public let authenticatedHostIdentity: String
    public let latency: Duration?

    public init(transport: any WireTransport, authenticatedHostIdentity: String, latency: Duration? = nil) {
        self.transport = transport
        self.authenticatedHostIdentity = authenticatedHostIdentity
        self.latency = latency
    }
}

public enum TransportRouterError: Swift.Error, Sendable, Equatable {
    case noEligibleRoute
    case hostIdentityMismatch(routeID: UUID)
}

/// Shared route selector. It never retries a request after a send failure: callers retain the
/// original command ID and decide when to replay through their durable outbox.
public actor TransportRouter: WireTransport {
    public typealias Connector = @Sendable (TransportRouteConfiguration) async throws -> TransportRouteConnection

    private let connector: Connector
    private let now: @Sendable () -> Date
    private var configurations: [UUID: TransportRouteConfiguration]
    private var health: [UUID: TransportRouteHealth]
    private var activeConnection: (configuration: TransportRouteConfiguration, connection: TransportRouteConnection)?

    public init(
        routes: [TransportRouteConfiguration],
        connector: @escaping Connector,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        configurations = Dictionary(uniqueKeysWithValues: routes.map { ($0.id, $0) })
        health = Dictionary(uniqueKeysWithValues: routes.map { ($0.id, TransportRouteHealth()) })
        self.connector = connector
        self.now = now
    }

    public func replaceRoutes(_ routes: [TransportRouteConfiguration]) {
        configurations = Dictionary(uniqueKeysWithValues: routes.map { ($0.id, $0) })
        health = health.filter { configurations[$0.key] != nil }
        for route in routes where health[route.id] == nil {
            health[route.id] = .init()
        }
        if let activeConnection, configurations[activeConnection.configuration.id] != activeConnection.configuration {
            self.activeConnection = nil
        }
    }

    public func activeRoute() -> TransportRouteConfiguration? {
        activeConnection?.configuration
    }

    public func routeHealth() -> [UUID: TransportRouteHealth] {
        health
    }

    public func disconnect() {
        activeConnection = nil
    }

    public func send(_ envelope: ProtocolEnvelope) async throws -> ProtocolEnvelope {
        let active = try await connectedRoute()
        do {
            let response = try await active.connection.transport.send(envelope)
            recordSuccess(for: active.configuration.id, latency: active.connection.latency)
            return response
        } catch {
            recordFailure(for: active.configuration.id, error: error)
            activeConnection = nil
            throw error
        }
    }

    private func connectedRoute() async throws -> (configuration: TransportRouteConfiguration, connection: TransportRouteConnection) {
        if let activeConnection { return activeConnection }
        for route in eligibleRoutes() {
            do {
                let connection = try await connector(route)
                guard connection.authenticatedHostIdentity == route.expectedHostIdentity else {
                    recordFailure(for: route.id, error: TransportRouterError.hostIdentityMismatch(routeID: route.id))
                    continue
                }
                recordSuccess(for: route.id, latency: connection.latency)
                let active = (configuration: route, connection: connection)
                activeConnection = active
                return active
            } catch {
                recordFailure(for: route.id, error: error)
            }
        }
        throw TransportRouterError.noEligibleRoute
    }

    private func eligibleRoutes() -> [TransportRouteConfiguration] {
        let currentTime = now()
        return configurations.values.filter { route in
            guard route.isEnabled else { return false }
            guard let backoffUntil = health[route.id]?.backoffUntil else { return true }
            return backoffUntil <= currentTime
        }.sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
            let lhsSuccess = health[lhs.id]?.lastSuccessAt ?? .distantPast
            let rhsSuccess = health[rhs.id]?.lastSuccessAt ?? .distantPast
            if lhsSuccess != rhsSuccess { return lhsSuccess > rhsSuccess }
            if lhs.isDirect != rhs.isDirect { return lhs.isDirect }
            return lhs.endpoint.absoluteString < rhs.endpoint.absoluteString
        }
    }

    private func recordSuccess(for routeID: UUID, latency: Duration?) {
        var value = health[routeID] ?? .init()
        value.lastSuccessAt = now()
        value.lastFailureDescription = nil
        value.latency = latency
        value.consecutiveFailures = 0
        value.backoffUntil = nil
        health[routeID] = value
    }

    private func recordFailure(for routeID: UUID, error: Error) {
        var value = health[routeID] ?? .init()
        value.lastFailureAt = now()
        value.lastFailureDescription = error.localizedDescription
        value.consecutiveFailures += 1
        // 1, 2, 4, 8, 16, then cap at 30 seconds; the bounded shift avoids overflow.
        let delay = min(30, 1 << min(value.consecutiveFailures - 1, 4))
        value.backoffUntil = now().addingTimeInterval(TimeInterval(delay))
        health[routeID] = value
    }
}
