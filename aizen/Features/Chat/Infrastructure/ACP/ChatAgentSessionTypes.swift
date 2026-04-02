import ACP
import Foundation

struct MessageItem: Identifiable, Equatable {
    let id: String
    let role: MessageRole
    let content: String
    let timestamp: Date
    var toolCalls: [ToolCall] = []
    var contentBlocks: [ContentBlock] = []
    var isComplete: Bool = false
    var startTime: Date?
    var executionTime: TimeInterval?
    var requestId: String?

    static func == (lhs: MessageItem, rhs: MessageItem) -> Bool {
        lhs.id == rhs.id &&
            lhs.content == rhs.content &&
            lhs.isComplete == rhs.isComplete &&
            lhs.contentBlocksSignature == rhs.contentBlocksSignature
    }

    private var contentBlocksSignature: (Int, String?) {
        let count = contentBlocks.count
        guard let last = contentBlocks.last else { return (count, nil) }
        let lastSignature: String
        switch last {
        case .text(let text):
            lastSignature = "text:\(text.text.count)"
        case .image(let image):
            lastSignature = "image:\(image.mimeType):\(image.data.count)"
        case .audio(let audio):
            lastSignature = "audio:\(audio.mimeType):\(audio.data.count)"
        case .resource(let resource):
            lastSignature = "resource:\(resource.resource.uri ?? ""):\(resource.resource.mimeType ?? "")"
        case .resourceLink(let link):
            lastSignature = "link:\(link.uri)"
        }
        return (count, lastSignature)
    }
}

enum MessageRole {
    case user
    case agent
    case system
}

enum AgentSessionError: LocalizedError {
    case sessionAlreadyActive
    case sessionNotActive
    case sessionResumeUnsupported
    case agentNotFound(String)
    case agentNotExecutable(String)
    case clientNotInitialized
    case custom(String)

    var errorDescription: String? {
        switch self {
        case .sessionAlreadyActive:
            return "Session is already active"
        case .sessionNotActive:
            return "No active session"
        case .sessionResumeUnsupported:
            return "Agent does not support session resume"
        case .agentNotFound(let name):
            return
                "Agent '\(name)' not configured. Please set the executable path in Settings → AI Agents, or click 'Auto Discover' to find it automatically."
        case .agentNotExecutable(let path):
            return "Agent at '\(path)' is not executable"
        case .clientNotInitialized:
            return "ACP client not initialized"
        case .custom(let message):
            return message
        }
    }
}
