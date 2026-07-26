import Foundation
import Testing
@testable import AizenTransport
import AizenWire

@Test func moduleLoads() { _ = AizenTransportModule.self }

@Test func routerPrefersTheConfiguredDirectRouteAndRejectsInsecureEndpoints() async throws {
    #expect(throws: TransportRouteConfigurationError.insecureEndpoint) {
        _ = try TransportRouteConfiguration(kind: .custom, endpoint: URL(string: "ws://example.test")!, expectedHostIdentity: "host")
    }

    let lan = try TransportRouteConfiguration(kind: .lan, endpoint: URL(string: "wss://aizen.local")!, priority: 0, expectedHostIdentity: "host")
    let tailscale = try TransportRouteConfiguration(kind: .tailscale, endpoint: URL(string: "wss://host.tailnet.ts.net")!, priority: 100, expectedHostIdentity: "host")
    let router = TransportRouter(routes: [tailscale, lan]) { route in
        .init(transport: EchoTransport(), authenticatedHostIdentity: route.expectedHostIdentity)
    }

    _ = try await router.send(envelope("first"))
    #expect(await router.activeRoute()?.id == lan.id)
}

@Test func routerRejectsMismatchedIdentityAndFallsBackWithoutResendingTheFailedRequest() async throws {
    let wrongIdentity = try TransportRouteConfiguration(kind: .lan, endpoint: URL(string: "wss://aizen.local")!, priority: 0, expectedHostIdentity: "expected")
    let healthy = try TransportRouteConfiguration(kind: .tailscale, endpoint: URL(string: "wss://host.tailnet.ts.net")!, priority: 100, expectedHostIdentity: "expected")
    let router = TransportRouter(routes: [wrongIdentity, healthy]) { route in
        if route.id == wrongIdentity.id {
            return .init(transport: EchoTransport(), authenticatedHostIdentity: "wrong")
        }
        return .init(transport: EchoTransport(), authenticatedHostIdentity: "expected")
    }

    _ = try await router.send(envelope("identity"))
    #expect(await router.activeRoute()?.id == healthy.id)
    #expect(await router.routeHealth()[wrongIdentity.id]?.consecutiveFailures == 1)
}

@Test func routerLeavesAnAmbiguousSendForTheCallerToReplay() async throws {
    let failing = try TransportRouteConfiguration(kind: .lan, endpoint: URL(string: "wss://aizen.local")!, expectedHostIdentity: "host")
    let router = TransportRouter(routes: [failing]) { _ in
        .init(transport: FailingTransport(), authenticatedHostIdentity: "host")
    }

    await #expect(throws: TransportTestError.failed) {
        _ = try await router.send(envelope("ambiguous"))
    }
    #expect(await router.activeRoute() == nil)
    #expect(await router.routeHealth()[failing.id]?.consecutiveFailures == 1)
}

private func envelope(_ messageID: String) -> ProtocolEnvelope {
    try! ProtocolEnvelope(messageID: messageID, connectionSequence: 1, kind: .hello, channel: .control, payload: .init(HelloPayload(minimumProtocolGeneration: 1, maximumProtocolGeneration: 1, productVersion: "2.0.0")))
}

private struct EchoTransport: WireTransport {
    func send(_ envelope: ProtocolEnvelope) async throws -> ProtocolEnvelope { envelope }
}

private enum TransportTestError: Error { case failed }

private struct FailingTransport: WireTransport {
    func send(_ envelope: ProtocolEnvelope) async throws -> ProtocolEnvelope { throw TransportTestError.failed }
}
