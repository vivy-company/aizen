import AizenCore
import AizenSecurity
import AizenStorage
import AizenTransport
import AizenWire
import Foundation

public enum RemoteHostAuthorizationError: Swift.Error, Sendable, Equatable {
    case unsupportedPayload(PayloadIdentifier)
    case malformedReference(String)
    case mismatchedSpace
}

/// Applies Host capability policy to every post-authentication remote Wire request before dispatch.
public struct RemoteHostEndpoint: WireEndpoint {
    private struct Requirement: Sendable {
        let capability: HostCapability
        let spaceID: SpaceID?
        let resourceID: ResourceID?
        let rateLimitKind: RemoteRequestKind?
    }

    private let endpoint: any WireEndpoint
    private let storage: StorageRepository
    private let authorization: DeviceAuthorizationGate
    private let rateLimiter: RemoteRequestRateLimiter
    private let session: AuthenticatedRemoteSession
    private let source: RemoteRequestSource

    public init(
        endpoint: any WireEndpoint,
        storage: StorageRepository,
        authorization: DeviceAuthorizationGate,
        rateLimiter: RemoteRequestRateLimiter,
        session: AuthenticatedRemoteSession,
        source: RemoteRequestSource
    ) {
        self.endpoint = endpoint
        self.storage = storage
        self.authorization = authorization
        self.rateLimiter = rateLimiter
        self.session = session
        self.source = source
    }

    public func receive(_ envelope: ProtocolEnvelope) async throws -> ProtocolEnvelope {
        let requirement = try await requirement(for: envelope)
        if let rateLimitKind = requirement.rateLimitKind {
            try await rateLimiter.require(kind: rateLimitKind, source: source, deviceID: session.deviceID)
        }
        do {
            try await authorization.require(
                deviceID: session.deviceID,
                capability: requirement.capability,
                spaceID: requirement.spaceID,
                resourceID: requirement.resourceID,
                route: session.route.rawValue
            )
        } catch {
            try await rateLimiter.require(kind: .unauthorizedCommand, source: source, deviceID: session.deviceID)
            throw error
        }
        return try await endpoint.receive(envelope)
    }

