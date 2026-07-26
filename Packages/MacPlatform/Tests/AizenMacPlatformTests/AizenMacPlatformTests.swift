import ACP
import AizenCore
import AizenHost
@testable import AizenMacPlatform
import AizenSecurity
import AizenStorage
import AizenTransport
import AizenWire
import Foundation
import Testing

@Test func hostMachServiceConfigurationBuildsTheTeamRequirement() throws {
    let configuration = try HostMachServiceConfiguration(
        machServiceName: "win.aizen.host",
        teamIdentifier: "QW4U57CXJX"
    )

    #expect(configuration.peerCodeSigningRequirement == "anchor apple generic and certificate leaf[subject.OU] = \"QW4U57CXJX\"")
    #expect(throws: HostMachServiceConfigurationError.invalidTeamIdentifier) {
        _ = try HostMachServiceConfiguration(machServiceName: "win.aizen.host", teamIdentifier: "QW4U57CXJX\"")
    }
}

@Test func hostIdentityIsStableAcrossHostRestarts() async throws {
    let persistence = MemoryHostIdentityPersistence()
    let first = try await HostIdentityStore(persistence: persistence).loadOrCreate(displayName: "Mac")
    let second = try await HostIdentityStore(persistence: persistence).loadOrCreate(displayName: "Renamed Mac")

    #expect(first.hostID == second.hostID)
    #expect(first.cryptographicIdentity.fingerprint == second.cryptographicIdentity.fingerprint)
    #expect(second.displayName == "Renamed Mac")
}

@Test func hostIdentityCredentialsKeepTheKeychainIdentityInMemoryOnly() async throws {
    let persistence = MemoryHostIdentityPersistence()
    let credentials = try await HostIdentityStore(persistence: persistence).loadOrCreateCredentials(displayName: "Mac")
    let message = Data("aizen-host".utf8)
    #expect(credentials.publicIdentity.cryptographicIdentity.verifies(signature: credentials.localIdentity.sign(message), message: message))
}

@Test func bonjourMetadataPublishesOnlyProtocolAndIdentityHints() throws {
    let identity = LocalCryptographicIdentity()
    let host = HostPublicIdentity(hostID: HostID(), displayName: "Wiedy's Mac", cryptographicIdentity: identity.publicIdentity())
    let metadata = HostBonjourMetadata(host: host, minimumProtocolGeneration: 1, maximumProtocolGeneration: 2)
    let values = metadata.txtRecord.mapValues { String(decoding: $0, as: UTF8.self) }

    #expect(Set(values.keys) == ["pr", "h", "fp", "pair"])
    #expect(values["pr"] == "1-2")
    #expect(values["fp"] == host.cryptographicIdentity.fingerprint.prefix)
    #expect(values["pair"] == "1")
    #expect(values.values.joined().contains("Wiedy") == false)
}

@Test func pairedTLSOptionsKeepTheHostReachableBeforeFirstPairing() throws {
    let hostIdentity = LocalCryptographicIdentity()
    let host = HostPublicIdentity(hostID: HostID(), displayName: "Mac", cryptographicIdentity: hostIdentity.publicIdentity())
    let device = DevicePublicIdentity(deviceID: DeviceID(), displayName: "Phone", platform: "iOS", cryptographicIdentity: LocalCryptographicIdentity().publicIdentity())
    _ = try PairedTLSOptions.server(host: host, hostIdentity: hostIdentity, authorizations: [])
    _ = try PairedTLSOptions.server(host: host, hostIdentity: hostIdentity, authorizations: [.init(device: device, grants: [.init(capability: .hostRead)])])
}

