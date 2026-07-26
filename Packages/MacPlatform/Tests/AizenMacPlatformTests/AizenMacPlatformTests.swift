import ACP
import AizenCore
import AizenHost
import AizenMacPlatform
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
    try await runtime.cancel(runID: run.id)
    #expect(await client.cancelledSessionID == "acp-session")
    #expect(await client.didTerminate)
}

private struct StaticConfigurationResolver: ACPRunConfigurationResolving {
    func configuration(for run: Run) async throws -> ACPRunConfiguration {
        ACPRunConfiguration(executablePath: "/usr/bin/true", workingDirectory: "/tmp/aizen")
    }
}

private struct NoDelegateProvider: ACPRunDelegateProviding {
    func delegate(for run: Run) async throws -> (any ACP.ClientDelegate)? { nil }
}

private struct StaticClientFactory: ACPRunClientFactory {
    let client: RecordingClient
    func makeClient() -> any ACPRunClient { client }
}

private actor RecordingClient: ACPRunClient {
    private(set) var startedWorkingDirectory: String?
    private(set) var cancelledSessionID: String?
    private(set) var didTerminate = false

    func start(configuration: ACPRunConfiguration, delegate: (any ACP.ClientDelegate)?) async throws -> String {
        startedWorkingDirectory = configuration.workingDirectory
        return "acp-session"
    }

    func cancel(sessionID: String) async throws { cancelledSessionID = sessionID }
    func terminate() async { didTerminate = true }
}
