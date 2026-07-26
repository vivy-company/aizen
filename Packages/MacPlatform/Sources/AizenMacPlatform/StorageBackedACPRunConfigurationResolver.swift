import ACP
import AizenCore
import AizenStorage
import Foundation

/// The executable inputs selected by the Host's agent configuration boundary.
/// Secrets remain in the resolved environment and never enter Storage snapshots.
public struct ACPAgentLaunchConfiguration: Sendable, Equatable {
    public let executablePath: String
    public let arguments: [String]
    public let environment: [String: String]

    public init(executablePath: String, arguments: [String] = [], environment: [String: String] = [:]) {
        precondition(!executablePath.isEmpty, "An ACP agent needs an executable")
        self.executablePath = executablePath
        self.arguments = arguments
        self.environment = environment
    }
}

/// Resolves the current Host-selected agent without exposing settings implementation to MacPlatform.
public protocol ACPAgentLaunchConfigurationResolving: Sendable {
    func launchConfiguration() async throws -> ACPAgentLaunchConfiguration
}

/// Maps a persisted Run to a Host-managed sandbox and the currently selected agent process.
public actor StorageBackedACPRunConfigurationResolver: ACPRunConfigurationResolving {
    public enum Error: Swift.Error, Sendable, Equatable {
        case unknownSession(SessionID)
        case missingExecutionContext(SessionID)
        case unknownExecutionContext(ExecutionContextID)
        case invalidExecutionContext(ExecutionContextID)
    }

    private let storage: StorageRepository
    private let agentConfiguration: any ACPAgentLaunchConfigurationResolving
    private let managedSandboxRoot: URL

    public init(
        storage: StorageRepository,
        agentConfiguration: any ACPAgentLaunchConfigurationResolving,
        managedSandboxRoot: URL
    ) {
        self.storage = storage
        self.agentConfiguration = agentConfiguration
        self.managedSandboxRoot = managedSandboxRoot.standardizedFileURL
    }

    public func configuration(for run: Run) async throws -> ACPRunConfiguration {
        let snapshot = try await storage.load()
        guard let session = snapshot.sessions.first(where: { $0.id == run.sessionID && $0.spaceID == run.spaceID }) else {
            throw Error.unknownSession(run.sessionID)
        }
        guard let executionContextID = run.executionContextID ?? session.executionContextID else {
            throw Error.missingExecutionContext(session.id)
        }
        guard let context = snapshot.executionContexts.first(where: { $0.id == executionContextID && $0.spaceID == run.spaceID }) else {
            throw Error.unknownExecutionContext(executionContextID)
        }
        guard context.kind == .managedTemporarySandbox || context.kind == .managedPersistentSandbox,
            context.hostReference?.rawValue == "sandbox-\(context.id.description)" else {
            throw Error.invalidExecutionContext(context.id)
        }

        let agent = try await agentConfiguration.launchConfiguration()
        let workingDirectory = managedSandboxRoot
            .appendingPathComponent(context.spaceID.description, isDirectory: true)
            .appendingPathComponent(context.id.description, isDirectory: true)
        return ACPRunConfiguration(
            executablePath: agent.executablePath,
            arguments: agent.arguments,
            workingDirectory: workingDirectory.path,
            environment: agent.environment
        )
    }
}

/// Projectless conversations do not expose filesystem or terminal tools until a Host tool policy is attached.
public struct NoACPToolDelegateProvider: ACPRunDelegateProviding {
    public init() {}

    public func delegate(for run: Run) async throws -> (any ClientDelegate)? { nil }
}
