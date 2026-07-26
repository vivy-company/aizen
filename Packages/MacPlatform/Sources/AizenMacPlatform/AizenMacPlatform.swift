import ACP
import AizenCore
import AizenHost
import Foundation

/// macOS-only adapters for ACP, terminals, filesystem, Git, Xcode, and Keychain.
public enum AizenMacPlatformModule {}

/// The resolved, non-secret process inputs for one ACP Run.
/// Resolution belongs to Host composition, where Space-scoped secure references can be accessed.
public struct ACPRunConfiguration: Sendable, Equatable {
    public let executablePath: String
    public let arguments: [String]
    public let workingDirectory: String
    public let environment: [String: String]

    public init(executablePath: String, arguments: [String] = [], workingDirectory: String, environment: [String: String] = [:]) {
        precondition(!executablePath.isEmpty, "An ACP Run needs an executable")
        precondition(!workingDirectory.isEmpty, "An ACP Run needs a working directory")
        self.executablePath = executablePath
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
    }
}

/// Resolves a Run into the platform process inputs after Host has checked its Space and Execution Context.
public protocol ACPRunConfigurationResolving: Sendable {
    func configuration(for run: Run) async throws -> ACPRunConfiguration
}

/// Supplies ACP tool and permission handling without coupling the runtime to SwiftUI or a managed object context.
public protocol ACPRunDelegateProviding: Sendable {
    func delegate(for run: Run) async throws -> (any ClientDelegate)?
}

/// Narrow external boundary that lets Host tests use fake ACP clients while production uses `ACP.Client`.
public protocol ACPRunClient: Sendable {
    func start(configuration: ACPRunConfiguration, delegate: (any ClientDelegate)?) async throws -> String
    func sendPrompt(sessionID: String, text: String) async throws -> String?
    func cancel(sessionID: String) async throws
    func terminate() async
}

public protocol ACPRunClientFactory: Sendable {
    func makeClient() -> any ACPRunClient
}

public struct SwiftACPClientFactory: ACPRunClientFactory {
    public init() {}

    public func makeClient() -> any ACPRunClient { SwiftACPClient() }
}

/// Production adapter around the actor supplied by swift-acp. It performs the real subprocess,
/// protocol initialization, and session creation steps before a Run becomes active.
public actor SwiftACPClient: ACPRunClient {
    private let client = Client()
    private var assistantTextBySession: [String: String] = [:]
    private var notificationTask: Task<Void, Never>?

    public init() {}

    public func start(configuration: ACPRunConfiguration, delegate: (any ClientDelegate)?) async throws -> String {
        await client.setDelegate(delegate)
        do {
            try await client.launch(
                agentPath: configuration.executablePath,
                arguments: configuration.arguments,
                workingDirectory: configuration.workingDirectory,
                environment: configuration.environment.isEmpty ? nil : configuration.environment
            )
            _ = try await client.initialize(
                protocolVersion: AizenCoreModule.protocolGeneration,
                capabilities: ClientCapabilities(
                    fs: FileSystemCapabilities(readTextFile: delegate != nil, writeTextFile: delegate != nil),
                    terminal: delegate != nil
                ),
                clientInfo: ClientInfo(name: "Aizen", title: "Aizen Host", version: AizenCoreModule.productVersion),
                timeout: 120
            )
            let session = try await client.newSession(workingDirectory: configuration.workingDirectory, timeout: 120)
            observeAssistantMessages(for: session.sessionId.value)
            return session.sessionId.value
        } catch {
            await client.setDelegate(nil)
            await client.terminate()
            throw error
        }
    }

    public func cancel(sessionID: String) async throws {
        try await client.sendCancelNotification(sessionId: SessionId(sessionID))
    }

    public func sendPrompt(sessionID: String, text: String) async throws -> String? {
        assistantTextBySession[sessionID] = ""
        _ = try await client.sendPrompt(sessionId: SessionId(sessionID), content: [.text(.init(text: text))])
        // ACP returns the prompt response before this consumer has necessarily drained every queued update.
        try? await Task.sleep(for: .milliseconds(100))
        let assistantText = assistantTextBySession[sessionID, default: ""]
        return assistantText.isEmpty ? nil : assistantText
    }

    public func terminate() async {
        notificationTask?.cancel()
        notificationTask = nil
        assistantTextBySession.removeAll()
        await client.setDelegate(nil)
        await client.terminate()
    }

    private func observeAssistantMessages(for sessionID: String) {
        notificationTask?.cancel()
        notificationTask = Task { [weak self, client] in
            for await notification in await client.notifications {
                guard let text = Self.assistantText(from: notification, expectedSessionID: sessionID) else { continue }
                await self?.appendAssistantText(text, for: sessionID)
            }
        }
    }

    private func appendAssistantText(_ text: String, for sessionID: String) {
        assistantTextBySession[sessionID, default: ""] += text
    }

    private nonisolated static func assistantText(from notification: JSONRPCNotification, expectedSessionID: String) -> String? {
        guard notification.method == "session/update",
            let params = notification.params?.value as? [String: Any],
            let data = try? JSONSerialization.data(withJSONObject: params),
            let update = try? JSONDecoder().decode(SessionUpdateNotification.self, from: data),
            update.sessionId.value == expectedSessionID,
            case .agentMessageChunk(.text(let content)) = update.update else {
            return nil
        }
        return content.text
    }
}

/// Host-owned ACP process lifetime. Clients can close without affecting this actor or its ACP subprocess.
public actor ACPRunRuntime: RunRuntime {
    public enum Error: Swift.Error, Sendable, Equatable {
        case duplicateRun(RunID)
        case unknownRun(RunID)
    }

    private struct ActiveRun: Sendable {
        let client: any ACPRunClient
        let sessionID: String
    }

    private let configurationResolver: any ACPRunConfigurationResolving
    private let delegateProvider: any ACPRunDelegateProviding
    private let clientFactory: any ACPRunClientFactory
    private var activeRuns: [RunID: ActiveRun] = [:]

    public init(
        configurationResolver: any ACPRunConfigurationResolving,
        delegateProvider: any ACPRunDelegateProviding,
        clientFactory: any ACPRunClientFactory = SwiftACPClientFactory()
    ) {
        self.configurationResolver = configurationResolver
        self.delegateProvider = delegateProvider
        self.clientFactory = clientFactory
    }

    public func start(run: Run) async throws {
        guard activeRuns[run.id] == nil else { throw Error.duplicateRun(run.id) }
        let configuration = try await configurationResolver.configuration(for: run)
        let delegate = try await delegateProvider.delegate(for: run)
        let client = clientFactory.makeClient()
        let sessionID = try await client.start(configuration: configuration, delegate: delegate)
        activeRuns[run.id] = ActiveRun(client: client, sessionID: sessionID)
    }

    public func cancel(runID: RunID) async throws {
        guard let activeRun = activeRuns.removeValue(forKey: runID) else { throw Error.unknownRun(runID) }
        do {
            try await activeRun.client.cancel(sessionID: activeRun.sessionID)
        } catch {
            await activeRun.client.terminate()
            throw error
        }
        await activeRun.client.terminate()
    }

    public func send(message: String, to runID: RunID) async throws -> String? {
        guard let activeRun = activeRuns[runID] else { throw Error.unknownRun(runID) }
        return try await activeRun.client.sendPrompt(sessionID: activeRun.sessionID, text: message)
    }
}

extension ACPRunRuntime: PromptRunRuntime {}
