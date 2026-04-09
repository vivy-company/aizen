//
//  ChatAgentSession.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import ACP
import Combine
import Foundation
import CoreData
import UniformTypeIdentifiers

/// ObservableObject that wraps Client for managing an agent session
@MainActor
class ChatAgentSession: ObservableObject {
    static let maxMessageCount = 500
    static let maxToolCallCount = 500
    // MARK: - Published Properties

    @Published var sessionId: SessionId?
    @Published var agentName: String
    @Published var workingDirectory: String

    // Tool calls stored in dictionary for O(1) lookup, with order array for chronological iteration
    @Published var toolCallsById: [String: ToolCall] = [:]
    @Published var toolCallOrder: [String] = []

    /// Computed property for ordered tool calls array (maintains API compatibility)
    var toolCalls: [ToolCall] {
        toolCallOrder.compactMap { toolCallsById[$0] }
    }

    @Published var messages: [MessageItem] = []
    @Published var currentIterationId: String?
    @Published var isActive: Bool = false
    @Published var sessionState: SessionState = .idle
    @Published var currentThought: String?
    @Published var error: String?
    @Published var isStreaming: Bool = false  // True while prompt request is in progress

    @Published var authMethods: [AuthMethod] = []
    @Published var needsAuthentication: Bool = false
    @Published var availableCommands: [AvailableCommand] = []
    @Published var currentMode: SessionMode?
    @Published var agentPlan: Plan?
    @Published var availableModes: [ModeInfo] = []
    @Published var availableModels: [ModelInfo] = []
    @Published var availableConfigOptions: [SessionConfigOption] = []
    @Published var currentModeId: String?
    @Published var currentModelId: String?

    // Agent setup state
    @Published var needsAgentSetup: Bool = false
    @Published var missingAgentName: String?
    @Published var setupError: String?

    // Version update state
    @Published var needsUpdate: Bool = false
    @Published var versionInfo: AgentVersionInfo?

    // MARK: - Internal Properties

    var acpClient: Client?
    var cancellables = Set<AnyCancellable>()
    var process: Process?
    var notificationTask: Task<Void, Never>?
    var notificationProcessingTask: Task<Void, Never>?
    var versionCheckTask: Task<Void, Never>?
    var finalizeMessageTask: Task<Void, Never>?
    
    // Session persistence
    var chatSessionId: UUID?  // Core Data ChatSession ID for persistence
    var lastAgentChunkAt: Date?
    static let finalizeIdleDelay: TimeInterval = 0.2
    var isModeChanging = false
    @Published var isResumingSession = false
    var resumeReplayAgentMessages: [String] = []
    var resumeReplayIndex: Int = 0
    var resumeReplayBuffer: String = ""
    var suppressResumedAgentMessages = false
    var persistedToolCallIds: Set<String> = []
    var thoughtBuffer: String = ""
    var thoughtFlushTask: Task<Void, Never>?
    static let thoughtUpdateInterval: TimeInterval = 0.06
    var pendingAgentText: String = ""
    var pendingAgentBlocks: [ContentBlock] = []
    var agentMessageFlushTask: Task<Void, Never>?
    static let agentMessageFlushInterval: TimeInterval = 0.05

    /// Currently pending Task tool calls (subagents) - used for parent tracking
    /// When only one Task is active, child tool calls are assigned to it
    /// When multiple Tasks are active (parallel), we cannot reliably assign parents
    var activeTaskIds: [String] = []
    /// Buffer tool call updates that arrive before the tool call itself
    var pendingToolCallUpdatesById: [String: [ToolCallUpdateDetails]] = [:]

    // Delegates
    let terminalDelegate = AgentTerminalDelegate()
    let permissionHandler = AgentPermissionHandler()
    var clientDelegateBridge: ChatAgentSessionClientDelegate!
    var agentCapabilities: AgentCapabilities?
    var promptCapabilities: PromptCapabilities? { agentCapabilities?.promptCapabilities }

    // MARK: - Initialization

    init(agentName: String = "", workingDirectory: String = "") {
        self.agentName = agentName
        self.workingDirectory = workingDirectory
        self.clientDelegateBridge = ChatAgentSessionClientDelegate(session: self)
    }
}
