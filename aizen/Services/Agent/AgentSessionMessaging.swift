//
//  AgentSessionMessaging.swift
//  aizen
//
//  Messaging logic for AgentSession
//

import Foundation
import UniformTypeIdentifiers
import CoreData

// MARK: - AgentSession + Messaging

@MainActor
extension AgentSession {
    /// Send a message to the agent with optional file attachments
    func sendMessage(content: String, attachments: [ChatAttachment] = []) async throws {
        // Check session state - must be ready to send messages
        guard sessionState.isReady else {
            if sessionState.isInitializing {
                throw AgentSessionError.custom("Session is still initializing. Please wait...")
            }
            throw AgentSessionError.sessionNotActive
        }

        guard let sessionId = sessionId, isActive else {
            throw AgentSessionError.sessionNotActive
        }

        guard let client = acpClient else {
            throw AgentSessionError.clientNotInitialized
        }

        if suppressResumedAgentMessages {
            suppressResumedAgentMessages = false
            clearResumeReplayState()
        }

        // Start new iteration - previous tool calls remain visible but will be collapsed
        currentIterationId = UUID().uuidString

        // Mark any incomplete agent message as complete before starting new conversation turn
        markLastMessageComplete()
        resetFinalizeState()
        clearThoughtBuffer()

        // Build content blocks array for sending to agent
        var contentBlocks: [ContentBlock] = []

        // Build UI content blocks (for display - excludes prepended text from main block)
        var uiContentBlocks: [ContentBlock] = []

        // Collect text-based attachments to prepend to message (for agent)
        var prependedContent = ""
        for attachment in attachments {
            if let attachmentContent = attachment.contentForAgent {
                prependedContent += attachmentContent + "\n\n"
            }
        }

        // Add text content (with attachments prepended if any) - this goes to agent
        let fullContent = prependedContent.isEmpty ? content : prependedContent + content
        contentBlocks.append(.text(TextContent(text: fullContent, annotations: nil, _meta: nil)))

        // For UI, only add the typed message as main text block
        uiContentBlocks.append(.text(TextContent(text: content, annotations: nil, _meta: nil)))

        // Add attachments as appropriate content blocks
        for attachment in attachments {
            switch attachment {
            case .image(let data, let mimeType):
                // Pasted image - create ImageContent block
                let imageContent = ImageContent(
                    data: data.base64EncodedString(),
                    mimeType: mimeType
                )
                contentBlocks.append(.image(imageContent))
                uiContentBlocks.append(.image(imageContent))

            case .file(let url):
                // Check if it's an image file
                if attachment.isImage {
                    if let imageBlock = try? await createImageBlock(from: url) {
                        contentBlocks.append(imageBlock)
                        uiContentBlocks.append(imageBlock)
                    }
                } else {
                    if let resourceBlock = try? await createResourceBlock(from: url) {
                        contentBlocks.append(resourceBlock)
                        uiContentBlocks.append(resourceBlock)
                    }
                }

            case .text(let pastedText):
                // Pasted text - add as separate text block for UI display
                uiContentBlocks.append(
                    .text(TextContent(text: pastedText, annotations: nil, _meta: nil)))

            case .reviewComments, .buildError:
                // These are prepended to content for agent, but also show as attachment in UI
                if let attachmentContent = attachment.contentForAgent {
                    uiContentBlocks.append(
                        .text(TextContent(text: attachmentContent, annotations: nil, _meta: nil)))
                }
            }
        }

        // Add user message to UI with UI content blocks (typed text + attachments, not prepended content)
        addUserMessage(content, contentBlocks: uiContentBlocks)
        AgentUsageStore.shared.recordPrompt(agentId: agentName, attachmentsCount: attachments.count)

        // Mark streaming active before sending
        isStreaming = true

        do {
            // Send to agent - notifications arrive asynchronously via AsyncStream
            // Response comes AFTER all notifications are sent, but our notification
            // listener Task may not have processed them all yet
            _ = try await client.sendPrompt(sessionId: sessionId, content: contentBlocks)

            // Delay setting isStreaming = false to allow buffered notifications to be processed
            // The AsyncStream may still have notifications queued that need to update messages
            // Setting @Published properties during view updates causes undefined behavior
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                self.isStreaming = false
                self.scheduleFinalizeLastMessage()
            }
        } catch {
            // Reset streaming state on error (e.g., timeout)
            isStreaming = false
            if isAuthRequiredError(error) {
                needsAuthentication = true
                addSystemMessage("Authentication required. Use the login button or configure API keys in environment variables.")
            }
            throw error
        }