    private func requirement(for envelope: ProtocolEnvelope) async throws -> Requirement {
        switch envelope.payload.identifier {
        case HelloPayload.identifier, CapabilitiesPayload.identifier:
            return .init(capability: .hostRead, spaceID: nil, resourceID: nil, rateLimitKind: nil)
        case SnapshotRequestPayload.identifier:
            return .init(capability: .hostRead, spaceID: nil, resourceID: nil, rateLimitKind: .snapshot)
        case ReadJournalEventsQueryPayload.identifier:
            let request = try ReadJournalEventsQueryPayload(protobufBytes: envelope.payload.protobufBytes)
            if let rawSpaceID = request.spaceID {
                return .init(capability: .spaceRead, spaceID: try spaceID(rawSpaceID), resourceID: nil, rateLimitKind: nil)
            }
            return .init(capability: .hostRead, spaceID: nil, resourceID: nil, rateLimitKind: nil)
        case ListSpacesQueryPayload.identifier:
            return .init(capability: .hostRead, spaceID: nil, resourceID: nil, rateLimitKind: nil)
        case ListConversationsQueryPayload.identifier:
            let request = try ListConversationsQueryPayload(protobufBytes: envelope.payload.protobufBytes)
            return try requirementForOptionalSpace(request.spaceID)
        case ListRunsQueryPayload.identifier:
            let request = try ListRunsQueryPayload(protobufBytes: envelope.payload.protobufBytes)
            return try requirementForOptionalSpace(request.spaceID)
        case ListResourcesQueryPayload.identifier:
            let request = try ListResourcesQueryPayload(protobufBytes: envelope.payload.protobufBytes)
            return try requirementForOptionalSpace(request.spaceID)
        case DiscoverXcodeProjectQueryPayload.identifier:
            let request = try DiscoverXcodeProjectQueryPayload(protobufBytes: envelope.payload.protobufBytes)
            let resource = try await requiredResource(request.resourceID)
            return .init(capability: .xcodeRead, spaceID: resource.spaceID, resourceID: resource.id, rateLimitKind: nil)
        case OpenXcodeProjectCommandPayload.identifier:
            let request = try OpenXcodeProjectCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let resource = try await requiredResource(request.resourceID)
            return .init(capability: .xcodeBuild, spaceID: resource.spaceID, resourceID: resource.id, rateLimitKind: nil)
        case ListExecutionContextsQueryPayload.identifier:
            let request = try ListExecutionContextsQueryPayload(protobufBytes: envelope.payload.protobufBytes)
            if let rawResourceID = request.resourceID {
                let resource = try await requiredResource(rawResourceID)
                return .init(capability: .resourceRead, spaceID: resource.spaceID, resourceID: resource.id, rateLimitKind: nil)
            }
            return try requirementForOptionalSpace(request.spaceID)
        case ListTerminalSessionsQueryPayload.identifier:
            let request = try ListTerminalSessionsQueryPayload(protobufBytes: envelope.payload.protobufBytes)
            return try requirementForOptionalSpace(request.spaceID)
        case ListContextFilesQueryPayload.identifier:
            let request = try ListContextFilesQueryPayload(protobufBytes: envelope.payload.protobufBytes)
            let context = try await requiredExecutionContext(request.executionContextID)
            return .init(capability: .fileRead, spaceID: context.spaceID, resourceID: context.resourceID, rateLimitKind: nil)
        case ReadContextTextFileQueryPayload.identifier:
            let request = try ReadContextTextFileQueryPayload(protobufBytes: envelope.payload.protobufBytes)
            let context = try await requiredExecutionContext(request.executionContextID)
            return .init(capability: .fileRead, spaceID: context.spaceID, resourceID: context.resourceID, rateLimitKind: nil)
        case GetConversationTimelineQueryPayload.identifier:
            let request = try GetConversationTimelineQueryPayload(protobufBytes: envelope.payload.protobufBytes)
            let conversation = try await requiredSession(request.sessionID)
            return .init(capability: .sessionRead, spaceID: conversation.spaceID, resourceID: nil, rateLimitKind: nil)
        case CreateSpaceCommandPayload.identifier, RenameSpaceCommandPayload.identifier, DeleteSpaceCommandPayload.identifier,
             ConfigureAgentLaunchCommandPayload.identifier, AttachExecutionContextCommandPayload.identifier,
             DetachExecutionContextCommandPayload.identifier, RemoveExecutionContextCommandPayload.identifier:
            return .init(capability: .hostAdmin, spaceID: nil, resourceID: nil, rateLimitKind: nil)
        case CreateConversationCommandPayload.identifier:
            let request = try CreateConversationCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            return .init(capability: .conversationSend, spaceID: try spaceID(request.spaceID), resourceID: nil, rateLimitKind: nil)
        case SendConversationCommandPayload.identifier:
            let request = try SendConversationCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let conversation = try await requiredSession(request.sessionID)
            let requestedSpaceID = try spaceID(request.spaceID)
            guard conversation.spaceID == requestedSpaceID else { throw RemoteHostAuthorizationError.mismatchedSpace }
            return .init(capability: .conversationSend, spaceID: conversation.spaceID, resourceID: nil, rateLimitKind: nil)
        case CancelRunCommandPayload.identifier:
            let request = try CancelRunCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let run = try await requiredRun(request.runID)
            return .init(capability: .conversationCancel, spaceID: run.spaceID, resourceID: nil, rateLimitKind: nil)
        case ImportLocalFolderCommandPayload.identifier, ImportLocalRepositoryCommandPayload.identifier,
             ImportWebResourceCommandPayload.identifier:
            let spaceID: SpaceID
            if envelope.payload.identifier == ImportLocalFolderCommandPayload.identifier {
                spaceID = try self.spaceID(try ImportLocalFolderCommandPayload(protobufBytes: envelope.payload.protobufBytes).spaceID)
            } else if envelope.payload.identifier == ImportLocalRepositoryCommandPayload.identifier {
                spaceID = try self.spaceID(try ImportLocalRepositoryCommandPayload(protobufBytes: envelope.payload.protobufBytes).spaceID)
            } else {
                spaceID = try self.spaceID(try ImportWebResourceCommandPayload(protobufBytes: envelope.payload.protobufBytes).spaceID)
            }
            return .init(capability: .fileRead, spaceID: spaceID, resourceID: nil, rateLimitKind: nil)
        case RemoveResourceCommandPayload.identifier:
            let request = try RemoveResourceCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let resource = try await requiredResource(request.resourceID)
            return .init(capability: .fileWrite, spaceID: resource.spaceID, resourceID: resource.id, rateLimitKind: nil)
        case RefreshRepositoryResourceCommandPayload.identifier:
            let request = try RefreshRepositoryResourceCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let resource = try await requiredResource(request.resourceID)
            return .init(capability: .gitRead, spaceID: resource.spaceID, resourceID: resource.id, rateLimitKind: nil)
        case CreateTerminalSessionCommandPayload.identifier:
            let request = try CreateTerminalSessionCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let requestedSpaceID = try spaceID(request.spaceID)
            let context = try await requiredExecutionContext(request.executionContextID)
            guard context.spaceID == requestedSpaceID else { throw RemoteHostAuthorizationError.mismatchedSpace }
            return .init(capability: .terminalCreate, spaceID: context.spaceID, resourceID: context.resourceID, rateLimitKind: nil)
        case CreateLocalFolderContextCommandPayload.identifier:
            let request = try CreateLocalFolderContextCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let requestedSpaceID = try spaceID(request.spaceID)
            let resource = try await requiredResource(request.resourceID)
            guard resource.spaceID == requestedSpaceID else { throw RemoteHostAuthorizationError.mismatchedSpace }
            return .init(capability: .fileRead, spaceID: resource.spaceID, resourceID: resource.id, rateLimitKind: nil)
        case CreateRepositoryCheckoutContextCommandPayload.identifier:
            let request = try CreateRepositoryCheckoutContextCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let requestedSpaceID = try spaceID(request.spaceID)
            let resource = try await requiredResource(request.resourceID)
            guard resource.spaceID == requestedSpaceID else { throw RemoteHostAuthorizationError.mismatchedSpace }
            return .init(capability: .gitRead, spaceID: resource.spaceID, resourceID: resource.id, rateLimitKind: nil)
        default:
            throw RemoteHostAuthorizationError.unsupportedPayload(envelope.payload.identifier)
        }
    }

