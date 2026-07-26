import AizenCore
import Foundation

struct OperationOutput: Encodable, Equatable {
    let id: String
    let spaceID: String
    let sessionID: String?
    let lifecycle: String
    let progress: Double?
    let failure: String?

    init(operation: AizenCore.Operation) {
        id = operation.id.description
        spaceID = operation.spaceID.description
        sessionID = operation.sessionID?.description
        lifecycle = operation.lifecycle.rawValue
        progress = operation.progress
        failure = operation.failureDescription
    }

    private enum CodingKeys: String, CodingKey {
        case id, spaceID, sessionID, lifecycle, progress, failure
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(spaceID, forKey: .spaceID)
        if let sessionID {
            try values.encode(sessionID, forKey: .sessionID)
        } else {
            try values.encodeNil(forKey: .sessionID)
        }
        try values.encode(lifecycle, forKey: .lifecycle)
        try values.encodeIfPresent(progress, forKey: .progress)
        try values.encodeIfPresent(failure, forKey: .failure)
    }
}

struct OperationPayload: Encodable, Equatable {
    let operation: OperationOutput
}

struct OperationListPayload: Encodable, Equatable {
    let operations: [OperationOutput]
}