@Test func lanWebSocketProcessorAuthenticatesAndSealsRemoteRequests() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "LAN")
    _ = try await storage.transact { $0.spaces.append(space) }
    let hostIdentity = LocalCryptographicIdentity()
    let host = HostPublicIdentity(hostID: HostID(), displayName: "Mac", cryptographicIdentity: hostIdentity.publicIdentity())
    let deviceIdentity = LocalCryptographicIdentity()
    let device = DevicePublicIdentity(deviceID: DeviceID(), displayName: "Phone", platform: "iOS", cryptographicIdentity: deviceIdentity.publicIdentity())
    try await storage.saveDeviceAuthorization(.init(device: device, grants: [.init(capability: .hostRead)]))
    let source = RemoteRequestSource("192.168.1.20")
    let rateLimiter = RemoteRequestRateLimiter()
    let processor = HostLANWebSocketProcessor(
        authenticator: RemoteSessionAuthenticator(host: host, hostIdentity: hostIdentity, storage: storage, rateLimiter: rateLimiter),
        endpoint: LocalHost(storage: storage),
        storage: storage,
        authorization: DeviceAuthorizationGate(storage: storage),
        rateLimiter: rateLimiter,
        source: source
    )
    let connectionID = UUID()
    let clientEphemeral = ConnectionEphemeralKey()
    let start = AuthenticationStartPayload(
        hostID: host.hostID,
        deviceID: device.deviceID,
        connectionID: connectionID,
        clientNonce: Data(repeating: 1, count: 32),
        deviceSigningPublicKey: device.cryptographicIdentity.signingPublicKey,
        deviceKeyAgreementPublicKey: device.cryptographicIdentity.keyAgreementPublicKey,
        clientEphemeralPublicKey: clientEphemeral.publicKey,
        route: "lan"
    )
    let startEnvelope = try ProtocolEnvelope(
        messageID: "start",
        connectionID: connectionID.uuidString,
        connectionSequence: 1,
        kind: .authentication,
        channel: .control,
        payload: .init(start)
    )
    let challengeEnvelope = try ProtocolEnvelope(serializedData: try await processor.receive(startEnvelope.serializedData()))
    let challenge = try AuthenticationChallengePayload(protobufBytes: challengeEnvelope.payload.protobufBytes)
    let binding = try ConnectionAuthenticationBinding(
        protocolGeneration: challengeEnvelope.protocolGeneration,
        hostID: challenge.hostID,
        deviceID: challenge.deviceID,
        connectionID: challenge.connectionID,
        clientNonce: challenge.clientNonce,
        serverNonce: challenge.serverNonce,
        clientEphemeralPublicKey: clientEphemeral.publicKey,
        serverEphemeralPublicKey: challenge.serverEphemeralPublicKey,
        route: .lan
    )
    let proof = ConnectionAuthenticator.makeProof(participant: .device, identity: deviceIdentity, binding: binding)
    let proofEnvelope = ProtocolEnvelope(
        messageID: "proof",
        connectionID: connectionID.uuidString,
        connectionSequence: 2,
        kind: .authentication,
        channel: .control,
        payload: try .init(AuthenticationProofPayload(connectionID: connectionID, deviceSignature: proof.signature))
    )
    let deviceKeys = try ConnectionAuthenticator.deriveKeys(participant: .device, ephemeralKey: clientEphemeral, peerEphemeralPublicKey: challenge.serverEphemeralPublicKey, binding: binding)
    let deviceChannel = AuthenticatedWireChannel(keys: deviceKeys, binding: binding)
    let capabilities = try await deviceChannel.open(try await processor.receive(proofEnvelope.serializedData()))
    #expect(capabilities.kind == .capabilities)

    let request = ProtocolEnvelope(messageID: "spaces", connectionSequence: 3, kind: .query, channel: .state, payload: try .init(ListSpacesQueryPayload()))
    let response = try await deviceChannel.open(try await processor.receive(try await deviceChannel.seal(request)))
    #expect(try ListSpacesResponsePayload(protobufBytes: response.payload.protobufBytes).spaces.map(\.name) == ["LAN"])
}

@Test func localHostRuntimeOwnsTheStorageBackedHost() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let runtime = LocalHostRuntime(storageURL: root.appendingPathComponent("storage-v2.json"))
    let transport = InProcessTransport(endpoint: runtime.host)
    let request = ProtocolEnvelope(
        messageID: "runtime-space",
        connectionSequence: 1,
        kind: .command,
        channel: .state,
        payload: try .init(CreateSpaceCommandPayload(name: "Runtime"))
    )

    let response = try await transport.send(request)

    #expect(UUID(uuidString: try CreateSpaceResultPayload(protobufBytes: response.payload.protobufBytes).spaceID) != nil)
}