    private func requirementForOptionalSpace(_ rawSpaceID: String?) throws -> Requirement {
        if let rawSpaceID {
            return .init(capability: .spaceRead, spaceID: try spaceID(rawSpaceID), resourceID: nil, rateLimitKind: nil)
        }
        return .init(capability: .hostRead, spaceID: nil, resourceID: nil, rateLimitKind: nil)
    }

    private func requiredSession(_ rawID: String) async throws -> Session {
        let id = try sessionID(rawID)
        guard let session = try await storage.load().sessions.first(where: { $0.id == id }) else {
            throw RemoteHostAuthorizationError.malformedReference(rawID)
        }
        return session
    }

    private func requiredRun(_ rawID: String) async throws -> Run {
        let id = try runID(rawID)
        guard let run = try await storage.load().runs.first(where: { $0.id == id }) else {
            throw RemoteHostAuthorizationError.malformedReference(rawID)
        }
        return run
    }

    private func requiredResource(_ rawID: String) async throws -> Resource {
        let id = try resourceID(rawID)
        guard let resource = try await storage.load().resources.first(where: { $0.id == id }) else {
            throw RemoteHostAuthorizationError.malformedReference(rawID)
        }
        return resource
    }

    private func requiredExecutionContext(_ rawID: String) async throws -> ExecutionContext {
        guard let value = UUID(uuidString: rawID) else { throw RemoteHostAuthorizationError.malformedReference(rawID) }
        let id = ExecutionContextID(rawValue: value)
        guard let context = try await storage.load().executionContexts.first(where: { $0.id == id }) else {
            throw RemoteHostAuthorizationError.malformedReference(rawID)
        }
        return context
    }

    private func spaceID(_ rawValue: String) throws -> SpaceID {
        guard let value = UUID(uuidString: rawValue) else { throw RemoteHostAuthorizationError.malformedReference(rawValue) }
        return .init(rawValue: value)
    }

    private func sessionID(_ rawValue: String) throws -> SessionID {
        guard let value = UUID(uuidString: rawValue) else { throw RemoteHostAuthorizationError.malformedReference(rawValue) }
        return .init(rawValue: value)
    }

    private func runID(_ rawValue: String) throws -> RunID {
        guard let value = UUID(uuidString: rawValue) else { throw RemoteHostAuthorizationError.malformedReference(rawValue) }
        return .init(rawValue: value)
    }

    private func resourceID(_ rawValue: String) throws -> ResourceID {
        guard let value = UUID(uuidString: rawValue) else { throw RemoteHostAuthorizationError.malformedReference(rawValue) }
        return .init(rawValue: value)
    }
}
