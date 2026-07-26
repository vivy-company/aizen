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
        let agent = try await agentConfiguration.launchConfiguration()
        let workingDirectory: String
        if context.kind == .managedTemporarySandbox || context.kind == .managedPersistentSandbox {
            guard context.hostReference?.rawValue == "sandbox-\(context.id.description)" else {
                throw Error.invalidExecutionContext(context.id)
            }
            workingDirectory = managedSandboxRoot
                .appendingPathComponent(context.spaceID.description, isDirectory: true)
                .appendingPathComponent(context.id.description, isDirectory: true)
                .path
        } else if (context.kind == .localFolder || context.kind == .repositoryCheckout),
            let resourceID = context.resourceID,
            let resource = snapshot.resources.first(where: { $0.id == resourceID && $0.spaceID == run.spaceID }),
            case .hostPrivate(let reference) = resource.details,
            let prefix = context.kind == .localFolder ? "local-folder:" : "local-repository:",
            reference.rawValue.hasPrefix(prefix) {
            let path = String(reference.rawValue.dropFirst(prefix.count))
            let directory = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw Error.invalidExecutionContext(context.id)
            }
            workingDirectory = directory.path
        } else {
            throw Error.invalidExecutionContext(context.id)
        }
        return ACPRunConfiguration(
            executablePath: agent.executablePath,
            arguments: agent.arguments,
            workingDirectory: workingDirectory,
            environment: agent.environment
        )
    }
}

/// Projectless conversations do not expose filesystem or terminal tools until a Host tool policy is attached.
public struct NoACPToolDelegateProvider: ACPRunDelegateProviding {
    public init() {}

    public func delegate(for run: Run) async throws -> (any ClientDelegate)? { nil }
}