@Test func hostAgentLaunchConfigurationKeepsEnvironmentOutOfTheConfigurationFile() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let secrets = RecordingEnvironmentStore()
    let store = HostAgentLaunchConfigurationStore(
        configurationURL: root.appendingPathComponent("host-agent-launch.json"),
        secrets: secrets
    )
    let command = ConfigureAgentLaunchCommandPayload(
        executablePath: "/usr/bin/env",
        arguments: ["codex-acp"],
        environment: ["TOKEN": "secret"]
    )

    try await store.updateAgentLaunchConfiguration(command)

    #expect(try await store.launchConfiguration() == ACPAgentLaunchConfiguration(
        executablePath: "/usr/bin/env",
        arguments: ["codex-acp"],
        environment: ["TOKEN": "secret"]
    ))
    #expect(String(decoding: try Data(contentsOf: root.appendingPathComponent("host-agent-launch.json")), as: UTF8.self).contains("secret") == false)
}

@Test func xpcWireServiceRoundTripsTheWireEnvelope() async throws {
    let request = ProtocolEnvelope(
        messageID: "xpc-round-trip",
        connectionSequence: 1,
        kind: .command,
        channel: .state,
        payload: try .init(ListSpacesQueryPayload())
    )
    let requestData = try request.serializedData()
    let service = XPCWireService(endpoint: EchoWireEndpoint())
    let responseData: Data = try await withCheckedThrowingContinuation { continuation in
        service.send(requestData) { data, error in
            if let error {
                continuation.resume(throwing: error)
            } else if let data {
                continuation.resume(returning: data)
            } else {
                continuation.resume(throwing: XPCWireTransportError.invalidResponse)
            }
        }
    }

    #expect(try ProtocolEnvelope(serializedData: responseData) == request)
}

@Test func xpcWireTransportRoundTripsThroughAnAcceptedConnection() async throws {
    let request = ProtocolEnvelope(
        messageID: "xpc-connection-round-trip",
        connectionSequence: 1,
        kind: .query,
        channel: .state,
        payload: try .init(ListSpacesQueryPayload())
    )
    let listener = XPCWireHostListener(wireEndpoint: EchoWireEndpoint())
    listener.resume()
    defer { listener.invalidate() }

    let endpoint = try #require(listener.listenerEndpoint)
    let response = try await XPCWireTransport(listenerEndpoint: endpoint).send(request)

    #expect(response == request)
}

@Test func acpRuntimeOwnsTheClientUntilTheRunIsCancelled() async throws {
    let client = RecordingClient()
    let runtime = ACPRunRuntime(
        configurationResolver: StaticConfigurationResolver(),
        delegateProvider: NoDelegateProvider(),
        clientFactory: StaticClientFactory(client: client)
    )
    let run = Run(spaceID: SpaceID(), sessionID: SessionID())
    try await runtime.start(run: run)
    #expect(await client.startedWorkingDirectory == "/tmp/aizen")
    #expect(try await runtime.send(message: "Hello", to: run.id, onAssistantTextDelta: { _ in }) == "Hello from ACP")
    #expect(await client.promptedText == "Hello")
    try await runtime.cancel(runID: run.id)
    #expect(await client.cancelledSessionID == "acp-session")
    #expect(await client.didTerminate)
}

@Test func storageBackedConfigurationUsesTheRunSandbox() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Vivy")
    let contextID = ExecutionContextID()
    let context = ExecutionContext(
        id: contextID,
        spaceID: space.id,
        kind: .managedTemporarySandbox,
        hostReference: HostPrivateReference(rawValue: "sandbox-\(contextID.description)")
    )
    let session = Session(spaceID: space.id, kind: .conversation, title: "Plan", executionContextID: context.id)
    _ = try await storage.transact {
        $0.spaces.append(space)
        $0.sessions.append(session)
        $0.executionContexts.append(context)
    }
    let run = Run(spaceID: space.id, sessionID: session.id, executionContextID: context.id)
    let resolver = StorageBackedACPRunConfigurationResolver(
        storage: storage,
        agentConfiguration: StaticAgentConfigurationResolver(),
        managedSandboxRoot: root.appendingPathComponent("sandboxes", isDirectory: true)
    )

    let configuration = try await resolver.configuration(for: run)
    #expect(configuration.executablePath == "/usr/bin/true")
    #expect(configuration.workingDirectory == root.appendingPathComponent("sandboxes").appendingPathComponent(space.id.description).appendingPathComponent(context.id.description).path)
}