        // Don't mark message complete here - notifications may still be processing
        // Message gets marked complete when next user message is sent (line 38)
    }

    /// Cancel the current prompt turn
    func cancelCurrentPrompt() async {
        guard let sessionId = sessionId, isActive else {
            return
        }

        guard let client = acpClient else {
            return
        }

        do {
            // Send cancel notification
            try await client.sendCancelNotification(sessionId: sessionId)

            // Reset streaming state - this is critical for UI to update
            isStreaming = false
            resetFinalizeState()

            // Mark any incomplete agent message as complete
            markLastMessageComplete()

            // Add system message indicating cancellation
            let cancelMessage = MessageItem(
                id: UUID().uuidString,
                role: .system,
                content: "Agent stopped by user",
                timestamp: Date()
            )
            messages.append(cancelMessage)

            // Clear current thought
            clearThoughtBuffer()
            currentThought = nil
        } catch {
            // Still reset streaming state even on error
            isStreaming = false
            resetFinalizeState()
            clearThoughtBuffer()
        }
    }

    /// Create an image content block from a file URL
    func createImageBlock(from url: URL) async throws -> ContentBlock {
        // Ensure we can access the file
        guard url.startAccessingSecurityScopedResource() else {
            throw AgentSessionError.custom("Cannot access file: \(url.lastPathComponent)")
        }
        defer { url.stopAccessingSecurityScopedResource() }

        // Check file size (limit to 10MB)
        let maxFileSize = 10 * 1024 * 1024  // 10MB
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let fileSize = fileAttributes[.size] as? Int64, fileSize > maxFileSize {
            throw AgentSessionError.custom(
                "Image too large: \(url.lastPathComponent) (\(fileSize / 1024 / 1024)MB). Maximum size is 10MB."
            )
        }

        // Get MIME type
        let mimeType = getMimeType(for: url) ?? "image/png"

        // Read image data
        let data = try await readDataFileAsync(url: url)

        let imageContent = ImageContent(
            data: data.base64EncodedString(),
            mimeType: mimeType,
            uri: url.absoluteString
        )
        return .image(imageContent)
    }

    /// Create a resource content block from a file URL
    func createResourceBlock(from url: URL) async throws -> ContentBlock {
        // Ensure we can access the file
        guard url.startAccessingSecurityScopedResource() else {
            throw AgentSessionError.custom("Cannot access file: \(url.lastPathComponent)")
        }
        defer { url.stopAccessingSecurityScopedResource() }

        // Check file size (limit to 10MB)
        let maxFileSize = 10 * 1024 * 1024  // 10MB
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let fileSize = fileAttributes[.size] as? Int64, fileSize > maxFileSize {
            throw AgentSessionError.custom(
                "File too large: \(url.lastPathComponent) (\(fileSize / 1024 / 1024)MB). Maximum size is 10MB."
            )
        }

        // Get MIME type
        let mimeType = getMimeType(for: url)

        // Determine if file is text or binary based on MIME type
        let isTextFile =
            mimeType?.hasPrefix("text/") ?? false || mimeType == "application/json"
            || mimeType == "application/xml" || mimeType == "application/javascript"

        if isTextFile {
            // Read as text asynchronously
            let text = try await readTextFileAsync(url: url)
            let textResource = EmbeddedTextResourceContents(
                text: text,
                mimeType: mimeType,
                uri: url.absoluteString,
                _meta: nil
            )
            let resourceContent = ResourceContent(
                resource: .text(textResource),
                annotations: nil,
                _meta: nil
            )
            return .resource(resourceContent)
        } else {
            // Read as binary asynchronously and base64 encode
            let data = try await readDataFileAsync(url: url)
            let base64 = data.base64EncodedString()
            let blobResource = EmbeddedBlobResourceContents(
                blob: base64,
                mimeType: mimeType,
                uri: url.absoluteString,
                _meta: nil
            )
            let resourceContent = ResourceContent(
                resource: .blob(blobResource),
                annotations: nil,
                _meta: nil
            )
            return .resource(resourceContent)
        }
    }

    /// Asynchronously read text file
    private func readTextFileAsync(url: URL) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let text = try String(contentsOf: url, encoding: .utf8)
                    continuation.resume(returning: text)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Asynchronously read binary file
    private func readDataFileAsync(url: URL) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let data = try Data(contentsOf: url)
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Get MIME type from file URL
    func getMimeType(for url: URL) -> String? {
        if let utType = UTType(filenameExtension: url.pathExtension) {
            return utType.preferredMIMEType
        }
        return nil
    }

    // MARK: - Message Management

    func addUserMessage(_ content: String, contentBlocks: [ContentBlock] = []) {
        let messageId = UUID()
        messages.append(
            MessageItem(
                id: messageId.uuidString,
                role: .user,
                content: content,
                timestamp: Date(),
                contentBlocks: contentBlocks
            ))
        trimMessagesIfNeeded()
        
        if let chatSessionId = chatSessionId {
            Task {
                let bgContext = PersistenceController.shared.container.newBackgroundContext()
                do {
                    try await bgContext.perform {
                        let fetchRequest: NSFetchRequest<ChatSession> = ChatSession.fetchRequest()
                        fetchRequest.predicate = NSPredicate(format: "id == %@", chatSessionId as CVarArg)
                        fetchRequest.fetchLimit = 1
                        
                        guard let session = try bgContext.fetch(fetchRequest).first else {
                            throw SessionPersistenceError.chatSessionNotFound(chatSessionId)
                        }
                        
                        session.messageCount += 1
                        session.lastMessageAt = Date()
                        
                        try bgContext.save()
                    }
                    
                    try await self.persistMessage(
                        id: messageId,
                        role: "user",
                        content: content,
                        contentBlocks: contentBlocks,
                        chatSessionId: chatSessionId
                    )
                } catch {
                }
            }
        }
    }

    func markLastMessageComplete() {
        flushAgentMessageBuffer()
        if let lastIndex = messages.lastIndex(where: { $0.role == .agent && !$0.isComplete }) {
            let completedMessage = messages[lastIndex]
            let completionTimestamp = Date()
            let executionTime = completedMessage.startTime.map { completionTimestamp.timeIntervalSince($0) }
            let updatedMessage = MessageItem(
                id: completedMessage.id,
                role: completedMessage.role,
                content: completedMessage.content,
                timestamp: completedMessage.timestamp,
                toolCalls: completedMessage.toolCalls,
                contentBlocks: completedMessage.contentBlocks,
                isComplete: true,
                startTime: completedMessage.startTime,
                executionTime: executionTime,
                requestId: completedMessage.requestId
            )
            var updatedMessages = messages
            updatedMessages[lastIndex] = updatedMessage
            messages = updatedMessages
            
            if let chatSessionId = chatSessionId,
               let messageId = UUID(uuidString: completedMessage.id) {
                let toolCallsToPersist = toolCalls.filter {
                    !persistedToolCallIds.contains($0.toolCallId) && $0.timestamp <= completionTimestamp
                }
                Task {
                    do {
                        try await self.persistMessage(
                            id: messageId,
                            role: "agent",
                            content: completedMessage.content,
                            contentBlocks: completedMessage.contentBlocks,
                            chatSessionId: chatSessionId,
                            toolCalls: toolCallsToPersist
                        )
                        self.persistedToolCallIds.formUnion(toolCallsToPersist.map { $0.toolCallId })
                    } catch {
                    }
                }
            }
        }
    }

    func addAgentMessage(
        _ content: String,
        toolCalls: [ToolCall] = [],
        contentBlocks: [ContentBlock] = [],
        isComplete: Bool = true,
        startTime: Date? = nil,
        requestId: String? = nil
    ) {
        let messageId = UUID()
        let newMessage = MessageItem(
            id: messageId.uuidString,
            role: .agent,
            content: content,
            timestamp: Date(),
            toolCalls: toolCalls,
            contentBlocks: contentBlocks,
            isComplete: isComplete,
            startTime: startTime,
            executionTime: nil,
            requestId: requestId
        )
        messages.append(newMessage)
        trimMessagesIfNeeded()
    }

    func addSystemMessage(_ content: String) {
        messages.append(
            MessageItem(
                id: UUID().uuidString,
                role: .system,
                content: content,
                timestamp: Date()
            ))
        trimMessagesIfNeeded()
    }

    private func trimMessagesIfNeeded() {
        let excess = messages.count - Self.maxMessageCount
        guard excess > 0 else { return }
        messages.removeFirst(excess)
    }
    
    private func persistMessage(
        id: UUID,
        role: String,
        content: String,
        contentBlocks: [ContentBlock],
        chatSessionId: UUID,
        toolCalls: [ToolCall] = []
    ) async throws {
        let context = PersistenceController.shared.container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        let agentName = self.agentName
        
        try await context.perform {
            let fetchRequest: NSFetchRequest<ChatSession> = ChatSession.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", chatSessionId as CVarArg)
            fetchRequest.fetchLimit = 1
            
            guard let chatSession = try context.fetch(fetchRequest).first else {
                throw NSError(domain: "AgentSession", code: 1, userInfo: [NSLocalizedDescriptionKey: "ChatSession not found"])
            }
            
            let chatMessage = ChatMessage(context: context)
            chatMessage.id = id
            chatMessage.role = role
            chatMessage.timestamp = Date()
            chatMessage.agentName = agentName
            
            let encoder = JSONEncoder()
            if let contentJSON = try? encoder.encode(contentBlocks),
               let jsonString = String(data: contentJSON, encoding: .utf8) {
                chatMessage.contentJSON = jsonString
            } else {
                chatMessage.contentJSON = content
            }

            chatMessage.session = chatSession

            if !toolCalls.isEmpty {
                for call in toolCalls {
                    let record = ToolCallRecord(context: context)
                    record.id = call.toolCallId
                    record.title = call.title
                    record.kind = call.kind?.rawValue ?? ToolKind.other.rawValue
                    record.status = call.status.rawValue
                    record.timestamp = call.timestamp
                    if let encoded = try? encoder.encode(call),
                       let jsonString = String(data: encoded, encoding: .utf8) {
                        record.contentJSON = jsonString
                    } else if let encoded = try? encoder.encode(call.content),
                              let jsonString = String(data: encoded, encoding: .utf8) {
                        record.contentJSON = jsonString
                    } else {
                        record.contentJSON = ""
                    }
                    record.message = chatMessage
                }
            }

            try context.save()
        }
    }
}
