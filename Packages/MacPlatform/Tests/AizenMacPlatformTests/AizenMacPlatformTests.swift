import ACP
import AizenCore
import AizenHost
import AizenMacPlatform
import AizenStorage
import Foundation
import Testing

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

private struct StaticConfigurationResolver: ACPRunConfigurationResolving {
    func configuration(for run: Run) async throws -> ACPRunConfiguration {
        ACPRunConfiguration(executablePath: "/usr/bin/true", workingDirectory: "/tmp/aizen")
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