@Test func storageBackedConfigurationUsesAHostOwnedLocalFolderResource() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("folder", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Vivy")
    let resource = Resource(spaceID: space.id, kind: .folder, title: "Folder", details: .hostPrivate(.init(rawValue: "local-folder:\(folder.path)")))
    let context = ExecutionContext(spaceID: space.id, kind: .localFolder, resourceID: resource.id, hostReference: .init(rawValue: "resource-context:\(resource.id.description)"))
    let session = Session(spaceID: space.id, kind: .conversation, title: "Plan", executionContextID: context.id)
    _ = try await storage.transact {
        $0.spaces.append(space)
        $0.resources.append(resource)
        $0.executionContexts.append(context)
        $0.sessions.append(session)
    }
    let resolver = StorageBackedACPRunConfigurationResolver(
        storage: storage,
        agentConfiguration: StaticAgentConfigurationResolver(),
        managedSandboxRoot: root.appendingPathComponent("sandboxes", isDirectory: true)
    )

    #expect(try await resolver.configuration(for: Run(spaceID: space.id, sessionID: session.id, executionContextID: context.id)).workingDirectory == folder.path)
}

@Test func storageBackedConfigurationUsesAHostOwnedRepositoryResource() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = root.appendingPathComponent("repository", isDirectory: true)
    try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Vivy")
    let resource = Resource(spaceID: space.id, kind: .repository, title: "Repository", details: .hostPrivate(.init(rawValue: "local-repository:\(repository.path)")))
    let context = ExecutionContext(spaceID: space.id, kind: .repositoryCheckout, resourceID: resource.id, hostReference: .init(rawValue: "repository-checkout:\(resource.id.description)"))
    let session = Session(spaceID: space.id, kind: .conversation, title: "Plan", executionContextID: context.id)
    _ = try await storage.transact {
        $0.spaces.append(space)
        $0.resources.append(resource)
        $0.executionContexts.append(context)
        $0.sessions.append(session)
    }
    let resolver = StorageBackedACPRunConfigurationResolver(storage: storage, agentConfiguration: StaticAgentConfigurationResolver(), managedSandboxRoot: root.appendingPathComponent("sandboxes", isDirectory: true))
    #expect(try await resolver.configuration(for: Run(spaceID: space.id, sessionID: session.id, executionContextID: context.id)).workingDirectory == repository.path)
}

private struct StaticConfigurationResolver: ACPRunConfigurationResolving {
    func configuration(for run: Run) async throws -> ACPRunConfiguration {
        ACPRunConfiguration(executablePath: "/usr/bin/true", workingDirectory: "/tmp/aizen")
    }
}

private struct EchoWireEndpoint: WireEndpoint {
    func receive(_ envelope: ProtocolEnvelope) async throws -> ProtocolEnvelope {
        envelope
    }
}

private final class MemoryHostIdentityPersistence: @unchecked Sendable, HostIdentityPersisting {
    private let lock = NSLock()
    private var data: Data?

    func load() throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return data
    }

    func save(_ data: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        self.data = data
    }
}

private final class RecordingEnvironmentStore: @unchecked Sendable, HostAgentEnvironmentStoring {
    private var value: [String: String] = [:]

    func store(environment: [String: String]) throws {
        value = environment
    }

    func environment() throws -> [String: String] {
        value
    }
}

private struct NoDelegateProvider: ACPRunDelegateProviding {
    func delegate(for run: Run) async throws -> (any ACP.ClientDelegate)? { nil }
}

private struct StaticAgentConfigurationResolver: ACPAgentLaunchConfigurationResolving {
    func launchConfiguration() async throws -> ACPAgentLaunchConfiguration {
        ACPAgentLaunchConfiguration(executablePath: "/usr/bin/true")
    }
}

private struct StaticClientFactory: ACPRunClientFactory {
    let client: RecordingClient
    func makeClient() -> any ACPRunClient { client }
}

private actor RecordingClient: ACPRunClient {
    private(set) var startedWorkingDirectory: String?
    private(set) var cancelledSessionID: String?
    private(set) var promptedText: String?
    private(set) var didTerminate = false

    func start(configuration: ACPRunConfiguration, delegate: (any ACP.ClientDelegate)?) async throws -> String {
        startedWorkingDirectory = configuration.workingDirectory
        return "acp-session"
    }

    func sendPrompt(
        sessionID: String,
        text: String,
        onAssistantTextDelta: @escaping @Sendable (String) async -> Void
    ) async throws -> String? {
        promptedText = text
        await onAssistantTextDelta("Hello from ACP")
        return "Hello from ACP"
    }
    func cancel(sessionID: String) async throws { cancelledSessionID = sessionID }
    func terminate() async { didTerminate = true }
}
