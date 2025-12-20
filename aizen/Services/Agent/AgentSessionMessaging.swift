//
//  AgentSessionMessaging.swift
//  aizen
//
//  Messaging logic for AgentSession
//

import Foundation
import UniformTypeIdentifiers
import os.log

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

        // Start new iteration - previous tool calls remain visible but will be collapsed
        currentIterationId = UUID().uuidString

        // Mark any incomplete agent message as complete before starting new conversation turn
        markLastMessageComplete()

        // Build content blocks array
        var contentBlocks: [ContentBlock] = []

        // Collect text-based attachments to prepend to message
        var prependedContent = ""
        for attachment in attachments {
            if let attachmentContent = attachment.contentForAgent {
                prependedContent += attachmentContent + "\n\n"
            }
        }

        // Add text content (with attachments prepended if any)
        let fullContent = prependedContent.isEmpty ? content : prependedContent + content
        contentBlocks.append(.text(TextContent(text: fullContent, annotations: nil, _meta: nil)))

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

            case .file(let url):
                // Check if it's an image file
                if attachment.isImage {
                    if let imageBlock = try? await createImageBlock(from: url) {
                        contentBlocks.append(imageBlock)
                    }
                } else {
                    if let resourceBlock = try? await createResourceBlock(from: url) {
                        contentBlocks.append(resourceBlock)
                    }
                }

            case .reviewComments, .buildError:
                // These are handled above via contentForAgent
                break
            }
        }

        // Add user message to UI with all content blocks
        addUserMessage(content, contentBlocks: contentBlocks)

        // Mark streaming active before sending
        isStreaming = true

        // Send to agent - notifications arrive asynchronously via AsyncStream
        // Response comes AFTER all notifications are sent, but our notification
        // listener Task may not have processed them all yet
        let response = try await client.sendPrompt(sessionId: sessionId, content: contentBlocks)

        logger.debug("Prompt response received with stop reason: \(response.stopReason.rawValue)")

        // Delay setting isStreaming = false to allow buffered notifications to be processed
        // The AsyncStream may still have notifications queued that need to update messages
        // Setting @Published properties during view updates causes undefined behavior
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            self.isStreaming = false
            logger.debug("Streaming ended after notification drain")
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

            // Add system message indicating cancellation
            let cancelMessage = MessageItem(
                id: UUID().uuidString,
                role: .system,
                content: "Agent stopped by user",
                timestamp: Date()
            )
            messages.append(cancelMessage)

            // Clear current thought
            currentThought = nil
        } catch {
            logger.error("Error cancelling prompt: \(error.localizedDescription)")
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
        messages.append(
            MessageItem(
                id: UUID().uuidString,
                role: .user,
                content: content,
                timestamp: Date(),
                contentBlocks: contentBlocks
            ))
        trimMessagesIfNeeded()
    }

    func markLastMessageComplete() {
        if let lastIndex = messages.lastIndex(where: { $0.role == .agent && !$0.isComplete }) {
            let completedMessage = messages[lastIndex]
            let executionTime = completedMessage.startTime.map { Date().timeIntervalSince($0) }
            messages[lastIndex] = MessageItem(
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
        let newMessage = MessageItem(
            id: UUID().uuidString,
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
}
