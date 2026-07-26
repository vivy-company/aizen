import ACP
import AizenCore
import AizenHost
import AizenMacPlatform
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
